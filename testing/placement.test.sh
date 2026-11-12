#!/usr/bin/env bash
# TIER 1 — the tree is placed, branded, and made to answer.
#
# A real bootstrap is `orun new --run-hooks --resume` against a workspace: it
# places each phase, runs that phase's hooks, lands a pull request and watches
# the convergence. Everything in that sentence except the platform can run
# here, offline, and this file runs it:
#
#   1. the whole blueprint placed in one go — orun runs `validate` and
#      `plan --dry-run` inside the produced tree and says so; asserted, because
#      a future orun that stopped running them would weaken this tier in silence;
#   2. THE OFFLINE BOOTSTRAP (testing/lib/bootstrap.sh) — both phases placed in
#      order onto what the previous one landed, finished by the blueprint's OWN
#      `run:` hooks (retouch, rebrand, re-tenant, work-tree strip, the
#      deferrals and their restore, the deployment record), each
#      landing a commit;
#   3. the product it ends with: branded with no residue — the site's name
#      and source link, the Worker and its self-reference binding, the R2
#      bucket names and every secret ref its own — carrying nothing of the
#      factory and naming none of it, re-tenanted, its gates restored, its
#      record rendered;
#   4. what the product's own CI does with the 01-product merge: `orun plan`
#      for a push to main over exactly that commit — INFRA BEFORE APP: the R2
#      bucket applied on stage and prod, each Worker deploy waiting on its own
#      environment's apply and nothing else, stage and prod side by side,
#      nothing on dev; the R2 root authenticating with the r2-data token and
#      the deploy with the workers-deploy one; the build rendering the
#      environment's wiring, the Worker, smoke and secret refs the product's
#      own. Then the same edge on a pull request, where it is advisory and
#      nothing waits; and the 02-docs merge, which plans nothing at all;
#   5. a `--resume` over the finished site places nothing and un-brands nothing.
#
# testing/e2e.test.sh goes on from here: it installs, builds and serves the
# product and runs its smoke against it.
#
# Needs: orun, node, pnpm, python3 (+PyYAML), git. No credential. The
# deployment-record probes reach the network if they can, and pass without it.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
# shellcheck source=lib/bootstrap.sh
source "$here/lib/bootstrap.sh"

for bin in orun node pnpm python3 git; do
  command -v "$bin" >/dev/null || { echo "placement.test.sh needs $bin on PATH" >&2; exit 1; }
done
# Step 4 is the PRODUCT's own plan, so it must be planned by the orun the
# product's CI runs (ci.yml's pin) or newer: an older orun (v2.58.11, the
# bootstrap's floor before v2.88.0) does not apply a dependsOn edge's
# `modeRules`, and would plan a pull request with the site waiting on
# the R2 plan.
pin="$(sed -n 's/^ *version: *v\([0-9.]*\) *$/\1/p' "$root/.github/workflows/ci.yml" | head -1)"
have="$(orun --version | sed -n 's/.*version \([0-9.]*\).*/\1/p')"
python3 -c "import sys; v=lambda s: tuple(map(int, s.split('.'))); sys.exit(0 if v(sys.argv[1]) >= v(sys.argv[2]) else 1)" "$have" "$pin" \
  || { echo "placement.test.sh plans as the product's CI does: run it with orun >= v$pin (ci.yml's pin), not v$have" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fails=0
fail() { echo "  ✕ $*" >&2; fails=$((fails + 1)); }
values="$here/fixtures/acme.json"
repo="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['reponame'])" "$values")"

sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$values" <<'PY'
import json, sys
for k, v in json.load(open(sys.argv[1])).items():
    if not k.startswith("_"):
        print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)

# ── 1. the whole blueprint, one placement ──────────────────────────────────
echo "── placing the whole blueprint at once (offline, no credential)"
whole="$scratch/whole"
mkdir -p "$whole"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$whole/$d/.gitkeep"; done
if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$whole" "${sets[@]}" > "$scratch/whole.log" 2>&1; then
  echo "FAIL: the placement did not run" >&2; tail -20 "$scratch/whole.log" >&2; exit 1
