# BOOTSTRAP — a new product from this baseline, in one landing

How to go from **nothing** to an **on-demand ISR site live on stage and prod,
its R2 cache buckets applied, documented**, with ONE provider consent — and
how its owner then connects the GitHub App whose webhook regenerates its
pages.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. The console card the platform renders is
**`blueprint.yaml`**; it names the build document and states the inputs, the
brokered secrets and the programme, and `testing/manifest.test.sh` holds it
to what the build document does.

Target wall-clock: **about fourteen minutes** — an estimate summed from the
phases (13 + 1) until a bootstrap measures it; no build of this baseline has
been timed. The shape: the task set-up in the background while ONE landing
is placed, branded and checked in the box (`orun validate` and `orun plan`,
no runner waited for), then one convergence — the R2 bucket applied on stage
and prod, then the site built with its name and deployed, stage and
prod side by side — then a short docs landing that restores the promotion
gate.

## 0. What you need

- GitHub org access (repository creation) and a machine with `git`, `node`
  (≥ 22), `pnpm` (10.12.1), `python3` with PyYAML, `curl`, and the `orun`
  CLI **≥ v2.88.0** — the floor for RUNNING the bootstrap (the phase overlay,
  landings that commit per phase, `githubOwner` on the doctor probe, a probe
  deferred for a project not yet created, `from: workspace`, the deploy
  credentials minted in one `secrets` reconcile, the task set-up run in the
  background (`background: true`), and landings checked in the box before
  they merge (`checks: local`)). The product's own `ci.yml` pins its lanes
  separately (v2.78.4).
- A Cloudflare account with **R2 enabled** (R2 must be activated once in the
  dashboard, even on the free plan; Durable Objects with SQLite storage are
  on the free plan too) and its **Account API token** with Workers Scripts
  Write, Workers KV Storage Write and **Workers R2 Storage Write** (the
  console's Connect recipe lists the exact permission groups). It is the ONLY
  provider credential this baseline needs, minted into two scopes: the
  brokered `workers-deploy` token deploys the Worker, and the `r2-data` token
  (`CLOUDFLARE_R2_TOKEN`) applies the bucket — `workers-deploy` carries no
  R2.
- **No GitHub App.** The site goes live listing sample issues under a
  notice that says how to connect one; the site's own App is not a
  connection the platform brokers, so the owner creates and connects it
  after the build (§4).
- **Workers Free is enough**: the Worker is about 1.3 MiB gzipped, inside
  Free's 3 MiB.
- An Orun Cloud workspace for the product — `orunWorkspace`, or the
  workspace the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs (secret writes below admin are
  masked as `not_found`).
- **The repository allow-listed in the workspace** (console → Settings → Git
  repos), unless the credential can write links. `01-product`'s `link` step
  stops and names the fix if it is not.

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/on-demand-isr
cd on-demand-isr

orun new --blueprint repo-blueprint.yaml \
  --out ~/sites/acme-issues --run-hooks --resume \
  --set reponame=acme-issues --set productname="Acme Issues" \
  --set githuborg=acme-inc \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the workers.dev subdomain of the Cloudflare account you deploy
into (Workers & Pages → your subdomain). A build started from the console, or
with `orun baseline new --from bst_…`, never asks for it: the platform reads
it from the workspace's Cloudflare connection, the same one the deploy tokens
mint from. Only a hand-run build like this one passes it.

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repository, no
landing, no convergence watch, no probe. That is deliberate — it is what
makes the offline bootstrap in `testing/` possible with no workspace and no
provider.

`--resume` is safe to re-run from anywhere, a fresh container with a fresh
`--out` included: **phase state is derived from the tree, never stored.** A
phase whose files are present but branded derives as `drifted`, and
`--resume` leaves it placed rather than reverting the product's identity.

## 1b. Or phase by phase

| phase | what it lands | verified by |
|---|---|---|
| `01-product` | the repository, created and linked; the WHOLE product in one PR — intent, CI, tooling, identity, the R2 root, the site and its tests; the brokered Cloudflare secrets (deploy, R2, account id) | its commit validated and planned in the box (as the PR and as the merge), then merged; the convergence green (R2 applied, then the site — which resolves `WIRING_CLOUDFLARE_R2` — built, deployed, smoke-tested); both workers.dev URLs answering |
| `02-docs` | `ai/context/deployment.md` from probed facts; prod's promotion gate and dev's push lanes restored | the render's own probes, recorded; the commit checked in the box and merged |

```bash
orun new --blueprint repo-blueprint.yaml --out ~/sites/acme-issues --run-hooks \
  --phase 01-product --values ~/acme-issues.values.yaml
# … then 02-docs
```

`02-docs` reads the identity back from `.rebrand/values.json` in the placed
tree, but the blueprint's **required** inputs — `reponame`, `productname`,
`githuborg` — are validated before anything runs, so pass them every time (a
`--values` file is easier). The domain is not one of them: the site goes live
on workers.dev, and `productdomain` defaults to empty, which brands the
reserved placeholder `<reponame>.example.com` into `BASE_DOMAIN` for an owner
to replace when they attach a domain (README, "Custom domain"). Pass
`--set productdomain=` only for a site that already has its domain.
The full guide, one page per phase: [docs/phases/README.md](docs/phases/README.md).

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. It parses the document, validates each hook against the action registry and compiles every template; it needs no credential and no network |
| `--phase <name>` | places exactly that phase; its `requires.phases` still gates |
| `--until <name>` | places every phase through that one and stops |

What lands in the product is PRODUCT-ONLY: the app, its R2 root, its tests,
its CI, its tooling, its README and its two context pages. None of this
repository's machinery (`.baseline/`, the blueprints, `tooling/rebrand`,
`tooling/bootstrap`, `hooks/`, `testing/`, `docs/phases/`, `specs/`,
`tasks/`, this file) ships, and no file that ships names one of them. That
promise is a test: `testing/leak.test.sh` derives what every phase would
place and gates the set and its sources, and `testing/placement.test.sh`
gates the same rules over a placed, branded tree.

