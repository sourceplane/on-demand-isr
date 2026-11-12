# on-demand-isr — operating contract (for humans and agents)

This is the standing guide to how this site is deployed and operated.
Instance facts (live URLs, workspace, whether its GitHub App is connected,
the secrets it uses) live in [deployment.md](deployment.md), rendered from
probed reality by the bootstrap's `02-docs` phase; this file is the contract
that stays true between deployments. It is written to give an agent with
repository read access enough context to reason about and operate the site
without any other source.

## What this system is

On-demand incremental static regeneration on Cloudflare, expressed as an
Orun component-native desired-state repo: this repository's own GitHub
issues as pages, read through the owner's GitHub App and regenerated when the
App's webhook says an issue changed. GitHub itself — the issues, the App and
its installation — is the owner's; nothing here runs GitHub.

- **`infra/terraform/cloudflare-r2`** — one R2 bucket per deployed
  environment (`stage`, `prod`), applied by Terraform: the site's Next.js
  page and data cache. After each apply it publishes a wiring document —
  `{r2_bucket_name}` — as the Orun secret `WIRING_CLOUDFLARE_R2` on that
  environment.
- **`apps/web`** — the site: Vercel's On-Demand ISR template built by
  `@opennextjs/cloudflare` into one Worker plus Static Assets. `/` and
  `/<number>` read GitHub through `"use cache"` functions
  (`lib/github.ts`): the App signs an RS256 JWT, exchanges it for an
  installation token, and reads the repository named by `SOURCE_URL`
  (`app/site.ts`). Each page is rendered once and cached in the bucket
  (`NEXT_INC_CACHE_R2_BUCKET`); the Worker exports two Durable Objects, the
  tag cache and the revalidation queue. `app/api/webhook` checks each
  delivery's signature and calls `revalidatePath`.
- **`tests/web`** — the site seam, the settings read per request, the App's
  JWT and installation token against an in-process GitHub, the webhook's
  signature check and the paths it revalidates, `/api/health`, and the pages
  rendered (vitest). It does not run in a lane: the `dev` lane of
  `tests/web` installs it and checks its structure, so run `pnpm typecheck`,
  `pnpm lint` and `pnpm test` before you push.
- **`tooling/*`** — shared TypeScript and ESLint configuration, the wrangler
  renderer that turns `wrangler.template.jsonc` plus a wiring document into
  `wrangler.jsonc`, and the step that puts the GitHub App's settings on the
  Worker after its build.

Environments: **`stage`** and **`prod`** are deployed; **`dev` is
verify-only by design** — lanes build and dry-deploy, nothing deploys, and
no bucket exists for it (its build renders the committed fixture).

The Worker is about 1.3 MiB gzipped, inside Workers Free's 3 MiB.

## Identity and tenancy

Every remote operation runs against ONE Orun workspace, declared in
`intent.yaml` under `execution.state.workspace` — committed, enforced, and
what CI uses. Do not remove it; headless credentials depend on it. If it
reads `ws_SET_ME`, the bootstrap had no workspace to write: set the real one
before anything else.

## How deployment works