fi
# The line's wording moved between orun releases (v2.58: `repo gate: validate +
# plan --dry-run passed`; v2.79: `Verified  intent valid · N components …`).
grep -Eq "repo gate: validate \+ plan --dry-run passed|Verified +intent valid" "$scratch/whole.log" \
  || fail "the placement did not report the repo-scale gate (orun validate + plan --dry-run inside the tree)"
n="$(find "$whole" -type f -not -path '*/.orun/*' | wc -l | tr -d ' ')"
[ "$n" -ge 50 ] || fail "only $n files placed — that is not a product"
[ "$fails" -eq 0 ] && echo "   $n files placed; the repo-scale gate ran"

# ── 2. the offline bootstrap ───────────────────────────────────────────────
echo "── the offline bootstrap: both phases, their own hooks, a landing each"
tree="$scratch/$repo"     # named as the repository is: orun names the project after it
bootstrap_offline "$root" "$tree" "$values" "$scratch/logs" > "$scratch/bootstrap.log" 2>&1 || {
  echo "FAIL: the offline bootstrap stopped" >&2; tail -40 "$scratch/bootstrap.log" >&2; exit 1; }
grep -E '^── ' "$scratch/bootstrap.log" | sed 's/^/  /'
commits="$(git -C "$tree" rev-list --count HEAD)"
[ "$commits" = 3 ] || fail "the bootstrap made $commits commits, not orun's initial one and one per phase (3)"
[ -z "$(git -C "$tree" ls-tree -r --name-only HEAD~2)" ] || fail "the first commit is not orun's empty Initial commit"