## 2. Why one landing is safe: the plan carries the order

The bucket must exist before the Worker that binds it: the Worker's
`wrangler.jsonc` carries the bucket's name, rendered in its build from the
wiring document the R2 root publishes after its apply, and a deploy whose
R2 binding names a bucket that does not exist is refused. That order used to
need landings of its own. It does not, because the product's plan holds it:

- `apps/web/component.yaml` declares `dependsOn: cloudflare-r2` with
  `mode: enforced`, and `modeRules` making it advisory on
  `github-pull-request`. On the merge the Worker's deploy waits for its
  environment's apply; on a pull request nothing deploys, so nothing waits.
- A job resolves its secrets when it STARTS, so `WIRING_CLOUDFLARE_R2_<ENV>`
  is there when the deploy begins.
- The deploy resolves the document from the place every later run looks
  (its `component.yaml` secret refs), so a green convergence already says it
  is there: a missing one fails its lane. There is no separate check.

`testing/phases.test.sh` fails if a component that reads a wiring document
does not wait for its publisher this way; `testing/placement.test.sh` plans
the product's own merge and asserts the R2 lanes run first.

### Two Cloudflare tokens, on purpose

`workers-deploy` grants Workers Scripts and KV write — and no R2. The R2
root's Terraform has to list the account's buckets (`adopt.tf`) and create
one, so it authenticates with its own key, `CLOUDFLARE_R2_TOKEN`, minted from
the `r2-data` template — its own entry in the one
`orun.integrations/reconcile@v1` hook (`secrets`), beside the deploy token's
`workers-deploy` — and bound in
`infra/terraform/cloudflare-r2/component.yaml` as the provider's
`CLOUDFLARE_API_TOKEN` (the way a D1 root binds a `d1-edit` token). The card
(`blueprint.yaml` `spec.secrets`) mirrors the hook, and
`testing/manifest.test.sh` holds the two together.

## 3. Headless / container mode

The blueprint's source is this repository (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two
tokens:

```bash
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/on-demand-isr
cd on-demand-isr
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme-issues --run-hooks --resume --progress json \
  --values /work/acme-issues.values.yaml
```

| requirement | detail |
|---|---|
| `GITHUB_TOKEN` | fine-grained PAT: **read** on this repository; on the PRODUCT's repository **contents write**, **pull-requests write**, **actions read+write** (`orun.run/watch@v1` resumes runs with `gh run rerun`), **checks read**; **repository create** on the owner if `01-product` creates it (or pre-create it — supported) |
| classic token caveat | a classic PAT or gh OAuth token also needs the `workflow` scope to push `.github/workflows/` |
| pinning | the clone's `--branch <tag>` pins everything: the blueprint, its modules and its hooks' scripts all come from that one commit |

