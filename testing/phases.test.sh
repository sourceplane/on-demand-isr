#!/usr/bin/env bash
# The phases in `repo-blueprint.yaml` must be the phases the bootstrap runs,
# placing what they are meant to place, saying what they are, and naming only
# what the engine can resolve.
#
# The partition below is the bootstrap's order, written down a second time on
# purpose. It is the one-landing shape (cirrus-baseline v22): `01-product`
# places EVERY module and is the one phase that deploys; `02-docs` places
# nothing. The order that used to need separate landings — the R2 bucket
# before the Worker that binds it — is carried by the plan instead, and this
# file checks the edges that carry it: every component that reads a wiring
# document waits, on a merge to main, for the infra component that publishes
# it. Each reader resolves its document in the convergence from the place
# every later run looks, so a green convergence says the document is there —
# no separate check. A module that drifts into another phase, or an edge that
# goes missing, fails at landing time, live, with nothing in this repository
# having looked wrong.
#
# And the shape that keeps a bootstrap fast (orun >= v2.88.0): the run-level
# task set-up runs in the background, each phase finds its task just before
# its landing, each landing checks its commit here (`checks: local`), and the
# convergence watch reads every few seconds.
#
# Adapted from sourceplane/cirrus-baseline's testing/phases.test.sh: the
# narration rules and the hook-only rule are Cirrus's, unchanged.
#
# bash + python3 + PyYAML. No network, no fakes, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── repo-blueprint.yaml phases against what the bootstrap runs"
python3 - "$root" <<'PY'
import pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the phase contract test (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []
def bad(m): problems.append(m)

bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
phases = bp.get("phases") or []
if not phases:
    sys.exit("repo-blueprint.yaml declares no phases — this check has gone blind")

PARTITION = {
    "01-product": ["ai-deployment", "ai-operations", "cloudflare-r2", "discovery-roots",
                   "github-workflows", "rebrand-values", "root-gitignore", "root-intent",
                   "root-package-json", "root-pnpm-lock",
                   "root-pnpm-workspace", "root-readme", "root-turbo", "tooling-eslint",
                   "tooling-tsconfig", "tooling-wire", "vscode", "web", "web-tests"],
    "02-docs": [],
}
HOOK_ONLY = {"02-docs"}
# The phases that DEPLOY, and so must give a re-run something to land.
DEPLOYS = {"01-product"}
# Each phase's pre, post and await hooks, in order — the one-landing recipe.
# The brokered keys are one `secrets` reconcile. No phase has a `pre` hook:
# the task is found in `post`, just before the landing, so that everything
# before it runs beside the background task set-up. No phase awaits the
# wiring: the site's deploy resolves it in the convergence (checked below).
PRE = {"01-product": [], "02-docs": []}
POST = {
    "01-product": ["retouch", "git-init", "stage", "rebrand", "orun-workspace", "work-tree",
                   "promotion", "dev-lanes", "restage", "rebrand-verify",
                   "repo", "link", "secrets", "task", "land"],
    "02-docs": ["promotion", "dev-lanes", "render", "task", "land"],
}
AWAIT = {"01-product": ["converge", "verify"], "02-docs": []}

by_name = {p["name"]: p for p in phases}
names = [p["name"] for p in phases]

# ── the order IS the execution order ──────────────────────────────────────
if names != sorted(names):
    bad(f"phases are not in execution order: {names}. The numbered name IS the "
        f"order; a phase out of sequence is a barrier in the wrong place.")
if names != list(PARTITION):
    bad(f"phases are {names}; the bootstrap runs {list(PARTITION)}")

# ── the partition has not drifted ─────────────────────────────────────────
for name, want in PARTITION.items():
    if name not in by_name:
        continue
    now = sorted(by_name[name].get("modules") or [])
    if now != sorted(want):
        bad(f"phase {name} no longer places what it placed: gained "
            f"{sorted(set(now) - set(want)) or '[]'}, lost {sorted(set(want) - set(now)) or '[]'}")
declared = {m["name"] for m in bp.get("modules") or []}
placed = {m for p in phases for m in (p.get("modules") or [])}
for m in sorted(declared - placed):
    bad(f"module {m} is declared and no phase places it")
for name in HOOK_ONLY:
    if by_name.get(name, {}).get("modules"):
        bad(f"phase {name} places modules — it is declared as hooks only")

# ── nothing may GATE on a phase the tree cannot answer for ────────────────
# A hook-only phase places no files, so orun derives it as `unknown`, and
# `requires.phases` fails closed on `unknown`: a requirement naming one can
# never be satisfied.
for p in phases:
    for need in ((p.get("requires") or {}).get("phases") or []):
        if need in HOOK_ONLY:
            bad(f"phase {p['name']} requires {need}, which places no files — require "
                f"its predecessor instead")
        if need not in by_name or names.index(need) >= names.index(p["name"]):
            bad(f"phase {p['name']} requires {need}, which does not run before it")

# ── every phase says what it is and what to budget ────────────────────────
for p in phases:
    for field in ("title", "expectedMinutes"):
        if not p.get(field):
            bad(f"phase {p['name']} declares no {field} — an operator reads both")
    if not (p.get("hooks") or {}):
        bad(f"phase {p['name']} declares no hooks — a phase that only places files "
            f"still has to land them")

def hooks_of(p):
    h = p.get("hooks") or {}
    if isinstance(h, list):
        return list(h)
    return [x for slot in ("pre", "post", "await") for x in (h.get(slot) or [])]

run_hooks = list((bp.get("hooks") or {}).get("preInstantiate") or [])

# ── every phase lands, and every landing is bound to its task ─────────────
for p in phases:
    ids = [h.get("id") for h in hooks_of(p)]
    lands = [h for h in hooks_of(p) if (h.get("uses") or "").startswith("orun.pr/land@")]
    if len(lands) != 1:
        bad(f"phase {p['name']} has {len(lands)} landing(s); a phase is ONE pull request")
        continue
    w = lands[0].get("with") or {}
    if w.get("task") != "{{ .phase.hooks.task.outputs.key }}":
        bad(f"phase {p['name']} lands without binding the PR to its task key")
    if "task" not in ids or ids.index("task") > ids.index(lands[0].get("id")):
        bad(f"phase {p['name']} must ensure its task before it lands")
    if p["name"] in DEPLOYS:
        if not any("retouch.mjs" in " ".join(h.get("run") or []) for h in hooks_of(p)):
            bad(f"phase {p['name']} deploys and has no retouch hook — a re-run after a "
                f"failed convergence would land an empty diff and redeploy nothing")
        awaits = (p.get("hooks") or {}).get("await") or []
        watch = [h for h in awaits if (h.get("uses") or "").startswith("orun.run/watch@")]
        if not watch or (watch[0].get("with") or {}).get("sha") != "{{ .phase.hooks.land.outputs.mergeSha }}":
            bad(f"phase {p['name']} deploys and does not watch the convergence of the "
                f"commit it merged (orun.run/watch@v1 with sha: mergeSha)")

# ── the hooks run in the one-landing order ────────────────────────────────
for name, want in PRE.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("pre") or [])]
    if got != want:
        bad(f"phase {name}'s pre hooks are {got}; want {want} — a task found in `pre` waits "
            f"for the background task set-up before the phase has done anything")
