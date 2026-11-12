# on-demand-isr

On-demand incremental static regeneration — this repository's own GitHub
issues as pages, each issue a page with its comments and its Markdown and
code highlighted — on **Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), built from
Vercel's [On-Demand ISR](https://vercel.com/templates/next.js/on-demand-incremental-static-regeneration)
template, [vercel/on-demand-isr](https://github.com/vercel/on-demand-isr) (MIT —
`apps/web/LICENSE.md`). Every page, and every read of GitHub behind it, is
cached with `"use cache"` in an **R2 bucket** that Terraform provisions per
environment; the tag cache and the revalidation queue are **Durable Objects**
the Worker itself exports. When an issue changes, your GitHub App's webhook —
its signature checked — drops the pages that show it, and the next visit
renders them again.

It is live from its first deploy, before any GitHub App is connected: `/`
lists **sample issues** under a notice that says how to connect one. Once you
give the deploy your App's ID, private key and webhook secret, it lists
[this repository's issues](https://github.com/sourceplane/on-demand-isr/issues).

## Live deployment

<!-- 02-docs:begin -->
Not recorded yet. The bootstrap's last phase writes the live URLs, the
workspace, whether the GitHub App is connected and the secrets the site uses
into [ai/context/deployment.md](ai/context/deployment.md); how the site
deploys and how to operate it is in
[ai/context/operations.md](ai/context/operations.md).
<!-- 02-docs:end -->

## What is here

| Surface | Where |
|---|---|
| The pages: `/` (the repository's issues under the template's explanation) and `/<number>` (one issue with its comments, Markdown rendered by `marked` and highlighted by `highlight.js`); `/api/webhook` (GitHub's deliveries) and `/api/health` | `apps/web/app` |
| The site's name and the repository it lists | `apps/web/app/site.ts` (`SITE_NAME`, `SOURCE_URL`) |
| The GitHub App client: its RS256 JWT, the installation token, the cached reads | `apps/web/lib/github.ts` |
| The App's settings, read per request, and whether it is connected | `apps/web/lib/settings.ts` |
| What the site shows until it is: the sample issues and the notice | `apps/web/lib/sample.ts`, `apps/web/app/connect-notice.tsx` |
| The template's stylesheet (compiled by `sass` at build) | `apps/web/styles` |
| Workers build, cache bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ `wrangler.jsonc`), `component.yaml` |
| The R2 bucket (stage, prod) | `infra/terraform/cloudflare-r2` |
| Tests | `tests/web` (vitest: the App's JWT and installation token against an in-process GitHub, the webhook's signature check, the pages rendered) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

None of these needs a GitHub App: with none the site lists its sample issues.
To work against yours, copy `apps/web/.env.example` to `apps/web/.env.local`
and set the App's three settings, then:

```bash
pnpm --filter @app/web dev        # http://localhost:3000, Next's dev server
pnpm --filter @app/web preview    # wrangler dev over the built Worker, a local R2 bucket and local Durable Objects
```

## Connecting a GitHub App

The site reads this repository's issues as a **GitHub App** installed on it,
and the App's webhook tells the site when an issue changes. A GitHub App has
one webhook URL, so an App regenerates one environment: create one for
`prod`, and a second for `stage` if stage should regenerate on demand too (it
re-reads GitHub every 15 minutes either way, the template's cache lifetime).

1. **Create the App** — under the account that owns this repository
   (Settings → Developer settings → GitHub Apps → New GitHub App):
   - **Homepage URL**: the site, `https://on-demand-isr-web-prod.your-workers-subdomain.workers.dev`.
   - **Webhook**: active; **URL** `https://on-demand-isr-web-prod.your-workers-subdomain.workers.dev/api/webhook`;
     a **secret** — a long random string you keep for step 3.
   - **Repository permissions**: **Issues — Read-only** (Metadata stays
     read-only, as GitHub requires).
   - **Subscribe to events**: **Issues** and **Issue comment**.
2. **Install it** on this repository (the App's page → Install App → only
   select repositories → this one), and on the App's settings page note its
   **App ID** and **generate a private key** (GitHub downloads a `.pem`).
3. **Give the deploy the App**, once per environment. The three are this
   repository's Orun secrets:

   ```bash
   orun secrets set GITHUB_APP_ID --env prod                   # prompts for the value
   orun secrets set GITHUB_APP_PK_PEM --env prod < app.private-key.pem
   orun secrets set GITHUB_WEBHOOK_SECRET --env prod
   ```

   and the same with `--env stage` (its own App, or the same ID and key and
   no webhook of its own). Then **redeploy the site**: a secret is read when
   the site deploys, and setting one deploys nothing. Use **Deploy by hand**
   below, or change the stamp on the last line of `apps/web/component.yaml`
   (`# orun: redeploy …`) and merge. None of the three is ever in the build:
   the deploy puts them on the Worker as secrets, and the site reads them per
   request. From that deploy on, `/` lists this repository's issues.
4. **Check it**: open an issue on this repository and refresh the page. GitHub
   shows each delivery under the App's **Advanced** tab; `Success!` is the
   webhook's answer, and a delivery whose signature does not match the
   secret is refused (`Invalid signature.`, 400).

Until `GITHUB_WEBHOOK_SECRET` is set, `/api/webhook` refuses every delivery
(503): with no secret, anyone could sign one.

## How on-demand ISR works here

The issues `/` and `/<number>` show are read through `"use cache"` functions
(`apps/web/lib/github.ts`), and each page is rendered once and kept: the
Worker binds the bucket as `NEXT_INC_CACHE_R2_BUCKET` (every rendered page and
`"use cache"` entry), and two Durable Objects — `NEXT_TAG_CACHE_DO_SHARDED`
(which paths were revalidated, and when) and `NEXT_CACHE_DO_QUEUE`
(background revalidation of stale entries, through the Worker's own
`WORKER_SELF_REFERENCE` binding). A visit reads the cache, not GitHub.

A webhook delivery whose `x-hub-signature-256` is the HMAC-SHA256 of its body
under `GITHUB_WEBHOOK_SECRET` calls `revalidatePath('/')` and
`revalidatePath('/<number>')` for the issue it names; the next visit to each
renders it again from GitHub and caches it until the next change. Without a
webhook, an entry is refreshed in the background after 15 minutes, the
template's lifetime.

The cache is keyed by the build: a new deploy starts with an empty cache and
renders each page on its first visit with the Worker's current settings —
which is why connecting the App takes a redeploy and nothing more.

The bucket's name is never hand-written: `apps/web/wrangler.template.jsonc`
names it as a wiring token, and `wrangler.jsonc` is that template rendered —
from `wiring.fixture.json` for local work and verification, and on every
deploy from the document the `cloudflare-r2` Terraform root publishes after
its apply (`WIRING_CLOUDFLARE_R2`, per environment). Edit the template, then
`pnpm run wire:fixture` and commit the render with the template. The Durable
Objects need no root: the migration in the config creates them on the first
deploy.

## How it deploys

Merges to `main` converge through [Orun](https://github.com/sourceplane/orun):
`.github/workflows/ci.yml` plans the changed components and runs each lane
against the workspace in `intent.yaml`. The R2 bucket applies first, then the
site builds for that environment and deploys — and the deploy hands the
GitHub App's settings, if set, to the Worker — to `stage`, then to `prod` once
stage has converged on the same commit; `dev` only verifies. The Worker is
`on-demand-isr-web-<env>` on your account's workers.dev subdomain, and
every deploy is smoke-tested over HTTP: the home page must answer, and so
must `/api/health`, which only the Worker can. A pull request runs the same
pipeline's verify lanes, with nothing applied or deployed: the R2 bucket
planned for stage and prod, and the site built and dry-deployed for each
environment. They do not run the tests or the linter — run those before you
push (Getting started, above). (A push to `main` applies, builds and
deploys.)

The pipeline holds one credential, GitHub's own `GITHUB_TOKEN`. The Cloudflare
tokens and account id are brokered per run from the workspace's Cloudflare
connection — one to deploy the Worker, one with R2 access for the bucket's
apply — and the bucket names and the App's three settings travel as Orun
secrets; nothing provider-shaped is stored in the repository or in GitHub.

**Deploy by hand.** Orunbase's **Deploy** button on a component, or **Run
workflow** on the CI workflow in GitHub's Actions tab (on `main`), runs
`ci.yml` for the environment and components you pick, and each one deploys
exactly as a merge would deploy it. Leave the component blank to redeploy
every component in that environment, with nothing changed: after connecting
your GitHub App, say. A component with nothing to run in that environment (a
test suite in `prod`) is left out with a notice.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting (SSR, route handlers, ISR) | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets (`ASSETS`) |
| `"use cache"` (`experimental.useCache`) and its default lifetime | Kept as written: the pages and their GitHub reads cached, refreshed after 15 minutes |
| The ISR and Data Cache | The R2 bucket bound as `NEXT_INC_CACHE_R2_BUCKET`, keyed by the build |
| `revalidatePath` from the webhook | Kept; a sharded Durable Object tag cache records each revalidation, consulted on every cache read |
| Stale-while-revalidate | A Durable Object queue that re-renders stale entries through the Worker |
| `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM`, `GITHUB_WEBHOOK_SECRET` (Vercel environment variables) | Orun secrets the deploy puts on the Worker, read per request, never in the build; sample issues until the first two are set, the webhook shut until the third is |
| The `nextjs/on-demand-isr` repository and the `nextjs` installation | This repository (`SOURCE_URL`, `apps/web/app/site.ts`) and its owner's installation |
| Image Optimization (`/_next/image`) | Off (`images.unoptimized`): avatars come from GitHub's image host as they are |
| Deploy on push | Orun applies the bucket and deploys `on-demand-isr-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |

## Custom domain

The site answers on workers.dev from its first deploy. To serve it on your
own domain:

1. Add the domain to the Cloudflare account the site deploys into, and attach
   it to the Worker (dashboard → Workers & Pages →
   `on-demand-isr-web-prod` → Settings → Domains & Routes → Add →
   Custom domain).
2. Point the GitHub App's **Homepage URL** and **Webhook URL** at the domain.
3. The site was born with the reserved placeholder
   `on-demand-isr.example.com` where its domain goes: `BASE_DOMAIN` under
   each environment in `intent.yaml`. Replace it with your domain.

## Licence

The site is Vercel's On-Demand ISR template, under the MIT licence
(`apps/web/LICENSE.md`).