## 4. After the product is live

- **Connect a GitHub App** (the owner's step; the platform does not broker
  it): an App with read-only Issues access, subscribed to Issues and Issue
  comment events, its webhook at `<site>/api/webhook` with a secret, and
  installed on the product's repository; then the Orun secrets
  `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` (its private key) and
  `GITHUB_WEBHOOK_SECRET` per environment, and a redeploy — each deploy puts
  the three on the Worker (the build never sees them). The product's README,
  "Connecting a GitHub App", has every step.
- **Change the site**: anything under `apps/web`; its name and the
  repository it lists are `apps/web/app/site.ts`. Every merge to `main`
  redeploys.
- **Add a binding** (D1, KV, another bucket): a Terraform root that
  lease-publishes `WIRING_<ROOT>`, a token in `wrangler.template.jsonc`, its
  fixture entry, and in `apps/web/component.yaml` the root in the build's
  `--components`, the `WIRING_<ROOT>_<ENV>` secretEnv and an enforced
  `dependsOn` on it. `ai/context/operations.md` in the product says the same.
- **Custom domain**: attach it to the Worker in Cloudflare (the product's
  README, "Custom domain"). There is no domain phase: attaching a domain
  needs zone permissions the brokered `workers-deploy` token does not carry.
  Then point the GitHub App's homepage and webhook at the domain.
- **Refresh the record**: re-run `--phase 02-docs`; it is idempotent.

## 5. Testing this baseline

`.github/workflows/baseline.yml` runs three tiers on every pull request, and
each runs locally the same way:

```bash
for t in manifest phases coverage rebrand retouch bootstrap-defer wire render; do bash testing/$t.test.sh; done
bash testing/leak.test.sh        # needs orun
bash testing/placement.test.sh   # needs orun >= ci.yml's pin, node, pnpm: the offline bootstrap and the product's own plan
bash testing/e2e.test.sh         # + network for pnpm: the product built in the job tree, dry-deployed, served, regenerated by a signed webhook
```

The offline bootstrap (`testing/lib/bootstrap.sh`) places both phases in
order and finishes each with the blueprint's OWN `run:` hooks — read out of
`repo-blueprint.yaml`, not transcribed — so the retouch marker, the rebrand,
the re-tenant, the deferrals and their restore, and the deployment record
all run exactly as a real bootstrap runs them. Only the platform's typed
actions (task, repo, link, reconcile, land, watch, secrets,
probe) are stood in for, a landing becoming a commit. What no offline test
can do is the platform's half: the bucket applied for real (the R2 root is
held to `terraform validate`), the tokens minted, the deploy, the probes —
and a real GitHub App: the e2e connects a stand-in GitHub
(`testing/lib/fake-github.mjs`) that checks the App's RS256 JWT with its
public key and answers the Issues API for one repository, through a
test-only entry (`testing/lib/e2e-worker.mjs`) that reroutes the built
Worker's fetch — not a real installation.

## 6. Cutting a baseline tag (maintainers)

Every product built from this repository resolves a `baseline-vN` tag, so
the tag is cut by a workflow rather than by hand:

```bash
gh workflow run tag.yml -f version=baseline-v1          # from main
gh workflow run tag.yml -f version=baseline-v1 -f ref=<sha>
```