for name, want in POST.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("post") or [])]
    if got != want:
        bad(f"phase {name}'s post hooks are {got}; the one-landing order is {want}")
for name, want in AWAIT.items():
    got = [h.get("id") for h in ((by_name.get(name, {}).get("hooks") or {}).get("await") or [])]
    if got != want:
        bad(f"phase {name}'s await hooks are {got}; want {want}")
for p in phases:
    if p["name"] not in DEPLOYS:
        for h in hooks_of(p):
            if (h.get("uses") or "").startswith(("orun.integrations/reconcile@", "orun.run/watch@")):
                bad(f"phase {p['name']} deploys nothing and runs {h['uses']} ({h.get('id')})")

# ── INFRA BEFORE APP: the order the one landing relies on ─────────────────
# Every infra component that lease-publishes a wiring document
# (`secretOutputs: "WIRING_X=wiring"`), and every component that reads one
# (`WIRING_X_<ENV>` in secretEnv). A reader must wait for its publisher on a
# merge to main — `mode: enforced` — and not on a pull request, which deploys
# nothing (`modeRules` advisory on github-pull-request): a job resolves its
# secrets when it STARTS, so without the edge the first convergence's deploy
# would start before the apply had published the id it binds.
comps = {}
for f in root.rglob("component.yaml"):
    if "node_modules" in f.parts:
        continue
    d = yaml.safe_load(f.read_text()) or {}
    comps[(d.get("metadata") or {}).get("name")] = (f.relative_to(root).as_posix(), d.get("spec") or {})
