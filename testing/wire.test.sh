#!/usr/bin/env bash
# THE WIRING PATH — from a Terraform apply to the id in a deployed Worker's
# config — holds end to end, offline.
#
# An infra component lease-publishes a wiring document after its apply
# (`secretOutputs: "WIRING_<ROOT>=wiring"`, the root's `output "wiring"`); a
# deployable names the values it needs as tokens in `wrangler.template.jsonc`
# (`@@wiring(<root>/__ENV__:<key>)@@`), and its build renders `wrangler.jsonc`
# from the document (`tooling/wire/live.mjs`, in the component's
# buildCommand). Four things can drift apart there, and each fails a real
# deploy, late:
#
#   1. a token naming a key the root does not output, or a root that publishes
#      nothing — the render fails on the deploy lane;
#   2. the fixture missing an environment the deployable builds for — its
#      verify lane fails;
#   3. the committed wrangler.jsonc not being the fixture render — the deploy
#      lane's `verify-app-structure` checks the config exists BEFORE the build
#      (stack-tectonic's workers-assets composition), so the file is
#      committed, and a stale one is what a reader finds;
#   4. the build's render command: a deployed environment must render from
#      the real document and refuse to run without it, and a verify-only one
#      (`dev`, where no root applies) must render from the fixture.
#
# Every templated deployable in the tree is checked, against the commands
# its own component.yaml declares.
#
# Needs: node, python3 (+PyYAML). No network, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
fail=0
ok() { echo "   ok  $1"; }
bad() { echo "   ✕  $1" >&2; fail=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Every templated deployable, and what the infra publishes — read once.
python3 - "$root" > "$tmp/facts.json" <<'PY'
import json, pathlib, re, sys
import yaml
root = pathlib.Path(sys.argv[1])
comps = {}
for f in root.rglob("component.yaml"):
    if "node_modules" in f.parts or ".orun" in f.parts:
        continue
    d = yaml.safe_load(f.read_text()) or {}
    comps[(d.get("metadata") or {}).get("name")] = {"dir": f.parent.relative_to(root).as_posix(), "spec": d.get("spec") or {}}
publishers = {}
for name, c in comps.items():
    outs = str((c["spec"].get("parameters") or {}).get("secretOutputs") or "")
    for pair in filter(None, (x.strip() for x in outs.split(","))):
        key, _, output = pair.partition("=")
        if not key.startswith("WIRING_"):
            continue
        tf = "\n".join(p.read_text() for p in (root / c["dir"]).rglob("*.tf"))
        m = re.search(r'output\s+"%s"\s*\{.*?jsonencode\(\{(.*?)\}\)' % re.escape(output), tf, re.S)
        keys = re.findall(r"^\s*([A-Za-z0-9_]+)\s*=", m.group(1), re.M) if m else []
        envs = [e["name"] for e in (c["spec"].get("subscribe") or {}).get("environments") or []]
        publishers[name] = {"key": key, "output": output, "keys": keys, "envs": envs}
deployables = []
for name, c in comps.items():
    tpl = root / c["dir"] / "wrangler.template.jsonc"
    if not tpl.exists():
        continue
    params = c["spec"].get("parameters") or {}
    envs = [e["name"] for e in (c["spec"].get("subscribe") or {}).get("environments") or []]
    tokens = sorted(set(re.findall(r"@@wiring\(([a-z0-9-]+)/__ENV__:([A-Za-z0-9_]+)\)@@", tpl.read_text())))
    deployables.append({"name": name, "dir": c["dir"], "envs": envs, "tokens": tokens,
                        "build": params.get("buildCommand") or "", "config": params.get("wranglerConfig") or "",
                        "secretEnv": sorted((c["spec"].get("secretEnv") or {}).keys())})
print(json.dumps({"publishers": publishers, "deployables": deployables}))
PY
n="$(python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['deployables']))" "$tmp/facts.json")"
[ "$n" -ge 1 ] || { echo "no wrangler.template.jsonc anywhere — this check has gone blind" >&2; exit 1; }

for i in $(seq 0 $((n - 1))); do
  eval "$(python3 - "$tmp/facts.json" "$i" <<'PY'
import json, shlex, sys
d = json.load(open(sys.argv[1]))["deployables"][int(sys.argv[2])]
for k in ("name", "dir", "build", "config"):
    print(f"{k}={shlex.quote(d[k])}")
print(f"envs={shlex.quote(' '.join(d['envs']))}")
PY
)"
  echo "── $name ($dir)"

  # 1 + 2: every token resolves against what its root outputs, and the
  # fixture covers every environment the deployable builds for.
  python3 - "$tmp/facts.json" "$i" "$root" <<'PY' && ok "every token names a key its root outputs; the fixture covers every environment, the dev rung included" || fail=1
import json, pathlib, sys
facts = json.load(open(sys.argv[1])); d = facts["deployables"][int(sys.argv[2])]; root = pathlib.Path(sys.argv[3])
pubs = facts["publishers"]
fixture = json.loads((root / d["dir"] / "wiring.fixture.json").read_text())
problems = []
if not d["tokens"]:
    problems.append("wrangler.template.jsonc carries no @@wiring(<root>/__ENV__:<key>)@@ token")