# ── 3. the product it ends with ────────────────────────────────────────────
echo "── the product it produced"
(cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" --verify --values .rebrand/values.json) > "$scratch/verify.log" 2>&1 \
  || { fail "rebrand --verify found the baseline's identity in the product:"; sed 's/^/      /' "$scratch/verify.log" >&2; }

python3 - "$tree" "$values" "$root" <<'PY' || fails=$((fails + 1))
import json, pathlib, re, subprocess, sys
import yaml
tree, values, root = pathlib.Path(sys.argv[1]), json.load(open(sys.argv[2])), pathlib.Path(sys.argv[3])
problems = []
def bad(m): problems.append(m)
repo, org, name, sub, ws = (values[k] for k in ("reponame", "githuborg", "productname", "subdomain", "orunWorkspace"))

tracked = subprocess.run(["git", "ls-files"], cwd=tree, capture_output=True, text=True, check=True).stdout.split()

# Nothing of the factory, nothing local, exactly the two context pages…
NEVER = (".baseline/", "specs/", "tasks/", "testing/", "hooks/", "docs/phases/",
         "tooling/rebrand/", "tooling/bootstrap/", ".github/workflows/baseline.yml",
         ".github/workflows/tag.yml", "BOOTSTRAP.md", "repo-blueprint.yaml", "blueprint.yaml")
for p in tracked:
    if any(p == n or p.startswith(n) for n in NEVER):
        bad(f"{p} is in the product — it is the factory")
    if re.search(r"(^|/)(\.env(\.local)?|\.dev\.vars|node_modules|\.orun|\.next|\.open-next|\.terraform)(/|$)|\.tfstate$", p):
        bad(f"{p} is in the product — a local or built file")
ai = {p for p in tracked if p.startswith("ai/")}
if ai != {"ai/context/deployment.md", "ai/context/operations.md"}:
    bad(f"ai/ in the product is {sorted(ai)}")
# …and no file it carries NAMES the factory: those paths do not exist here.
FACTORY = re.compile(r"repo-blueprint|BOOTSTRAP\.md|(?<![\w-])(testing|specs|tasks|docs/phases|"
                     r"tooling/rebrand|tooling/bootstrap)/|(?<![\w/])\.baseline/")
for p in tracked:
    try:
        text = (tree / p).read_text()
    except UnicodeDecodeError:
        continue
    for n, line in enumerate(text.splitlines(), 1):
        if FACTORY.search(line):
            bad(f"{p}:{n} names a factory path: {line.strip()[:80]}")

# The identity, where the product carries it: the site's name at its one
# seam, and nowhere else in the site's code — the baseline's
# "On-Demand Incremental Static Regeneration" is gone from every file that spelled it — and the
# product's own repository as the one whose issues the site lists.
site = (tree / "apps/web/app/site.ts").read_text()
if f"SITE_NAME = {json.dumps(name)}" not in site:
    bad(f"apps/web/app/site.ts does not name the site {name!r}")
if f'SOURCE_URL = "https://github.com/{org}/{repo}"' not in site:
    bad(f"apps/web/app/site.ts does not link the product's repository github.com/{owner}/{repo}")
for p in tracked:
    if not p.startswith(("apps/web/app/", "apps/web/components/", "apps/web/lib/")):
        continue
    try:
        text = (tree / p).read_text()
    except UnicodeDecodeError:
        continue
    if "On-Demand Incremental Static Regeneration" in text:
        bad(f"{p} still names the site \"On-Demand Incremental Static Regeneration\"")
web = yaml.safe_load((tree / "apps/web/component.yaml").read_text())["spec"]
if web["parameters"]["workerName"] != f"{repo}-web":
    bad(f"workerName is {web['parameters']['workerName']}, not {repo}-web")
if web["parameters"]["workersDevSubdomain"] != sub:
    bad(f"workersDevSubdomain is {web['parameters']['workersDevSubdomain']}, not {sub}")
# The Worker's name, and the self-reference binding the revalidation queue
# calls it back through, which must name exactly the Worker it runs in.
for cfg, worker in (("wrangler.template.jsonc", f"{repo}-web-__ENV__"), ("wrangler.jsonc", f"{repo}-web-stage")):
    text = (tree / "apps/web" / cfg).read_text()
    if f'"name": "{worker}"' not in text:
        bad(f"apps/web/{cfg} does not name the Worker {worker}")
    if f'"service": "{worker}"' not in text:
        bad(f"apps/web/{cfg}'s WORKER_SELF_REFERENCE does not name {worker}")
if json.loads((tree / "package.json").read_text())["name"] != repo:
    bad("package.json is not named for the product")

# The R2 bucket: its name is built on the product's repo slug, so two
# products in one account never collide (bucket names are unique per account).
r2 = yaml.safe_load((tree / "infra/terraform/cloudflare-r2/component.yaml").read_text())["spec"]
if f'default = "{repo}"' not in (tree / "infra/terraform/cloudflare-r2/terraform/main.tf").read_text():
    bad("the R2 root's terraform `repo` default is not the product's slug")
fixture = json.loads((tree / "apps/web/wiring.fixture.json").read_text())
for env, prefix in (("dev", "dev-"), ("stage", "stg-"), ("prod", "prod-")):
    want = f"{prefix}{repo}-{env}"
    if (fixture.get(f"cloudflare-r2/{env}") or {}).get("r2_bucket_name") != want:
        bad(f"the fixture's {env} bucket name is not {want}")
# The GitHub App is the owner's to connect: its ID, its private key and its
# webhook secret, optional, the product's own; all three are kept out of the
# build and handed to the product's own Worker as secrets.
APP = ("GITHUB_APP_ID", "GITHUB_APP_PK_PEM", "GITHUB_WEBHOOK_SECRET")
opt = web.get("optionalSecretEnv") or {}
for key in APP:
    if opt.get(key) != f"secret://{ws}/{repo}/{{{{ .environment }}}}/{key}":
        bad(f"apps/web optionalSecretEnv {key} is {opt.get(key)!r}, not the product's {key}")
if set(opt) != set(APP):
    bad(f"apps/web optionalSecretEnv names {sorted(opt)}, not exactly the GitHub App's three settings")
build = web["parameters"]["buildCommand"]
if "env -u GITHUB_APP_ID -u GITHUB_APP_PK_PEM -u GITHUB_WEBHOOK_SECRET" not in build:
    bad("the build does not keep the GitHub App's settings out of the bundle (env -u)")
if f'--secret GITHUB_APP_ID --secret GITHUB_APP_PK_PEM --secret GITHUB_WEBHOOK_SECRET --worker "{repo}-web-${{ORUN_ENVIRONMENT}}"' not in build:
    bad(f"the build does not hand the GitHub App's settings to the product's own Worker {repo}-web-<env>")
if "E2E_GITHUB_ORIGIN" in build or "api.github.com" in build:
    bad("the build names the e2e's stand-in GitHub")
# Every secret ref names the product's workspace and project.
for label, refs in (("apps/web", web.get("secretEnv") or {}), ("cloudflare-r2", r2.get("secretEnv") or {})):
    for k, ref in refs.items():
        if not ref.startswith(f"secret://{ws}/{repo}/"):
            bad(f"{label} secretEnv {k} is {ref} — not the product's workspace and project")
# …and the R2 root authenticates with the r2-data key, not the deploy token.
if not (r2.get("secretEnv") or {}).get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_R2_TOKEN"):
    bad("the R2 root's CLOUDFLARE_API_TOKEN is not the r2-data key CLOUDFLARE_R2_TOKEN")

# The intent: re-tenanted, no work tree, both gates back, the R2 parameters its own.
intent_text = (tree / "intent.yaml").read_text()
intent = yaml.safe_load(intent_text)
if intent["metadata"]["name"] != repo:
    bad(f"intent metadata.name is {intent['metadata']['name']}")
if intent["execution"]["state"]["workspace"] != ws:
    bad(f"intent workspace is {intent['execution']['state']['workspace']}, not the product's")
if "work" in intent:
    bad("intent.yaml still declares the baseline's work tree")
if "promotion" not in intent["environments"]["prod"] or "@promotion-deferred" in intent_text:
    bad("prod's promotion gate was not restored by 02-docs")
if "github-push-main" not in intent["environments"]["dev"]["activation"]["triggerRefs"] or "@dev-lanes-deferred" in intent_text:
    bad("dev's push activation was not restored by 02-docs")
for env in ("stage", "prod"):
    want = f"https://{repo}-web-{env}.{sub}.workers.dev"
    if intent["environments"][env].get("url") != want:
        bad(f"environments.{env}.url is {intent['environments'][env].get('url')}, not {want}")
    tf = ((intent["environments"][env].get("parameterDefaults") or {}).get("terraform") or {})
    if tf.get("repo") != repo:
        bad(f"environments.{env} terraform repo is {tf.get('repo')}, not {repo}")
for page in (intent.get("repo") or {}).get("docs", {}).get("pages", []):
    if not (tree / page["path"]).exists():
        bad(f"intent repo.docs names {page['path']}, which the product does not have")

# The landings, as the phases made them: one marker per component the
# product's contract names, and the record 02-docs rendered.
for rel in ("infra/terraform/cloudflare-r2/component.yaml", "apps/web/component.yaml", "tests/web/component.yaml"):
    if not re.search(r"^# orun: redeploy 01-product \S+$", (tree / rel).read_text(), re.M):
        bad(f"{rel} carries no 01-product redeploy marker")
dep = (tree / "ai/context/deployment.md").read_text()
if "GENERATED by the `02-docs` phase" not in dep or f"https://{repo}-web-prod.{sub}.workers.dev" not in dep:
    bad("ai/context/deployment.md was not rendered for the product")
readme = (tree / "README.md").read_text()
if not readme.startswith(f"# {repo}\n") or "This site is **live**" not in readme:
    bad("README.md is not the product's, or its live-deployment section was not rendered")

# Provenance prose, over the BRANDED files.
PROV = re.compile(r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit|tag)\b|repo-blueprint|BOOTSTRAP\.md", re.I)
for rel in ("README.md", "ai/context/operations.md", "ai/context/deployment.md"):
    for n, line in enumerate((tree / rel).read_text().splitlines(), 1):
        if PROV.search(line):
            bad(f"{rel}:{n} speaks of the factory: {line.strip()[:70]}")

if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {len(tracked)} tracked files; branded (site name, repository, Worker, bucket names, secret refs), "
      f"no factory path named, re-tenanted, gates restored, record rendered")
