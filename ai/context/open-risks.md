# on-demand-isr — open risks

What is not yet proven or not yet decided. The full write-up of every risk,
including the accepted and resolved ones, is
`specs/epics/on-demand-isr/risks-and-open-questions.md`; this page lists only what
is still live, so it should be short.

| ID | Risk | State | What closes it |
|---|---|---|---|
| OI-A | No live bootstrap yet: the repository created and linked, the two tokens minted, a real `terraform apply`, a real `wrangler deploy` with the R2 and Durable Object bindings and the Worker secrets, the probes | OPEN | One bootstrap from a tag against a workspace |
| OI-B | No real GitHub App has been read: the App's RS256 JWT, the installation token and the Issues API are proven against a stand-in that verifies the JWT with the App's public key, and a real App's webhook has not called the site | OPEN | A GitHub App created on a bootstrapped site's repository, connected, and an issue opened |
| OI-C | Next.js (15.5.29) and @opennextjs/cloudflare (1.20.16) are pinned together: the adapter's peer range sets the lowest Next it accepts | WATCH | Move both at once |
| OI-D | The cache is keyed by the build: each deploy starts an empty cache, and nothing deletes the previous builds' objects from the bucket | WATCH | R2 storage is cheap and free to 10 GB; delete `incremental-cache/<old build id>/` when it matters |
| OI-M | The e2e reroutes the built Worker's fetch through a test-only entry; it relies on Next.js capturing the global fetch when its server starts | WATCH | An OpenNext release that changes that order fails the e2e loudly |

Accepted, and worth knowing before you change them: OI-E (one webhook URL per
App: an App regenerates one environment), OI-F (the template's 15-minute
`"use cache"` lifetime kept), OI-G (the first visit after a deploy renders),
OI-H (the template's quirks kept: an unauthenticated first read, pull
requests among the issues, comments by logins containing "bot" left out),
OI-I (an App not installed on the repository's owner is a 500 on uncached
pages, with a clear log), OI-J (the App's private key is a Worker secret),
OI-K (stack-tectonic 0.19.0), OI-L (local runs on Node 26; CI's Node 22 is
the gate).