for comp, key in d["tokens"]:
    p = pubs.get(comp)
    if not p:
        problems.append(f"token {comp}:{key} — no infra component {comp} lease-publishes a WIRING_* document")
        continue
    if key not in p["keys"]:
        problems.append(f"token {comp}:{key} — {comp}'s output \"{p['output']}\" has {p['keys']}")
    for env in d["envs"]:
        if not (fixture.get(f"{comp}/{env}") or {}).get(key):
            problems.append(f"the fixture has no {comp}/{env}:{key} — the {env} lane renders it")
    for env in p["envs"]:
        want = f"{p['key']}_{env.upper()}"
        if env in d["envs"] and want not in d["secretEnv"]:
            problems.append(f"{env} deploys after {comp} applies there, and secretEnv does not resolve {want}")
for p in problems:
    print(f"   ✕  {p}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

  # 3: the committed config is the fixture render.
  if [ "$config" != "wrangler.jsonc" ] || [ ! -f "$root/$dir/wrangler.jsonc" ]; then
    bad "wranglerConfig is '$config' — the composition checks it exists before the build, so it must be the committed wrangler.jsonc"
  else
    (cd "$root/$dir" && node "$root/tooling/wire/render.mjs" --template wrangler.template.jsonc \
       --out "$tmp/rendered.jsonc" --map wiring.fixture.json --env stage) >/dev/null
    cmp -s "$tmp/rendered.jsonc" "$root/$dir/wrangler.jsonc" \
      && ok "the committed wrangler.jsonc is the fixture render" \
      || { bad "the committed wrangler.jsonc is not the fixture render — run \`pnpm run wire:fixture\` and commit it"; diff "$tmp/rendered.jsonc" "$root/$dir/wrangler.jsonc" | head -10 >&2 || true; }
  fi

  # 4: the build's own render command, cut from its buildCommand at the
  # first `&&` (the rest is the Next.js build), run in a copy of the app.
  render="${build%% && *}"
  case "$render" in *tooling/wire/live.mjs*) ;; *) bad "buildCommand does not start by rendering with tooling/wire/live.mjs: $build"; continue ;; esac
  rm -rf "$tmp/tree"; mkdir -p "$tmp/tree/$dir" "$tmp/tree/tooling"
  cp -r "$root/tooling/wire" "$tmp/tree/tooling/wire"
  cp "$root/$dir/wrangler.template.jsonc" "$root/$dir/wiring.fixture.json" "$tmp/tree/$dir/"
  run_render() { # ENV [KEY=VALUE…] — the render as the lane runs it, with only the given wiring in env
    local env="$1"; shift
    (cd "$tmp/tree/$dir" && env -i PATH="$PATH" HOME="$HOME" ORUN_ENVIRONMENT="$env" "$@" bash -c "$render")
  }
  for env in $envs; do
    rm -f "$tmp/tree/$dir/wrangler.jsonc"
    docs=(); ids=()
    for pair in $(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['deployables'][int(sys.argv[2])]; pubs=json.load(open(sys.argv[1]))['publishers']
for comp in sorted({c for c,_ in d['tokens']}):
    if sys.argv[3] in pubs[comp]['envs']: print(pubs[comp]['key']+'_'+sys.argv[3].upper()+'|'+comp)
" "$tmp/facts.json" "$i" "$env"); do
      key="${pair%%|*}"; comp="${pair#*|}"
      id="e2e$(printf '%s' "$key" | md5sum | cut -c1-29)"
      docs+=("$key=$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['deployables'][int(sys.argv[2])]
print(json.dumps({k: sys.argv[3] for c,k in d['tokens'] if c==sys.argv[4]}))" "$tmp/facts.json" "$i" "$id" "$comp")")
      ids+=("$id")
    done
    if [ "${#docs[@]}" -gt 0 ]; then
      # A deployed environment: the document wins, and without it the render refuses.
      if run_render "$env" "${docs[@]}" > "$tmp/r.log" 2>&1 && grep -q "${ids[0]}" "$tmp/tree/$dir/wrangler.jsonc"; then
        ok "$env renders from the published document (${#docs[@]} of them)"
      else
        bad "$env did not render from the published document"; sed 's/^/        /' "$tmp/r.log" >&2
      fi
      rm -f "$tmp/tree/$dir/wrangler.jsonc"
      if run_render "$env" > "$tmp/r.log" 2>&1; then
        bad "$env rendered with no wiring document — a deploy would ship the fixture's placeholder id"
      else
        grep -q "${docs[0]%%=*}" "$tmp/r.log" && ok "$env without its document refuses, naming ${docs[0]%%=*}" \
          || { bad "$env refused without naming the missing document"; cat "$tmp/r.log" >&2; }
      fi
    else
      # A verify-only environment: no root applies there, so the fixture.
      if run_render "$env" > "$tmp/r.log" 2>&1; then
        want="$(python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))['deployables'][int(sys.argv[2])]
fx=json.load(open(sys.argv[3]))
c,k=d['tokens'][0]; print(fx[c+'/'+sys.argv[4]][k])" "$tmp/facts.json" "$i" "$root/$dir/wiring.fixture.json" "$env")"
        grep -q "\"$want\"" "$tmp/tree/$dir/wrangler.jsonc" && grep -q 'verify-only' "$tmp/r.log" \
          && ok "$env (verify-only, no root applies) renders from the fixture, and says so" \
          || { bad "$env did not render the fixture's $env values"; cat "$tmp/r.log" >&2; }
      else
        bad "$env (verify-only) cannot render without a document no root publishes"; sed 's/^/        /' "$tmp/r.log" >&2
      fi
    fi
  done
done

[ "$fail" -eq 0 ] || { echo "wire.test.sh: failure(s)" >&2; exit 1; }
echo "wire.test.sh: ok"