It refuses a version that is not `baseline-v<N>` and a tag that already
exists: a baseline tag is never moved. Then move the registry row in
orun-cloud's `infra/baselines-registry/baselines.yaml` by pull request —
after the tag exists, because the registry's sync fetches `blueprint.yaml`
at the tag and refuses the whole catalogue if it 404s.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `01-product` parks: `waiting for github for <org>` | the workspace's GitHub connection is to another account. Connect the App installation on `<org>` (console → Integrations → GitHub), then `--resume` |
| `01-product` waits on the `providers` probe, then stops | Cloudflare is not connected. Connect it (console → Integrations), then re-run the phase — the probe is a wait, not a failure |
| `01-product` stops at `link` | the repository is not linked to the workspace and the credential cannot link it. Allow-list it (console → Settings → Git repos) and re-run the phase |
| Secret WRITE fails `not_found` while listings work | the API key's role is below admin; re-mint it with the admin role |
| `secrets` fails `parent_grant_insufficient` on `CLOUDFLARE_R2_TOKEN` | the connection's token lacks Workers R2 Storage Write; add it, re-connect, re-run `01-product` |
| R2 lane: Authentication error (10000) | the R2 root is not authenticating with `CLOUDFLARE_R2_TOKEN` (its component.yaml), or the account has not activated R2 |
| deploy lane: Authentication error (10000) | the connection's token lacks Workers Scripts write; re-issue it, re-connect, re-run `01-product` |
| R2 lane: bucket already exists (10004) | `adopt.tf` imports a bucket of the same name; restore it if removed. Two products with one `reponame` in one account share bucket names — pick another `reponame` |
| web lane fails resolving `WIRING_CLOUDFLARE_R2_<ENV>` | that environment's R2 apply failed — read its lane; the web lane waits on it |
| web lane: `WIRING_CLOUDFLARE_R2` not found | that environment's R2 apply published nothing: the R2 component lost its `secretOutputs`, or its lane was not in the plan. Re-run the phase; its retouch marker re-plans the R2 root |
| `land` stops: `the landing's own check failed — orun plan for …` | the product's tree does not plan — the line after it is orun's own error (an unknown component type, a composition that does not resolve). Nothing was pushed. Fix the tree (or the baseline) and re-run the phase |
| `land` waits on CI after all | the product's repository requires a status check on `main` (branch protection or a ruleset), so GitHub refused the early merge; the landing waits for the check as a `checks: ci` landing would, then merges |
| Convergence failed AFTER the PR merged; re-running lands nothing | expected on its own — the files are on main. Re-run the phase (`--phase 01-product`, `--redo 01-product`, or the console's Retry): its `retouch` hook gives the landing a diff and the R2 root and the site re-plan |
| The live site lists sample issues under "no GitHub App is connected yet" | no App is connected — expected after a bootstrap. The product's README, "Connecting a GitHub App" |
| An App is connected, but the site still lists sample issues | `GITHUB_APP_ID` and `GITHUB_APP_PK_PEM` are read per request from the Worker, and a deploy puts them there: redeploy after setting them (the product's README, "Deploy by hand"). `/api/health` says `"connected":true` once they are |
| An App is connected, but `/` answers 500 | the App is not installed on the repository's owner (the log says "no installation for <owner>"), or the private key is not the App's; install it, or generate a new key and set `GITHUB_APP_PK_PEM` again |
| The App's deliveries answer 503 | `GITHUB_WEBHOOK_SECRET` is not set for that environment, or was set after its last deploy; set it and redeploy |
| The App's deliveries answer 400 "Invalid signature." | the App's webhook secret is not the environment's `GITHUB_WEBHOOK_SECRET`; set one to the other and redeploy |
| A new issue does not show | the App is not subscribed to Issues events, or its webhook points at another environment (an App has one webhook URL); the page still refreshes within 15 minutes |
| A bootstrap stopped before `02-docs`; prod no longer waits on stage | the gate is deferred, not dropped: run `02-docs`, or `node tooling/bootstrap/promotion.mjs --restore --file <product>/intent.yaml` |
| `✕ input "productname" is required` | all three required inputs (`reponame`, `productname`, `githuborg`) must be set on every invocation, single-phase ones included |
| `unknown flag: --phase`, `has no parameter "checks"`, `has no parameter "secrets"` or another parse error in the blueprint | the CLI is below the v2.88.0 floor |
| web lane `verify-app-structure` fails on `wrangler.jsonc` | the config is not committed. It is the fixture render of `wrangler.template.jsonc`: `pnpm run wire:fixture` and commit it |
| web lane `build-app`: `Symlink apps/web/node_modules/next is invalid, it points out of the filesystem root` | the product's intent pins stack-tectonic ≥ 0.20.0, whose lane-scoped install links each job's node_modules out of its tree, which Next 16's Turbopack refuses. Pin 0.19.0 (`intent.yaml` says why) |
| the convergence reported green, then `verify` got 404 | a second workflow ran on the push to main and the watch took its run. Only `ci.yml` may run on a push to main |
