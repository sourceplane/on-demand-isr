# 01-product — the product, built in one landing

**Places** every module: the root manifests, CI, tooling and the identity
file; `infra/terraform/cloudflare-r2` (the R2 cache bucket per environment);
`apps/web` (the on-demand ISR site, its OpenNext build, its
wrangler template and fixture, its deploy contract); `tests/web` (vitest).
Then brands them, lands them as ONE pull request, and watches the ONE
convergence that merge triggers.

**Requires** both connections live — GitHub (the App installation on the
OWNER of the repository, the only way the platform sees its pull requests)
and Cloudflare (every deploy credential below is minted from it) — probed,
waited for up to ten minutes each, so the consent can be clicked while it
waits. The site's own GitHub App is not required: the site goes live listing
sample issues, and the owner connects one afterwards (the product's README,
"Connecting a GitHub App").

## What runs

The run's task set-up — the epic, both milestones, both tasks — runs in the
background from the start (`background: true`), so every hook up to `task`
runs beside it; `task` is the first that waits for it.

| hook | what it does |
|---|---|
| `retouch` | the redeploy marker on the components `.baseline/tasks/01-product.TaskContract.yaml` names: `cloudflare-r2`, `web`, `web-tests` |
| `git-init`, `stage`, `rebrand` | the tree becomes a repository, then the product's |
| `orun-workspace` | intent.yaml's `workspace:` becomes the product's (or `ws_SET_ME`, which fails loudly) |
| `work-tree` | intent.yaml's `work:` block — this repository's epics and tasks — is removed |
| `promotion`, `dev-lanes` | prod's promotion gate and dev's push-to-main activation deferred until `02-docs` |
| `restage`, `rebrand-verify` | the sweep: no identity of this baseline left anywhere |
| `repo` | `orun.repo/ensure@v1` creates `<githuborg>/<reponame>` (or finds it) |
| `link` | the repository becomes the workspace's; `orun cloud check` is the gate |
| `secrets` | `orun.integrations/reconcile@v1`, the three keys in one hook, created side by side, each under its own template: `CLOUDFLARE_API_TOKEN` from `workers-deploy` (Workers Scripts and KV write, for the site's deploy — it carries no R2); `CLOUDFLARE_R2_TOKEN` from `r2-data` (R2 Storage write, which the R2 root's Terraform binds as its provider token); `CLOUDFLARE_ACCOUNT_ID`, the connection fact both bind |
| `task` | finds the phase's task and yields its key — waiting, if it must, for the background set-up |
| `land` | one PR bound to the task, its commit checked in the box first (`checks: local`: `orun validate`, then `orun plan` as the PR and as the merge would plan it, under a second); merged without waiting for the PR's CI |
| `converge` (await) | `orun.run/watch@v1` on the merge commit's run, read every 5 s; resumes it up to three times |
| `verify` (await) | `orun.http/probe@v1` on both workers.dev URLs |

## What the convergence does

`orun plan --changed` on the merge plans, with dev's push activation and the
promotion gate deferred:

| lane | waits on | does |
|---|---|---|
| `cloudflare-r2 · stage` / `· prod` | nothing | `terraform apply` of `stg-<reponame>-stage` / `prod-<reponame>-prod` with the `r2-data` token, adopting a bucket of that name if one exists (`adopt.tf`), then lease-publishes `WIRING_CLOUDFLARE_R2` = `{r2_bucket_name}` on that environment |
| `stage · web` / `prod · web` | that environment's R2 apply (`dependsOn: cloudflare-r2`, `mode: enforced` on main) | resolves `WIRING_CLOUDFLARE_R2_<ENV>` as it starts, renders `wrangler.jsonc` with the real bucket name, builds with OpenNext, deploys `<reponame>-web-<env>` (the Durable Objects' migration runs on this first deploy), and smoke-tests it: `/` must answer and `/robots.txt` must name the origin it was asked on, which only the Worker renders |

Stage and prod run side by side. `web-tests` verifies on dev only, on a pull
request. The landing's own pull request runs `plan` alone, and nothing waits
for it — the same plan ran in the box before the push: the baseline's own CI
installed, type-checked, linted, tested and built this exact tree before the
tag was cut. A later pull request's `web-tests` lane installs and checks the
package; it does not run the suite, so the product's developers run
`pnpm test` and `pnpm lint` before they push.

## Verified

The convergence run for the merge commit is green — the site resolved
`WIRING_CLOUDFLARE_R2` from stage and prod, where every later deploy reads
it; `https://<reponame>-web-{stage,prod}.<subdomain>.workers.dev` answer —
listing sample issues until the owner connects a GitHub App.

## Troubleshooting

| symptom | cause → fix |
|---|---|
| parks on the `providers` probe | GitHub (on the repository's owner) or Cloudflare is not connected to the workspace. Connect it (console → Integrations), then re-run the phase — the probe is a wait, not a failure |
| stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| `land`: `the landing's own check failed — orun plan for …` | the placed tree does not plan; the next line is orun's error. Nothing was pushed. Fix it and re-run the phase |
| `secrets` fails `parent_grant_insufficient` on `CLOUDFLARE_R2_TOKEN` | the connection's Account API token lacks Workers R2 Storage Write; add it (the console's Connect recipe lists it under "R2 data access"), re-connect, re-run the phase |
| R2 lane: Authentication error (10000) on the bucket list or create | the R2 root is not using the `r2-data` token — `infra/terraform/cloudflare-r2/component.yaml` must bind `CLOUDFLARE_API_TOKEN` to `CLOUDFLARE_R2_TOKEN`; the deploy token carries no R2 |
| R2 lane: `The bucket you tried to create already exists` (10004) | `adopt.tf` imports a bucket of the same name; if it was removed, restore it. Two products with the same `reponame` in one account share bucket names — use a distinct `reponame` |
| deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts write. Re-issue it with the permission groups the console's Connect recipe lists, re-connect, re-run the phase |
| web lane fails resolving `WIRING_CLOUDFLARE_R2_<ENV>` | that environment's R2 apply failed or never ran — read its lane; the web lane waits on it, so it shows as not run on a fresh failure |
| web lane `build-app`: `wire: missing wiring documents` | the job started without the document — the `dependsOn` edge is gone from `apps/web/component.yaml`, or the secretEnv names the wrong key |
| web lane `verify-app-structure`: `test -f wrangler.jsonc` fails | `apps/web/wrangler.jsonc` is not committed (an old `.gitignore` entry); render it with `pnpm run wire:fixture` and commit it |
| `build-app` fails: `Symlink apps/web/node_modules/next is invalid, it points out of the filesystem root` | the site's `intent.yaml` pins stack-tectonic ≥ 0.20.0 (lane-scoped install). Pin 0.19.0 — `intent.yaml`'s comment says why |
| smoke fails right after the FIRST deploy | workers.dev route propagation; the composition retries the first deploy and the smoke with backoff (stack-tectonic ≥ 0.19.0). A convergence resume clears what is left |
| the watch says green, the probe says 404 | another workflow ran on the push and the watch took its run. Only `ci.yml` may run on a push to main |
| convergence failed AFTER the PR merged; re-running lands nothing | the hooks did not run (`--run-hooks`), or the contract names no component — `node tooling/bootstrap/retouch.mjs --check --affects .baseline/tasks/01-product.TaskContract.yaml` in the site's tree says which |