PY

# ── 4. the product's own CI, over the 01-product merge ─────────────────────
echo "── orun plan in the product, for the push that merged 01-product"
s01="$(git -C "$tree" rev-parse HEAD~1)"; s02="$(git -C "$tree" rev-parse HEAD)"
git -C "$tree" checkout -q "$s01"
(cd "$tree" && orun validate --intent intent.yaml) > "$scratch/validate.log" 2>&1 \
  || { fail "orun validate refused the product's intent at 01-product"; tail -10 "$scratch/validate.log" >&2; }
# The first push to main: every file is new, so the changed set is everything
# and the plan is the full one.
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --output "$scratch/plan.json") \
  > "$scratch/plan.log" 2>&1 || { fail "orun plan failed in the product at 01-product"; tail -15 "$scratch/plan.log" >&2; }
git -C "$tree" checkout -q main
python3 - "$scratch/plan.json" "$values" <<'PY' || fails=$((fails + 1))
import json, sys
plan, values = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))
repo, sub, ws = values["reponame"], values["subdomain"], values["orunWorkspace"]
problems = []
def bad(m): problems.append(m)
jobs = {(j["component"], j["environment"]): j for j in plan["jobs"]}
want = {("cloudflare-r2", "stage"), ("cloudflare-r2", "prod"), ("web", "stage"), ("web", "prod")}
if set(jobs) != want:
    bad(f"the 01-product merge plans {sorted(jobs)}; it must apply cloudflare-r2 and deploy web on "
        f"stage and prod, and nothing else (dev's push lanes are deferred)")