1. Merge (or push) to `main`.
2. CI (`.github/workflows/ci.yml`) runs `orun plan --changed` — only
   components whose files changed are planned — then runs each planned lane
   with `orun run --remote-state`, authenticated by GitHub OIDC (the
   exchange resolves this repository's linked workspace server-side).
3. **The bucket before the Worker.** `cloudflare-r2` applies for the
   environment and publishes `WIRING_CLOUDFLARE_R2`. `apps/web` declares an
   enforced `dependsOn` on it for pushes to `main`, so its deploy starts only
   after that apply — and a job resolves its secrets when it starts, so the
   document is there.
4. `apps/web` renders `wrangler.jsonc` from that document (the real bucket
   name) and builds once per environment, without the GitHub App's settings
   (`env -u`): the build renders nothing from GitHub. Once it is done,
   `tooling/wire/worker-secrets.mjs` puts `GITHUB_APP_ID`,
   `GITHUB_APP_PK_PEM` and `GITHUB_WEBHOOK_SECRET` (those that are set) on
   `on-demand-isr-web-<env>`. `wrangler deploy` ships the Worker (the
   Durable Objects are created by the config's migration on the first
   deploy), and a smoke test fetches `/` and `/api/health`, which only the
   Worker answers.
5. `prod` deploys after `stage` has converged on the same commit
   (`environments.prod.promotion` in intent.yaml).
6. **The convergence run is the deployment.** A green run means every
   planned lane applied. Failed lanes are retried with
   `gh run rerun --failed`, which resumes the same execution.

On a pull request nothing applies or deploys: the R2 root plans, the site
builds and dry-deploys, and the edges in step 3 are advisory.

Caveats that matter:

- A push that touches no component files plans zero lanes — that run is
  green and deployed nothing. Never treat "latest run green" as "site
  converged"; probe the URLs instead.
- A change to `intent.yaml`'s `environments` maps to no component and
  redeploys nothing on its own. Land it with a change under `apps/web`.
- Setting or changing any `GITHUB_*` secret deploys nothing: the deploy puts
  them on the Worker. Redeploy it (below).
- `wrangler.jsonc` is generated. Edit `wrangler.template.jsonc`, run
  `pnpm run wire:fixture` and commit both; the deploy renders its own
  config from the template, so a stale committed render misleads local work.

## The pages and their cache

- **No GitHub App connected** (`GITHUB_APP_ID` or `GITHUB_APP_PK_PEM` unset
  on the Worker): the site calls GitHub for nothing; `/` lists three sample
  issues (`lib/sample.ts`) under a notice that says how to connect an App,
  each sample issue has its page, any other number is the 404 page, and
  `/api/health` answers `{"ok":true,"connected":false}`.
- **Connected**: `/` lists the issues of the repository in `SOURCE_URL`, with
  its stars and forks, and `/<number>` the issue with its comments (bots'
  left out, as the template does), Markdown rendered by `marked` and code
  highlighted by `highlight.js`. The App's installation is the one on the
  repository's owner; without it every uncached page answers 500 and the log
  says "no installation for <owner>". The installation token is kept per
  Worker isolate and refreshed when GitHub answers 401. `/api/health`
  answers `{"ok":true,"connected":true}`.
- **The cache**: each page and each `"use cache"` read of GitHub is stored in
  the bucket under the build's id, so a new deploy starts with an empty cache
  and renders each page on its first visit with the Worker's current
  settings. Entries are refreshed in the background after 15 minutes (the
  default `"use cache"` lifetime, the template's), and dropped at once by the
  webhook.
- **The webhook**: `POST /api/webhook` from the App. A delivery whose
  `x-hub-signature-256` is `sha256=` + the HMAC-SHA256 of its raw body under
  `GITHUB_WEBHOOK_SECRET` (compared in constant time) revalidates `/` and the
  page of the issue it names, and answers `Success!`; the next visit to each
  renders it again and caches it. Any other delivery answers 400 and drops
  nothing. With no `GITHUB_WEBHOOK_SECRET` the route answers 503 to
  everything — an HMAC keyed with an empty string would be anyone's to
  compute. A GitHub App has ONE webhook URL: an App regenerates one
  environment.

## Secrets model

- **Brokered provider secrets**: `CLOUDFLARE_API_TOKEN` (the
  `workers-deploy` scope: Workers Scripts and KV Storage write) deploys the
  Worker; `CLOUDFLARE_R2_TOKEN` (the `r2-data` scope: R2 Storage write) is
  what the R2 root's Terraform authenticates with, because the deploy token
  carries no R2; `CLOUDFLARE_ACCOUNT_ID` is the connection fact both bind.
  Minted per run from the workspace's Cloudflare connection — no long-lived
  values at rest, nothing to rotate by hand.
- **Wiring**: `WIRING_CLOUDFLARE_R2` on `stage` and `prod`, written by the R2
  root's apply (lease-published), read by the Worker's build as
  `WIRING_CLOUDFLARE_R2_<ENV>`. It holds the bucket name, not a credential.
- **The GitHub App**: `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` (the App's private
  key, the `.pem` GitHub generates) and `GITHUB_WEBHOOK_SECRET` per
  environment, Orun secrets the owner sets (`orun secrets set … --env
  <env>`; the key from a file on stdin), optional. The build never sees them
  (`env -u`); the deploy hands them to `wrangler secret bulk` on
  `on-demand-isr-web-<env>`, and the Worker reads them per request. The key
  can read the issues of every repository the App is installed on, nothing
  more (read-only Issues).
- Inspect by NAME only: `orun secrets list --org <ws> --project` and
  `--env stage|prod`; `wrangler secret list --name on-demand-isr-web-<env>`.
  No tooling in this repository prints a secret value, and no document in
  `ai/context/` may contain one.

## Verifying the system

```bash
# the site on each environment (also recorded, probed, in deployment.md);
# /api/health says whether the GitHub App is connected
curl -s https://on-demand-isr-web-stage.your-workers-subdomain.workers.dev/api/health
curl -s -o /dev/null -w '%{http_code}\n' https://on-demand-isr-web-prod.your-workers-subdomain.workers.dev/

# the wiring and the App's settings the deploys read, and workspace readiness
orun secrets list --org <ws> --env stage && orun secrets list --org <ws> --env prod
orun integrations list --org <ws> --json && orun cloud check --org <ws>
```

GitHub lists every webhook delivery and the site's answer under the App's
settings → Advanced → Recent deliveries, with a **Redeliver** button.

## Common operations

| task | how |
|---|---|
| change the site | edit `apps/web` (its name and the repository it lists: `apps/web/app/site.ts`), merge |
| connect a GitHub App | the README's "Connecting a GitHub App": create it (Issues read-only, Issues and Issue comment events, webhook at `/api/webhook` with a secret), install it on this repository, set the three `GITHUB_*` secrets per environment, then redeploy |
| list another repository | change `SOURCE_URL` in `apps/web/app/site.ts` and install the App on that repository's owner |
| regenerate a page by hand | Redeliver a delivery from the App's settings, or merge any change under `apps/web` (a new build starts an empty cache) |
| rotate the App's key or webhook secret | generate a new key (or secret) in the App's settings, set the Orun secret, redeploy, then delete the old key |
| deploy a change | merge to `main`; watch the run; failed lanes → `gh run rerun --failed` |
| deploy by hand | Orunbase's Deploy button, or `gh workflow run ci.yml --ref main -f environment=<env> [-f component=<a,b>]` — the named components (blank: every one) run in that environment as a merge runs them; started off `main` it is refused |
| redeploy without a change | edit the last line of `apps/web/component.yaml` (`# orun: redeploy <reason> <stamp>`) and merge — it is a deploy trigger, nothing reads it |
| empty the cache | redeploy (a new build id), or delete the bucket's `incremental-cache/` objects; old builds' objects stay in the bucket until deleted |
| add a binding (D1, KV, another bucket) | a Terraform root under `infra/terraform/` that publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its fixture entry, the root in the build's `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv and an enforced `dependsOn` on it in `apps/web/component.yaml` |
| serve a custom domain | attach it to the Worker in Cloudflare, point the App's homepage and webhook URLs at it (README, "Custom domain"), and replace the placeholder `on-demand-isr.example.com` in `intent.yaml`'s `BASE_DOMAIN` with it |
| add a runtime secret | an Orun secret in `optionalSecretEnv` (`apps/web/component.yaml`); `env -u` it from the build and add a `--secret` to the `worker-secrets.mjs` step, and read it with `setting()` (`apps/web/lib/settings.ts`) |
| headless credentials | `ORUN_TOKEN` (workspace-scoped) + `GITHUB_TOKEN` |

The deployment record is the bootstrap's `02-docs` phase. Re-running it (the
Orun console's Retry on that phase, or `orun new … --phase 02-docs`)
re-probes the URLs and re-renders [deployment.md](deployment.md); it is
idempotent.

## Evolution

Structural changes follow the same contract that deployed the site: add a
component under `apps/`, `infra/` or `packages/` with a `component.yaml`,
land it as a pull request, and the convergence run applies it. Next.js and
`@opennextjs/cloudflare` are pinned together (`apps/web/package.json`): the
adapter's peer range sets the lowest Next.js it accepts, so move both at
once.