publishes = {}
for name, (rel, spec) in comps.items():
    outs = str((spec.get("parameters") or {}).get("secretOutputs") or "")
    for pair in filter(None, (x.strip() for x in outs.split(","))):
        key = pair.split("=", 1)[0]
        if key.startswith("WIRING_"):
            publishes[key] = name
if not publishes:
    bad("no infra component lease-publishes a WIRING_* document — this check has gone blind")
readers = 0
for name, (rel, spec) in comps.items():
    keys = {re.sub(r"_(DEV|STAGE|PROD)$", "", k) for k in (spec.get("secretEnv") or {}) if k.startswith("WIRING_")}
    for key in sorted(keys):
        readers += 1
        pub = publishes.get(key)
        if not pub:
            bad(f"{rel} reads {key}, which no infra component publishes")
            continue
        edge = next((d for d in spec.get("dependsOn") or [] if d.get("component") == pub), None)
        rules = (edge or {}).get("modeRules") or []
        advisory_on_pr = any(r.get("mode") == "advisory"
                             and ((r.get("when") or {}).get("triggerRef") == "github-pull-request")
                             for r in rules)
        if not edge or edge.get("mode") != "enforced" or not advisory_on_pr:
            bad(f"{rel} reads {key} and does not wait for {pub} on a merge to main — declare "
                f"dependsOn {pub} with mode: enforced and a modeRules advisory on github-pull-request")
        mod = next((m for m in bp.get("modules") or [] if (m.get("from") or "").rstrip("/") == rel.rsplit("/", 1)[0]), None)
        pub_mod = next((m["name"] for m in bp.get("modules") or []
                        if (m.get("from") or "").rstrip("/") == comps[pub][0].rsplit("/", 1)[0]), None)
        if mod and pub_mod and pub_mod not in (mod.get("dependsOn") or []):
            bad(f"module {mod['name']} reads {key} and is not placed after {pub_mod} (module dependsOn)")
# …and every document published is one a component in the convergence
# resolves, on stage AND prod, from the place every later run looks (its
# secretEnv: `secret://<project>/<project>/<env>/WIRING_X`). That read is what
# replaced the `wiring` await: a job resolves its secrets when it starts,
# fail-closed, so a green convergence says every one of them is there. A
# document nothing reads in the convergence would need the await back.
read_from = {}
for name, (rel, spec) in comps.items():
    for env_key, ref in (spec.get("secretEnv") or {}).items():
        m = re.match(r"^secret://[^/]+/[^/]+/(stage|prod)/(WIRING_[A-Z0-9_]+)$", str(ref))
        if m:
            read_from.setdefault(m.group(2), set()).add(m.group(1))
for key in sorted(publishes):
    if read_from.get(key, set()) != {"stage", "prod"}:
        bad(f"{key} is published and no component resolves it on both stage and prod "
            f"(it is read on {sorted(read_from.get(key, set())) or 'none'}) — nothing in the "
            f"convergence proves it is there; read it, or await it with orun.secrets/exists@v1")
for p in phases:
    for h in hooks_of(p):
        if (h.get("uses") or "").startswith("orun.secrets/exists@"):
            keys = set((h.get("with") or {}).get("keys") or [])
            proven = {k for k in keys if read_from.get(k, set()) >= {"stage", "prod"}}
            if proven:
                bad(f"phase {p['name']} awaits {sorted(proven)} with orun.secrets/exists@v1, which "
                    f"the convergence's own lanes already resolve on stage and prod — a second check")