def refs(j):
    return {r["asEnv"]: r["ref"] for r in j.get("secretRefs") or []}
def ours(ref):
    return ref.startswith(f"secret://{ws}/") and (f"/{repo}/" in ref or f"project:{repo}" in ref)

for env in ("stage", "prod"):
    r2, web = jobs.get(("cloudflare-r2", env)), jobs.get(("web", env))
    if not r2 or not web:
        continue
    # INFRA BEFORE APP: the Worker's deploy waits for its own environment's
    # R2 apply, and for nothing else — not the other environment, not stage.
    if not r2["profile"].endswith(".apply"):
        bad(f"cloudflare-r2@{env} plans profile {r2['profile']}, not an apply")
    if r2.get("dependsOn"):
        bad(f"cloudflare-r2@{env} waits on {r2['dependsOn']} — during the bootstrap stage and prod apply side by side")
    if not web["profile"].endswith(".deploy"):
        bad(f"web@{env} plans profile {web['profile']}, not a deploy")
    if (web.get("dependsOn") or []) != [r2["id"]]:
        bad(f"web@{env} waits on {web.get('dependsOn')}; it must wait on {r2['id']} alone (infra before app)")
    steps = {s["id"]: s.get("run") or "" for s in web["steps"]}
    for need in ("verify-app-structure", "build-app", "deploy", "smoke"):
        if need not in steps:
            bad(f"web@{env} has no {need} step")
    if "tooling/wire/live.mjs" not in steps.get("build-app", "") or "--components cloudflare-r2" not in steps.get("build-app", ""):
        bad(f"web@{env}'s build does not render the R2 wiring: {steps.get('build-app','').strip()}")
    if f'EFFECTIVE_WORKER_NAME="{repo}-web-{env}"' not in steps.get("deploy", ""):
        bad(f"web@{env} deploys a Worker not named {repo}-web-{env}")
    if "/api/health" not in steps.get("smoke", ""):
        bad(f"web@{env}'s smoke does not check the Worker-answered /api/health")
    r = refs(web)
    for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID", f"WIRING_CLOUDFLARE_R2_{env.upper()}"):
        if not ours(r.get(key, "")):
            bad(f"web@{env} resolves {key} from {r.get(key) or 'nowhere'} — not the product's workspace and project")
    if r.get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_R2_TOKEN"):
        bad(f"web@{env} deploys with the R2 key; the deploy token is workers-deploy's CLOUDFLARE_API_TOKEN")
    r = refs(r2)
    for key in ("CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"):
        if not ours(r.get(key, "")):
            bad(f"cloudflare-r2@{env} resolves {key} from {r.get(key) or 'nowhere'} — not the product's")
    if not r.get("CLOUDFLARE_API_TOKEN", "").endswith("/CLOUDFLARE_R2_TOKEN"):
        bad(f"cloudflare-r2@{env} authenticates with {r.get('CLOUDFLARE_API_TOKEN')}, not the r2-data key "
            f"CLOUDFLARE_R2_TOKEN — workers-deploy carries no R2")
