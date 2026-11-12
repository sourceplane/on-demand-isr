# on-demand-isr — design

## 1. The template

vercel/on-demand-isr (`2e96485`, Next.js 15.3.6, React 19, `sass`) is the
demo behind Vercel's On-Demand ISR template. `/` lists the issues of
`nextjs/on-demand-isr` with the repository's stars and forks under a short
explanation of on-demand ISR; `/<number>` shows one issue and its comments,
their Markdown rendered by `marked` with `highlight.js`. Both read GitHub
through `"use cache"` functions (`experimental.useCache`) in `lib/github.ts`,
which authenticates as a GitHub App: an RS256 JWT signed with the App's
private key (`jsonwebtoken`), exchanged for an installation token, refreshed
when GitHub answers 401. `app/api/webhook` receives the App's deliveries,
checks `x-hub-signature-256` (HMAC-SHA256 of the raw body under
`GITHUB_WEBHOOK_SECRET`, `timingSafeEqual`) and calls `revalidatePath('/')`
and `revalidatePath('/<number>')`. With no other `cacheLife`, the reads take
the default profile: refreshed after 15 minutes.

## 2. How Vercel maps to Cloudflare

| Vercel | Cloudflare |
|---|---|
| Next.js hosting | One Worker built by `@opennextjs/cloudflare`, plus Static Assets |
| The ISR and Data Cache behind `"use cache"` | An R2 bucket (`NEXT_INC_CACHE_R2_BUCKET`), provisioned per environment by Terraform |
| `revalidatePath` | A sharded Durable Object tag cache every cache read consults |
| Background revalidation | A Durable Object queue calling the Worker back (`WORKER_SELF_REFERENCE`) |
| Environment variables | Orun secrets the deploy puts on the Worker |
| Deploy on push | Orun's convergence: the bucket applied, then the Worker deployed |

## 3. The cache

OpenNext's static-assets cache refuses `"use cache"` entries ("Composable
cache is not supported"), so the template needs a cache that stores them —
R2, as the commerce baselines use — and `revalidatePath` needs a tag cache
consulted on every read, which a Durable Object gives with strong
consistency. The commerce baselines' `open-next.config.ts` is this one's.
The bucket's name reaches the Worker as a wiring document the R2 root
publishes; the Durable Objects are the Worker's own classes, created by a
migration on the first deploy. OpenNext keys every entry by the build id.

## 4. The spike

In a scratch copy, before anything was ported (`~/orunbase/spikes/on-demand-isr.md`):

- **The build.** Next 15.5.29 on @opennextjs/cloudflare 1.20.16 (its floor on
  the 15 line), `useCache` and `inlineCss` kept: `○ /` (Revalidate 15m),
  `● /[id]`, `ƒ /api/webhook`; `sass` compiled the stylesheet. The template's
  `moduleResolution: "node"` cannot type the adapter's `config` export, so
  `open-next.config.ts` is excluded from its tsconfig.
- **No populateCache.** The build has no App settings, so its prerender of
  `/` is the sample page. Not copying it into the bucket, the first request
  rendered `/` on demand ("Fetching … for /" logged at request time) and
  later ones were HITs. Because the cache is keyed by the build id, a
  redeploy starts empty and renders with the Worker's current settings:
  connecting an App is a redeploy.
- **On-demand ISR on workerd**, against a stand-in GitHub that verifies every
  JWT with the App's public key: `/` listed the repository's issue; the next
  visit was a HIT with no call to GitHub; an issue added upstream did not
  show; a delivery with a wrong signature was refused (400) and changed
  nothing; a signed one answered `Success!`, the next visit was a MISS
  listing both issues and the one after a HIT; the new issue's page
  rendered.
- **The App's JWT.** `jsonwebtoken` signed RS256 with a PKCS#1 key — the
  format GitHub issues — on workerd with `nodejs_compat`, and every JWT
  verified; `crypto.createHmac` and `timingSafeEqual` worked too. No swap to
  `jose`.
- **Size.** 5,941 KiB raw, 1,319 KiB gzipped: Workers Free.

## 5. The App's settings and the repository

`GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` and `GITHUB_WEBHOOK_SECRET` are optional
Orun secrets per environment. The build runs without them (`env -u`) and
`tooling/wire/worker-secrets.mjs` puts them on the Worker after it, so no
bundle carries them; `lib/settings.ts` reads them per request from the
Worker's env (`getCloudflareContext()`), else from `process.env` (`next
dev`, the tests). The repository is the site's own: `SOURCE_URL` in
`app/site.ts`, which the rebrand rewrites to the product's repository, and
the installation the one on its owner. When the App has none there, the
error says so and names the repository. The site's name is the same file's
`SITE_NAME`, upstream's title without " with Next.js", which the card's
48-character name pattern refuses.

## 6. The unconnected site

With no App ID or key the readers call GitHub for nothing and answer three
sample issues in GitHub's own shapes (`lib/sample.ts`), about the site
itself; `/` and each sample issue's page carry a notice that links the
README's "Connecting a GitHub App" (`app/connect-notice.tsx`), any other
number is the 404 page, and `/api/health` says `"connected":false`. The
template's own explanation stays above them.

## 7. The webhook

Upstream keyed its HMAC with `''` when `GITHUB_WEBHOOK_SECRET` was unset, so
anyone could sign a delivery. The route now answers 503 until the secret is
set. Signed deliveries are upstream's: the raw body's HMAC compared in
constant time, then `revalidatePath('/')` and the issue's page; anything else
is a 400 that drops nothing. A GitHub App has one webhook URL, so an App
regenerates one environment; the README says how to give stage its own.

## 8. Tests

`tests/web` (vitest) runs the app's modules on Node: the seam; the settings
read from a simulated Worker context and from the process; the App's JWT
verified with its public key, the installation chosen by owner, the token
refreshed on 401, against an in-process GitHub; the readers connected and
not; the webhook's signature check and the paths it revalidates;
`/api/health`; the pages rendered with React's server renderer.

The e2e (`testing/e2e.test.sh`) builds the product in the job's own tree,
serves it as born, then builds it again with the App's settings in the job's
environment (none may reach the build) and serves it with them as Worker
secrets. `api.github.com` is answered by `testing/lib/fake-github.mjs`, which
verifies the JWT with the App's public key, reached through the e2e's own
Worker entry (`testing/lib/e2e-worker.mjs`): it wraps the global fetch, then
imports the built Worker and re-exports its Durable Objects, so the product
code is exactly what deploys. It then proves the loop the spike proved, with
a forged, an unsigned, a tampered and a truncated delivery refused.

## 9. Alternatives rejected

- **`jose` in place of `jsonwebtoken`.** WebCrypto imports only PKCS#8 keys,
  so GitHub's PKCS#1 key would need converting; `jsonwebtoken` works as it is.
- **populateCache at deploy.** It would copy the build's sample `/` into the
  bucket and serve it after an App is connected, until the first webhook.
- **A `GITHUB_API_URL` setting for the e2e.** A host option shipped only for
  a test is a seam no product needs; the e2e's own entry reroutes the fetch.
- **Accepting deliveries with no secret.** Upstream's behaviour, but an HMAC
  keyed with `''` authenticates nothing.
- **Keeping `nextjs/on-demand-isr`.** A product listing another
  organisation's issues, through an installation it cannot have.
