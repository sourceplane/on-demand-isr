# on-demand-isr — risks and open questions

| ID | Risk | State | Notes |
|---|---|---|---|
| OI-A | Not proven live: the repository and link, the minted tokens, a real `terraform apply` and `wrangler deploy`, the Worker secrets put on a real Worker, the probes | OPEN | Baseline CI proves everything else offline; one bootstrap closes it |
| OI-B | No real GitHub App has been read: the JWT, the installation token and the Issues API are proven against a stand-in that verifies the JWT with the App's public key, and no real webhook has called the site | OPEN | A GitHub App created on a bootstrapped site's repository, an issue opened |
| OI-C | Next.js and @opennextjs/cloudflare pinned together (15.5.29, 1.20.16) | WATCH | The adapter's peer range sets the lowest Next it accepts on each line; move both at once |
| OI-D | The cache is keyed by the build: a deploy starts an empty cache, and nothing deletes previous builds' objects | WATCH | R2 storage is free to 10 GB; old builds' prefixes can be deleted by hand |
| OI-E | A GitHub App has one webhook URL: an App regenerates one environment | ACCEPTED | The README says so: one App for prod, a second for stage if it should regenerate too; both re-read GitHub every 15 minutes regardless |
| OI-F | The template's `"use cache"` default lifetime kept: entries are refreshed in the background after 15 minutes even without a webhook | ACCEPTED | Upstream's behaviour on Vercel (the route table's Revalidate 15m); an installation token allows 5,000 requests an hour |
| OI-G | The first visit after a deploy renders (no populateCache) | ACCEPTED | The build has no App settings, so its prerender is the sample page; rendering on the first visit is what makes a redeploy enough to connect an App |
| OI-H | The template's quirks kept: the first reads carry no token and are retried after a 401 (two token mints per isolate's first page), GitHub's issues endpoint lists pull requests too, comments by any login containing "bot" are left out | ACCEPTED | Upstream's own code, unchanged |
| OI-I | An App not installed on the repository's owner: every uncached page answers 500, with the log naming the owner | ACCEPTED | An owner's misconfiguration; upstream failed the same way with a `TypeError` |
| OI-J | The App's private key is a Worker secret | ACCEPTED | Read-only Issues access on the repositories the App is installed on; the README's rotation steps |
| OI-K | stack-tectonic 0.19.0 kept | ACCEPTED | The commerce baselines' pin |
| OI-L | Local tiers ran on Node 26 (Homebrew's node@22 was broken on the build machine); Baseline CI runs Node 22 | ACCEPTED | The e2e's Node 22 check only warned in a temporary local copy, deleted |
| OI-M | The e2e reroutes the built Worker's fetch through its own entry; it relies on Next.js capturing the global fetch when its server starts | WATCH | microcms-blog's pattern; a change in that order fails the e2e, not a product |