# ── THE FAST SHAPE (orun >= v2.88.0) ──────────────────────────────────────
# The run-level list is the task set-up, all of it in the background: the
# first phase's provider check, placement, rebrand, repository and secrets
# run while it opens the epic, the milestones and the tasks.
for h in run_hooks:
    if not h.get("background"):
        bad(f"hooks.preInstantiate {h.get('id')} is not `background: true` — the first phase "
            f"waits for it before doing anything, though nothing before its landing reads it")
# No phase keeps a `pre` hook on the task plane: one there waits for the
# whole background list before the phase has done anything.
PLANE = ("orun.task/", "orun.pr/land@")
for p in phases:
    for h in ((p.get("hooks") or {}).get("pre") or []):
        if (h.get("uses") or "").startswith(PLANE):
            bad(f"phase {p['name']} pre hook {h.get('id')} uses the task plane ({h['uses']}) — "
                f"move it to `post`, just before the landing")
# Every landing checks its commit here and merges, instead of waiting for a
# runner to plan the tree this box just wrote.
for p in phases:
    for h in hooks_of(p):
        if (h.get("uses") or "").startswith("orun.pr/land@") and (h.get("with") or {}).get("checks") != "local":
            bad(f"phase {p['name']} lands with checks {(h.get('with') or {}).get('checks', 'ci')!r}, "
                f"not 'local' — it waits for a runner to plan a tree that is here")
# The convergence watch reads every few seconds, not the action's default 40.
for p in phases:
    for h in ((p.get("hooks") or {}).get("await") or []):
        if (h.get("uses") or "").startswith("orun.run/watch@"):
            every = (h.get("with") or {}).get("pollSeconds")
            if not isinstance(every, int) or every > 10:
                bad(f"phase {p['name']} watches its convergence every {every or 40} s; at most 10 — "
                    f"the build goes on that much after the run is green")

# ── every phase's task is one the run-level list opens, in the same order ─
def task_names(hooks):
    return [(h.get("with") or {}).get("name") for h in hooks
            if (h.get("uses") or "").startswith("orun.task/ensure@")
            and (h.get("with") or {}).get("kind") == "task"]
opened = task_names(run_hooks)
per_phase = [n for p in phases for n in task_names(hooks_of(p))]
if opened != per_phase:
    bad(f"the run-level list opens tasks {opened}; the phases ensure {per_phase} — "
        f"a task is found by its title, so the two must be the same words")
milestones = [(h.get("with") or {}).get("name") for h in run_hooks
              if (h.get("with") or {}).get("kind") == "milestone"]
if milestones != names:
    bad(f"the run-level list opens milestones {milestones}; the phases are {names}")

# ── every contract a hook names exists, beside the blueprint ──────────────
for h in run_hooks + [x for p in phases for x in hooks_of(p)]:
    rel = (h.get("with") or {}).get("contract")
    if rel and not (root / rel).exists():
        bad(f"hook {h.get('id')} names contract {rel}, which does not exist")
    if rel and not rel.startswith(".baseline/tasks/"):
        bad(f"hook {h.get('id')} names contract {rel} outside .baseline/tasks/ — "
            f"`tasks/` is this repository's own work tree, where an unkeyed "
            f"contract is an error")
for p in phases:
    for h in hooks_of(p):
        argv = " ".join(h.get("run") or [])
        for ref in re.findall(r"\{\{ \.baseline\.dir \}\}/(\S+?)(?:\"|'|\s|$)", argv + " "):
            if not (root / ref).exists():
                bad(f"phase {p['name']} hook {h.get('id')} runs {ref}, which this "
                    f"repository does not have")

# ── every phase has a documentation page, and every page a phase ──────────
docs_dir = root / "docs" / "phases"
pages = {f.stem for f in docs_dir.glob("*.md")} - {"README"}
for n in names:
    if n not in pages:
        bad(f"phase {n} has no page at docs/phases/{n}.md")
for page in sorted(pages - set(names)):
    bad(f"docs/phases/{page}.md documents a phase repo-blueprint.yaml does not declare")

