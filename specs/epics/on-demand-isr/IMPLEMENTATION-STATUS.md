# on-demand-isr — implementation status

| Milestone | State | Landed |
|---|---|---|
| OI0 — the spec | ✅ | OI-1 |
| OI1 — the site on Workers | ✅ | OI-2 |
| OI2 — a baseline | ✅ | OI-3, tagged `baseline-v1` |

## Departures from the upstream template

Everything not listed here is vercel/on-demand-isr as it is at `2e96485`.

| # | What | Why |
|---|---|---|
| 1 | The app lives in `apps/web` of a pnpm workspace (`@app/web`); its dependencies pinned to upstream's locked versions (`highlight.js` 11.11.1, `jsonwebtoken` 9.0.2, `marked` 15.0.7, `marked-highlight` 2.2.1, `sass` 1.85.0, `server-only` 0.0.1); `dev`/`start` on port 3000; upstream's lockfile, `.vscode/settings.json` (a TypeScript 4.9.4 path) and `bun dev` not carried | The workspace's shape |
| 2 | `next` 15.3.6 → 15.5.29 with `@opennextjs/cloudflare` 1.20.16, both pinned; `react`/`react-dom` 19.0.0 → 19.2.5 | The adapter accepts `>=15.5.29 <16` on the 15 line; React to its current 19 patch |
| 3 | `next.config.ts`: `output: "standalone"`, `outputFileTracingRoot` at the workspace root, `images.unoptimized` (the avatar `remotePatterns` kept), `allowedDevOrigins` for the live preview, `initOpenNextCloudflareForDev()`; `experimental.useCache`, `inlineCss` and `logging` kept | OpenNext's build and bindings |
| 4 | `open-next.config.ts` (R2 incremental cache, sharded Durable Object tag cache, Durable Object queue), `wrangler.template.jsonc` + `wiring.fixture.json` (→ the committed `wrangler.jsonc`), `cloudflare-env.d.ts`, `next-types.d.ts`; no populateCache | The cache on Workers; each page rendered on its first visit with the Worker's settings (design §4) |
| 5 | `tsconfig.json` excludes `open-next.config.ts`, `.open-next` and `.wrangler` (upstream's options kept, `moduleResolution: "node"` included) | That resolution cannot type the adapter's `config` export, and Next's build type-checks the file |
| 6 | `lib/settings.ts`: `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` and `GITHUB_WEBHOOK_SECRET` read per request from the Worker's env, else `process.env`; `lib/github.ts` and the webhook read them through it | A Worker's settings are its secrets, which the deploy puts there |
| 7 | `lib/github.ts`: the repository is `REPOSITORY` from `app/site.ts`'s `SOURCE_URL` (upstream: `nextjs/on-demand-isr`), the installation the one on its owner, compared without case (upstream: `nextjs`); a clear error when there is none (upstream: a `TypeError`); the missing-settings error names the Orun secrets | The site lists its own repository |
| 8 | `lib/sample.ts` and `app/connect-notice.tsx`: with no App ID or key, the readers answer three sample issues and call GitHub for nothing, and `/` and `/<number>` show a notice linking the README's "Connecting a GitHub App"; the readers return `connected` | A product deploys before its owner connects an App; upstream failed on its first read without one |
| 9 | `app/api/webhook`: 503 while `GITHUB_WEBHOOK_SECRET` is unset; signed deliveries as upstream (HMAC-SHA256 of the raw body, `timingSafeEqual`, `revalidatePath('/')` and the issue's page) | Upstream keyed its HMAC with `''` when the secret was unset, which anyone can compute |
| 10 | `app/api/health/route.ts` | The deploy's smoke and the record's probe |
| 11 | `app/site.ts`: `SITE_NAME = "On-Demand Incremental Static Regeneration"` (upstream's title without " with Next.js") and `SOURCE_URL`; the layout's title reads `SITE_NAME`, and a description is added | One rename seam; upstream's full title is over the card's 48-character name pattern |
| 12 | The repository links in `/`, `/[id]` and the explanation read `SOURCE_URL` (owner, name, fork, issues, new issue); the explanation's "pushed to the edge", "a Serverless Function is invoked" and "about 300ms~ to propagate to the global Vercel Edge Network" now describe the Worker and its R2 cache | The product is not on Vercel, and its repository is its own |
| 13 | ESLint with the workspace's shared config (upstream ships none); its 13 warnings — upstream's `console.log` and `any` — kept | The workspace's lint lane |
| 14 | `tests/web` (vitest, 35 tests): the seam, the settings, the App's JWT and installation token against an in-process GitHub, the readers connected and not, the webhook's signature check, `/api/health`, the pages rendered | Upstream ships no tests |