# The lanes say the same: the applies first, each deploy one level down.
level = {l["id"]: l.get("level") for l in plan.get("lanes") or []}
lane_of = {jid: l["id"] for l in plan.get("lanes") or [] for jid in l["jobs"]}
for env in ("stage", "prod"):
    k, w = lane_of.get(f"cloudflare-r2.{env}.terraform"), lane_of.get(f"web.{env}.verify-deploy")
    if k and w and not (level.get(k) == 0 and level.get(w) == 1):
        bad(f"{env}: the R2 lane is level {level.get(k)} and the web lane level {level.get(w)} — want 0 then 1")
if problems:
    for p in problems:
        print(f"  ✕ {p}", file=sys.stderr)
    sys.exit(1)
print("   cloudflare-r2 → stage + prod, apply (r2-data key), level 0; web → stage + prod, deploy")
print("   (workers-deploy key), level 1, each waiting on its own environment's apply alone (infra before app);")
print("   Worker, wiring, smoke and secrets the product's own")
PY

echo "── …the same edge on a pull request: advisory, nothing waits"
git -C "$tree" worktree add -q "$scratch/pr" "$s01"
echo "// a change" >> "$scratch/pr/apps/web/app/page.tsx"
echo "# a change" >> "$scratch/pr/infra/terraform/cloudflare-r2/terraform/main.tf"
git -C "$scratch/pr" -c user.email=t@example.invalid -c user.name=t commit -qam "a pull request"
(cd "$scratch/pr" && orun plan --intent intent.yaml --trigger github-pull-request --changed \
   --base "$s01" --head HEAD --output "$scratch/plan-pr.json") > "$scratch/plan-pr.log" 2>&1 \
  || { fail "orun plan failed for a pull request"; tail -15 "$scratch/plan-pr.log" >&2; }
python3 - "$scratch/plan-pr.json" <<'PY' || fails=$((fails + 1))
import json, sys
plan = json.load(open(sys.argv[1]))
jobs = {(j["component"], j["environment"]): j for j in plan["jobs"]}
problems = []
for env in ("stage", "prod"):
    web, r2 = jobs.get(("web", env)), jobs.get(("cloudflare-r2", env))
    if not web or not r2:
        problems.append(f"the pull request plans no web or cloudflare-r2 job on {env}")
        continue
    if not web["profile"].endswith(".verify") or not r2["profile"].endswith(".plan-only"):
        problems.append(f"{env}: a pull request plans {web['profile']} and {r2['profile']} — it must verify and plan only")
    if r2["id"] in (web.get("dependsOn") or []):
        problems.append(f"web@{env} waits on {r2['id']} on a pull request — the edge must be advisory there")
for p in problems:
    print(f"  ✕ {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
[ "$fails" -eq 0 ] && echo "   web verifies beside the R2 plan on stage and prod; neither waits"
git -C "$tree" worktree remove --force "$scratch/pr"

echo "── …and the 02-docs merge plans nothing"
(cd "$tree" && orun plan --intent intent.yaml --trigger github-push-main --changed \
   --base "$s01" --head "$s02" --output "$scratch/plan-02.json") > "$scratch/plan-02.log" 2>&1 \
  || { fail "orun plan failed for the 02-docs merge"; tail -15 "$scratch/plan-02.log" >&2; }
jobs02="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['jobs']))" "$scratch/plan-02.json" 2>/dev/null || echo '?')"
[ "$jobs02" = 0 ] && echo "   0 jobs: restoring the gates and writing the record redeploys nothing" \
  || fail "the 02-docs merge plans $jobs02 job(s); it touches no component and must plan none"

# ── 5. a resume over the finished site ────────────────────────────────────
echo "── --resume over the finished product"
before="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" --resume "${sets[@]}" > "$scratch/resume.log" 2>&1 \
  || { fail "--resume did not run"; tail -10 "$scratch/resume.log" >&2; }
after="$(git -C "$tree" status --porcelain; git -C "$tree" rev-parse HEAD)"
[ "$before" = "$after" ] || { fail "--resume changed the finished product:"; git -C "$tree" status --short | head -10 >&2; }
grep -q "SITE_NAME = \"Sam's Tees & Mugs\"" "$tree/apps/web/app/site.ts" \
  || fail "--resume reverted the product's identity"
[ "$fails" -eq 0 ] && echo "   nothing placed again, nothing un-branded"

[ "$fails" -eq 0 ] || { echo "placement.test.sh: $fails failure(s)" >&2; exit 1; }
echo "placement.test.sh: ok"
