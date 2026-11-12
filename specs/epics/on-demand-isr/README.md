# on-demand-isr — On-Demand ISR on Cloudflare Workers

**Vercel's On-Demand ISR template lists a repository's GitHub issues as
statically generated pages, reads them as a GitHub App, and regenerates them
the moment the App's webhook says an issue changed, through
`revalidatePath`. The port keeps the template — its pages, its `"use cache"`
reads, its webhook — and moves its cache onto Cloudflare: one Worker, the
pages and reads in R2, the record of what was revalidated in Durable
Objects. The App's settings become Worker secrets read per request, the
repository becomes the site's own, and the webhook stops accepting an HMAC
keyed with an empty secret. A spike proved the whole loop — cached, signed,
regenerated — on workerd before anything was built on it. A product built
from it deploys before its owner connects an App, listing sample issues, and
lists its own repository's issues once they set the App's ID, key and
webhook secret.**

| | |
|---|---|
| Status | ✅ Shipped (`baseline-v1`) — proven offline in Baseline CI; not yet live (risk OI-A) |
| Upstream | [vercel/on-demand-isr](https://github.com/vercel/on-demand-isr) (MIT, `LICENSE.md`), at `2e96485` (2026-10-14) |
| Reference | [sfcc-commerce](https://github.com/sourceplane/sfcc-commerce) and [commerce](https://github.com/sourceplane/commerce) — the same OpenNext, R2 and Durable Object shape, Worker secrets pushed after the build, a webhook that revalidates; [microcms-blog](https://github.com/sourceplane/microcms-blog) — a SaaS client's host rerouted by the e2e's own Worker entry |
| Key | `OI` |

## Read in this order

1. [design.md](design.md) — the template, how each Vercel piece maps to
   Cloudflare, the cache and the spike that proved it, the App's settings and
   the repository, the unconnected site, the webhook, the tests, and the
   alternatives rejected.
2. [implementation-plan.md](implementation-plan.md) — the milestones and
   what each one lands.
3. [risks-and-open-questions.md](risks-and-open-questions.md) — what is not
   proven, and what was accepted.
4. [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md) — what shipped, and
   every departure from the template.
