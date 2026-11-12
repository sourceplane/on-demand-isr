#!/usr/bin/env bash
# hooks/render-deployment-docs.sh runs in the build box, which has python3 but
# not PyYAML: a hook that imports yaml stops the record phase with exit 1
# while the site is live. This runs the hook on a scaffolded site tree under a
# python3 with no third-party packages (and again with the system python3,
# when it has PyYAML), and checks the record it writes: the workspace read
# from intent.yaml, the site's Workers and R2 buckets, a probe row per
# environment (no such Worker exists, so whatever answers — nothing offline,
# workers.dev's 404 online — is not the site's /api/health), the GitHub App's
# three optional secrets named, and the README's live-deployment section.
#
# Needs: bash, python3 (with venv), curl. The network is optional.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

python3 -m venv --without-pip "$work/bare"
if "$work/bare/bin/python3" -c 'import yaml' 2>/dev/null; then
  echo "render.test.sh: the bare python3 still imports yaml — cannot test" >&2; exit 1
fi
if grep -nE '^\s*(import|from)\s+yaml\b|import yaml' "$here/hooks/render-deployment-docs.sh"; then
  echo "render.test.sh: the hook imports yaml, which the build box does not have" >&2; exit 1
fi

product="$work/product"; mkdir -p "$product/.github/workflows" "$product/.rebrand"
printf '{"reponame":"acme-issues","subdomain":"acme"}\n' > "$product/.rebrand/values.json"
printf '# acme-issues\n\nIssues, regenerated on demand.\n\n## Live deployment\n\n<!-- 02-docs:begin -->\nNot recorded yet.\n<!-- 02-docs:end -->\n\n## What is here\n' > "$product/README.md"
printf 'jobs:\n  lane:\n    steps:\n      - with:\n          version: v2.78.4\n' > "$product/.github/workflows/ci.yml"
cat > "$product/intent.yaml" <<'YAML'
execution:
  state:
    # the site's own workspace
    workspace: ws_TEST0000  # set by the bootstrap
environments:
  stage:
    env:
      BASE_DOMAIN: acme-issues.example.com
YAML

fail=0
for py in "$work/bare/bin" ""; do
  label="${py:+without PyYAML}"; label="${label:-with the system python3}"
  [ -n "$py" ] || python3 -c 'import yaml' 2>/dev/null || { echo "   (skipped: the system python3 has no PyYAML)"; continue; }
  rm -rf "$product/ai"
  # No workspace argument: the hook reads it from intent.yaml.
  if ! (cd "$product" && PATH="${py:+$py:}$PATH" bash "$here/hooks/render-deployment-docs.sh" . "" "$here" >/dev/null 2>"$work/err"); then
    echo "  ✕ $label: the hook failed"; sed 's/^/      /' "$work/err"; fail=1; continue
  fi
  rec="$product/ai/context/deployment.md"
  bad() { echo "  ✕ $label: $1"; fail=1; }
  grep -q '| Orun workspace | `ws_TEST0000` |' "$rec" || bad "the workspace is not read from intent.yaml"
  grep -q '`acme-issues-web-stage`, `acme-issues-web-prod` on `acme.workers.dev`' "$rec" || bad "the Workers are not the site's"
  grep -q '`stg-acme-issues-stage`, `prod-acme-issues-prod`' "$rec" || bad "the R2 buckets are not the site's"
  for env in stage prod; do
    grep -qE "^\| site \(${env}\) \| https://acme-issues-web-${env}\.acme\.workers\.dev \| (unreachable|answering [0-9]{3}(, /api/health not answered by the Worker)?) \|$" "$rec" \
      || bad "the ${env} probe row is wrong (or claims a Worker answered)"
  done
  grep -q '| `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` | `acme-issues` on stage and on prod, set by the owner (optional)' "$rec" || bad "the App's ID and key are not named"
  grep -q '| `GITHUB_WEBHOOK_SECRET` | `acme-issues` on stage and on prod, set by the owner (optional)' "$rec" || bad "the webhook secret is not named"
  grep -q 'Connecting a GitHub' "$rec" || bad "the record does not say how to connect a GitHub App"
  grep -q 'orun `v2.78.4`' "$rec" || bad "the CI lane pin is not read"
  grep -q 'This site is \*\*live\*\*' "$product/README.md" || bad "the README's live-deployment section is not rendered"
  [ "$(grep -c '<!-- 02-docs:begin -->' "$product/README.md")" = 1 ] || bad "the README's section is not replaced in place"
  [ -f "$product/ai/context/operations.md" ] || bad "operations.md was not healed from the baseline's copy"
  [ "$fail" = 0 ] && echo "   $label: record rendered, the workspace read from intent.yaml"
done
[ "$fail" = 0 ] || exit 1
echo "render.test.sh: ok"