# ── narration: authored here, printed from state (Cirrus's rules) ─────────
META_AT = {
    "start": {"files", "expectedMinutes"},
    "await": {"files", "expectedMinutes"},
    "failed": {"files", "expectedMinutes"},
    "done": {"files", "expectedMinutes", "elapsed", "next"},
}
STATE_WORDS = {"done", "failed", "complete", "completed", "succeeded", "skipped"}
PHASE_KEYS = {"name", "title"}
input_keys = set((bp.get("inputs") or {}).keys())

ws_input = (bp.get("inputs") or {}).get("orunWorkspace") or {}
if ws_input.get("from") != "workspace":
    bad("inputs.orunWorkspace must declare `from: workspace` — a console build has no other way to say it")

def strip_expressions(line):
    return re.sub(r"\{\{.*?\}\}", "", line, flags=re.S)

def refs(line):
    found = []
    for expr in re.findall(r"\{\{(.*?)\}\}", line, re.S):
        found += re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expr)
    return found

def check_line(where, line, slot, hook_ids):
    prose = strip_expressions(line).lower()
    for w in STATE_WORDS:
        if re.search(rf"\b{w}\b", prose):
            bad(f"{where} asserts {w!r} — `state` is the truth and narration is the "
                f"caption. Describe the world, not the run.")
    for ref in refs(line):
        parts = ref.split(".")
        head = parts[0]
        if head == "phase":
            if len(parts) != 2 or parts[1] not in PHASE_KEYS:
                bad(f"{where} names .{ref}; a phase carries {sorted(PHASE_KEYS)}")
        elif head == "inputs":
            if len(parts) != 2 or parts[1] not in input_keys:
                bad(f"{where} names .{ref}, which is not a declared input")
        elif head == "meta":
            allowed = META_AT.get(slot, META_AT["start"])
            if len(parts) != 2 or parts[1] not in allowed:
                bad(f"{where} names .{ref}; the {slot} event carries {sorted(allowed)}")
        elif head == "hooks":
            if len(parts) < 2 or parts[1] not in hook_ids:
                bad(f"{where} names .{ref}; this phase has no such hook")
        else:
            bad(f"{where} names .{ref}; narration may reference phase, inputs, meta and hooks")

for p in phases:
    n = p.get("narrate") or {}
    ids = {h.get("id") for h in hooks_of(p)}
    awaits = bool((p.get("hooks") or {}).get("await"))
    for slot in ("start", "await", "done", "failed"):
        line = n.get(slot)
        if slot == "await" and not awaits:
            # A phase that waits on nothing never says its await line.
            if line:
                bad(f"phase {p['name']} declares narrate.await and has no await hooks — "
                    f"nobody would ever read it")
            continue
        if not line:
            bad(f"phase {p['name']} declares no narrate.{slot}")
            continue
        check_line(f"phase {p['name']} narrate.{slot}", line, slot, ids)
    for h in ((p.get("hooks") or {}).get("await") or []):
        line = h.get("narrate")
        if not line:
            bad(f"phase {p['name']} await hook {h.get('id')} declares no narrate — a "
                f"wait with no words reads as a stalled build")
            continue
        check_line(f"phase {p['name']} hook {h.get('id')} narrate", line, "done", ids)
    for slot in ("pre", "post"):
        for h in ((p.get("hooks") or {}).get(slot) or []):
            if h.get("narrate"):
                check_line(f"phase {p['name']} hook {h.get('id')} narrate", h["narrate"], "start", ids)

# ── what a baseline of this shape never grows back ────────────────────────
if (root / "flows").exists():
    bad("flows/ exists — the bootstrap is the blueprint; every mechanism is a typed orun action")

if problems:
    print("FAIL: the blueprint's phases and the bootstrap disagree:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

placed_n = sum(len(p.get("modules") or []) for p in phases)
print(f"   {len(publishes)} wiring document(s), {readers} reader(s), each waiting for its publisher on main")
narrated = sum(len(p.get("narrate") or {}) for p in phases)
narrated += sum(1 for p in phases for h in hooks_of(p) if h.get("narrate"))
print(f"   {len(phases)} phases, {placed_n} modules, {len(HOOK_ONLY)} hook-only — in execution order")
print(f"   {narrated} authored narration lines, every reference resolving")
PY

echo "phases.test.sh: ok"
