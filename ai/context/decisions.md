# on-demand-isr — decisions

The choices that shape this repository, one line each, with where the full
reasoning lives. Superseded decisions stay listed, marked, so the history
reads in order.

| # | Decision | Why | Source |
|---|---|---|---|
| 1 | OpenNext on Workers + Static Assets, the commerce baselines' shape | The template is a Next.js App Router app: server components, route handlers and `"use cache"` run in the Worker | `specs/epics/on-demand-isr/design.md` §2 |
| 2 | The page and data cache in R2, the tag cache (sharded) and the revalidation queue in Durable Objects | `"use cache"` needs a composable cache (OpenNext's static-assets cache refuses it), and `revalidatePath` needs a tag cache every read consults: the commerce baselines' proven shape, no database to provision | design.md §3 |
| 3 | Next.js 15.3.6 → 15.5.29, the template's 15 line kept | @opennextjs/cloudflare 1.20.16 accepts `>=15.5.29 <16`; `experimental.useCache` and `inlineCss` kept as upstream sets them | design.md §4, risk OI-C |
| 4 | No populateCache at deploy: each page is rendered on its first visit | The build has no App settings (`env -u`), so its prerender of `/` is the sample page; the cache is keyed by the build id, so a deploy starts empty and renders with the Worker's settings — connecting an App is a redeploy, nothing more | design.md §4 |
| 5 | The App's three settings are optional Orun secrets the deploy puts on the Worker, read per request (`lib/settings.ts`: the Worker's env, else `process.env`) | The template read them from the server's environment; on Workers that is the Worker's secrets, and none may be in a bundle | design.md §5 |
| 6 | The repository is the product's own (`SOURCE_URL` in `app/site.ts`), its installation found by owner | Upstream hard-coded `nextjs/on-demand-isr` and the `nextjs` installation; the rebrand rewrites `SOURCE_URL` to the product's repository | design.md §5 |
| 7 | No App, no calls: sample issues (`lib/sample.ts`) under a notice (`app/connect-notice.tsx`); `/api/health` says whether the App is connected | A baseline goes live with no key the platform cannot broker; upstream threw on the first read without its settings | design.md §6 |
| 8 | The webhook is shut (503) until `GITHUB_WEBHOOK_SECRET` is set | Upstream keyed its HMAC with `''` when the secret was unset, which anyone can compute; signed deliveries keep upstream's check (`timingSafeEqual`) and its `revalidatePath` calls | design.md §7 |
| 9 | `jsonwebtoken` kept for the App's RS256 JWT | It signs with GitHub's PKCS#1 key on workerd (`nodejs_compat`); the spike verified every JWT with the public key, so no swap to `jose` | design.md §4 |
| 10 | A clear error when the App has no installation on the repository's owner | Upstream failed with a `TypeError` reading `undefined.id` | design.md §5 |
| 11 | The e2e serves the built Worker behind a test-only entry that reroutes `api.github.com` to a stand-in (`testing/lib/`) | The client builds GitHub's URL itself and the product carries no host option; no test seam ships | design.md §8 |
| 12 | One site-name seam (`SITE_NAME`, `app/site.ts`: upstream's title without "with Next.js", which the card's 48-character name pattern refuses) | The rename rewrites one line; upstream wrote its title into the layout | design.md §5 |
| 13 | stack-tectonic 0.19.0, `ci.yml` as the commerce baselines', no `checks.yml`, the domain not asked, the subdomain from the Cloudflare connection | The commerce baselines' settled shape | `intent.yaml`, `blueprint.yaml` |
