# on-demand-isr

Vercel's [On-Demand ISR](https://vercel.com/templates/next.js/on-demand-incremental-static-regeneration)
template, [vercel/on-demand-isr](https://github.com/vercel/on-demand-isr) — a
repository's GitHub issues as statically generated pages, each issue a page
with its comments as highlighted Markdown, regenerated on demand when a GitHub
App's webhook says an issue changed (`revalidatePath`) — running on
**Cloudflare Workers + Static Assets** through
[`@opennextjs/cloudflare`](https://opennext.js.org/cloudflare), with the
Next.js page and data cache in an **R2 bucket** provisioned by Terraform
through [Orun](https://github.com/sourceplane/orun) and the tag cache and
revalidation queue in **Durable Objects** the Worker itself exports, deployed by
[Orun](https://github.com/sourceplane/orun) to stage and prod on every merge.
Packaging it as an Orun baseline is the next milestone (OI2).

A fresh build needs no GitHub App: until its owner connects one, `/` lists
sample issues under a notice that says how — never a 500 — and the webhook
refuses every delivery. The owner connects an App by setting its ID, private
key and webhook secret as Orun secrets and redeploying; the site then lists
its own repository's issues. The Worker is about 1.3 MiB gzipped, inside
Workers Free's 3 MiB. See [`specs/epics/on-demand-isr`](specs/epics/on-demand-isr/README.md)
for the design, the milestones and the as-built status.

## What is here (the product)

| Surface | Where |
|---|---|
| The pages: `/` (the issues), `/<number>` (one issue and its comments), `/api/webhook`, `/api/health` | `apps/web/app` |
| The site's name and the repository it lists | `apps/web/app/site.ts` (`SITE_NAME`, `SOURCE_URL`) |
| The GitHub App client (RS256 JWT, installation token, cached reads) and its settings, read per request | `apps/web/lib/github.ts`, `apps/web/lib/settings.ts` |
| What the site shows until an App is connected | `apps/web/lib/sample.ts`, `apps/web/app/connect-notice.tsx` |
| Workers build, cache bindings and deploy contract | `apps/web/next.config.ts`, `open-next.config.ts`, `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `component.yaml` |
| The R2 bucket (stage, prod) | `infra/terraform/cloudflare-r2` |
| The wrangler renderer, and the step that puts the App's settings on the Worker | `tooling/wire` |
| Tests | `tests/web` (the seam, the settings, the App's JWT and token against an in-process GitHub, the webhook's signature check, the pages rendered) |

## Getting started

```bash
pnpm install
pnpm run wire:fixture   # render apps/web/wrangler.jsonc from the offline fixture
pnpm typecheck
pnpm lint
pnpm test
pnpm build              # next build + opennextjs-cloudflare build → apps/web/.open-next
```

```bash
pnpm --filter @app/web dev        # http://localhost:3000, Next's dev server
pnpm --filter @app/web preview    # wrangler dev over the built Worker, a local R2 bucket and local Durable Objects
```

With no App settings both serve the sample issues. To run against an App, put
its three settings in `apps/web/.env.local` (from `apps/web/.env.example`).
Offline, `testing/lib/fake-github.mjs` answers the App and Issues APIs for one
repository (it checks every JWT with the App's public key), and
`testing/e2e.test.sh` serves the built Worker against it through a test-only
entry, `testing/lib/e2e-worker.mjs`.

## How it maps to Vercel

| Vercel | Here |
|---|---|
| Next.js hosting (SSR, route handlers, ISR) | One Cloudflare Worker (`.open-next/worker.js`) + Static Assets (`ASSETS`) |
| `"use cache"` (`experimental.useCache`), its default lifetime | Kept as written: pages and GitHub reads cached, refreshed in the background after 15 minutes |
| The ISR and Data Cache | The R2 bucket bound as `NEXT_INC_CACHE_R2_BUCKET`, keyed by the build |
| `revalidatePath` | A sharded Durable Object tag cache (`NEXT_TAG_CACHE_DO_SHARDED`) consulted on every cache read |
| Stale-while-revalidate | A Durable Object queue (`NEXT_CACHE_DO_QUEUE`) that re-renders stale entries through the Worker's `WORKER_SELF_REFERENCE` binding |
| Image Optimization | Off (`images.unoptimized`): avatars come from GitHub's image host |
| `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM`, `GITHUB_WEBHOOK_SECRET` | Orun secrets each deploy puts on the Worker, read per request; the build never sees them. Without the first two the sample issues; without the third the webhook answers 503 (upstream keyed its HMAC with an empty string) |
| The `nextjs/on-demand-isr` repository, the `nextjs` installation | The product's own repository (`SOURCE_URL`) and its owner's installation |
| Deploy on push | Orun applies the bucket and deploys `<repo>-web-{stage,prod}` on merge to `main` (`apps/web/component.yaml`) |
| "Deploy with Vercel" (clone the template) | `orun new --blueprint repo-blueprint.yaml` — a new repository, branded, deployed |

Next.js moves from 15.3.6 to 15.5.29, the floor of the 15 line
`@opennextjs/cloudflare` 1.20.16 accepts. The epic's
[IMPLEMENTATION-STATUS](specs/epics/on-demand-isr/IMPLEMENTATION-STATUS.md)
lists every departure and its evidence.

## How the bucket reaches the Worker

```
infra/terraform/cloudflare-r2 ──apply (r2-data token)──► orun secret WIRING_CLOUDFLARE_R2 (stage, prod)
                                               │   (each deploy resolves it as it starts;
                                               │    a missing one fails the lane)
                                               ▼
apps/web  dependsOn cloudflare-r2 (enforced on main) · secretEnv WIRING_CLOUDFLARE_R2_<ENV>
  build:  tooling/wire/live.mjs → wrangler.jsonc with the environment's bucket name
          (dev, verify-only, renders the fixture) → next build (no App settings: env -u)
          → opennextjs-cloudflare → tooling/wire/worker-secrets.mjs puts the App's settings on the Worker
  deploy: workers-deploy token → <repo>-web-<env>, its Durable Objects migrated on first deploy
```

`wrangler.jsonc` is committed as the fixture render of
`wrangler.template.jsonc`, because the deploy lane's `verify-app-structure`
step checks the config exists before it builds; `testing/e2e.test.sh` fails
if the two disagree.

## CI

| Workflow | What it runs | Ships to a product |
|---|---|---|
| `ci.yml` | the Orun pipeline, and the only workflow a product carries: `orun plan --changed`, then one job per lane. A pull request runs the verify lanes (the R2 root planned for stage and prod, the site built and dry-deployed per environment; they neither lint nor run the tests, which `baseline.yml`'s e2e tier runs before every tag), except the bootstrap's own landings (`orun/BASE-*`), where `plan` alone runs and nothing waits for it (the landing checked its commit in the box); a merge applies the R2 bucket, then deploys stage → prod. It plans nothing while `intent.yaml` names the placeholder workspace `ws_CHANGE_ME`, as this repository does. A manual run (Orunbase's Deploy button, or Run workflow on `main`) plans the environment and components it names under the push-to-main trigger, so they deploy as a merge deploys them | yes |
