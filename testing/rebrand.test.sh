#!/usr/bin/env bash
# THE REBRAND WRITES EACH VALUE ONCE, AND WHAT IT WROTE STAYS WRITTEN.
#
# Drives the real tooling/rebrand/rebrand.mjs over one-file trees and compares
# the file. Each case is a shape this baseline's identity actually takes in the
# tree — the repository link (the repository whose issues the site lists), the site-name seam, the worker name in the
# component and the wrangler config (and the Worker's self-reference binding),
# the R2 bucket names and the terraform `repo` they are built from, the
# placeholder domain, a secret ref — and the survival cases run through three
# passes, so a value an earlier rebrand wrote (a re-run phase re-runs the
# rebrand over everything placed) comes out of every later one unchanged.
#
# Two cases pin what makes a shipped file spell this baseline's slug and its
# code form only where they ARE the identity: the slug in prose IS the slug to
# the rename, and the Pascal form anywhere is residue. GitHub's own words (the
# App's GITHUB_* settings) are not this identity, and the template's upstream
# names (vercel/on-demand-isr, nextjs/on-demand-isr, on-demand-isr.vercel.app)
# are protected: cases pin that no rule touches either.
#
# The identity is PINNED (fixtures/baseline-identity.on-demand-isr.json) rather
# than read from .baseline/identity.json: what this tests is the engine, and
# its fixtures spell the identity out literally.
#
# Needs: node, git. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
rebrand="$here/../tooling/rebrand/rebrand.mjs"
identity="$here/fixtures/baseline-identity.on-demand-isr.json"

fail=0
# check NAME VALUES-JSON FILE CONTENT WANT [PASSES]
check() {
  local name="$1" values="$2" file="$3" content="$4" want="$5" passes="${6:-1}"
  local tmp got out i
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  for ((i = 1; i <= passes; i++)); do
    git -C "$tmp" add -A
    if ! out="$(cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty 2>&1)"; then
      echo "   ✕  $name: rebrand pass $i failed:" >&2
      printf '%s\n' "$out" | sed 's/^/        /' >&2
      fail=1
      rm -rf "$tmp"
      return
    fi
  done
  got="$(cat "$tmp/$file")"
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then
    echo "   ok  $name"
  else
    echo "   ✕  $name:" >&2
    echo "        got:  $got" >&2
    echo "        want: $want" >&2
    fail=1
  fi
}

acme='{"reponame":"acme-issues","productname":"Acme Issues","productdomain":"issues.acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'

echo "── rebrand: the site's own identity"
check "the repository link names the product's owner and repository" \
  "$acme" README.md \
  'The source is [github.com/sourceplane/on-demand-isr](https://github.com/sourceplane/on-demand-isr).' \
  'The source is [github.com/acme-inc/acme-issues](https://github.com/acme-inc/acme-issues).'
check "the site-name seam takes the product's name" \
  "$acme" apps/web/app/site.ts 'export const SITE_NAME = "On-Demand Incremental Static Regeneration";' \
  'export const SITE_NAME = "Acme Issues";'
check "…and stays a valid string for a name with an apostrophe and an ampersand" \
  '{"reponame":"sams-issues","productname":"Sam'"'"'s Tees & Mugs","productdomain":"sam.dev"}' \
  apps/web/app/site.ts 'export const SITE_NAME = "On-Demand Incremental Static Regeneration";' \
  'export const SITE_NAME = "Sam'"'"'s Tees & Mugs";'
check "the worker name is re-prefixed" \
  "$acme" apps/web/component.yaml 'workerName: on-demand-isr-web' \
  'workerName: acme-issues-web'
check "the wrangler config's worker name, the environment token kept" \
  "$acme" apps/web/wrangler.template.jsonc '  "name": "on-demand-isr-web-__ENV__",' \
  '  "name": "acme-issues-web-__ENV__",'
check "the Worker's self-reference binding names the same Worker" \
  "$acme" apps/web/wrangler.jsonc \
  '    { "binding": "WORKER_SELF_REFERENCE", "service": "on-demand-isr-web-stage" },' \
  '    { "binding": "WORKER_SELF_REFERENCE", "service": "acme-issues-web-stage" },'
check "the environment URLs: worker name and subdomain" \
  "$acme" intent.yaml '    url: https://on-demand-isr-web-stage.your-workers-subdomain.workers.dev' \
  '    url: https://acme-issues-web-stage.acme.workers.dev'
check "the R2 root's terraform repo — every bucket name is built on it" \
  "$acme" infra/terraform/cloudflare-r2/terraform/main.tf '  default = "on-demand-isr"' \
  '  default = "acme-issues"'
check "the per-environment terraform repo parameter" \
  "$acme" intent.yaml '        repo: on-demand-isr' \
  '        repo: acme-issues'
check "a fixture's bucket name follows the same rule" \
  "$acme" apps/web/wiring.fixture.json '    "r2_bucket_name": "stg-on-demand-isr-stage"' \
  '    "r2_bucket_name": "stg-acme-issues-stage"'
check "the placeholder domain is the product's domain, not a renamed slug" \
  "$acme" intent.yaml '      BASE_DOMAIN: on-demand-isr.example.com' \
  '      BASE_DOMAIN: issues.acme.dev'
check "no domain given: the reserved placeholder, for an owner to replace later" \
  '{"reponame":"acme-issues","productname":"Acme Issues","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: on-demand-isr.example.com' \
  '      BASE_DOMAIN: acme-issues.example.com'
check "an empty domain is no domain" \
  '{"reponame":"acme-issues","productname":"Acme Issues","productdomain":""}' \
  intent.yaml '      BASE_DOMAIN: on-demand-isr.example.com' \
  '      BASE_DOMAIN: acme-issues.example.com'
check "the repo slug" \
  "$acme" package.json '  "name": "on-demand-isr",' \
  '  "name": "acme-issues",'
check "a wiring secret ref names the product's workspace and project" \
  "$acme" apps/web/component.yaml \
  '    WIRING_CLOUDFLARE_R2_STAGE: "secret://on-demand-isr/on-demand-isr/stage/WIRING_CLOUDFLARE_R2"' \
  '    WIRING_CLOUDFLARE_R2_STAGE: "secret://ws_79BDXAZQ/acme-issues/stage/WIRING_CLOUDFLARE_R2"'
check "the R2 root's templated token ref too" \
  "$acme" infra/terraform/cloudflare-r2/component.yaml \
  '    CLOUDFLARE_API_TOKEN: "secret://on-demand-isr/on-demand-isr/{{ .environment }}/CLOUDFLARE_R2_TOKEN"' \
  '    CLOUDFLARE_API_TOKEN: "secret://ws_79BDXAZQ/acme-issues/{{ .environment }}/CLOUDFLARE_R2_TOKEN"'
check "org-owned identity is not renamed" \
  "$acme" intent.yaml 'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai' \
  'apiVersion: sourceplane.io/v1 # mail ops@sourceplane.ai'
check "without githuborg the repository link keeps the baseline's owner" \
  '{"reponame":"acme-issues","productname":"Acme Issues","productdomain":"issues.acme.dev"}' \
  README.md 'https://github.com/sourceplane/on-demand-isr' \
  'https://github.com/sourceplane/acme-issues'
check "THE HAZARD: in prose the rename takes the slug for the slug" \
  "$acme" apps/web/README.md 'the on-demand-isr site' \
  'the acme-issues site'
check "GitHub's own words are not this identity: the App's settings are left alone" \
  "$acme" apps/web/lib/settings.ts \
  "export type Setting = 'GITHUB_APP_ID' | 'GITHUB_APP_PK_PEM' | 'GITHUB_WEBHOOK_SECRET';" \
  "export type Setting = 'GITHUB_APP_ID' | 'GITHUB_APP_PK_PEM' | 'GITHUB_WEBHOOK_SECRET';"
check "the template's upstream names are protected: its repository, its old home and its demo" \
  "$acme" README.md \
  'Ported from vercel/on-demand-isr (formerly nextjs/on-demand-isr; demo: https://on-demand-isr.vercel.app).' \
  'Ported from vercel/on-demand-isr (formerly nextjs/on-demand-isr; demo: https://on-demand-isr.vercel.app).'
check "…while the product's own repository on the same line is renamed" \
  "$acme" README.md \
  'Built from https://github.com/vercel/on-demand-isr into https://github.com/sourceplane/on-demand-isr.' \
  'Built from https://github.com/vercel/on-demand-isr into https://github.com/acme-inc/acme-issues.'

echo "── rebrand: a written value is not rewritten, in any later pass"
contains='{"reponame":"on-demand-isr-2","productname":"On-Demand Incremental Static Regeneration 2","productdomain":"on-demand-isr.example.com.au","githuborg":"sourceplane","subdomain":"your-workers-subdomain-2"}'
check "a repo slug containing the baseline's slug survives three passes" \
  "$contains" package.json '  "name": "on-demand-isr",' \
  '  "name": "on-demand-isr-2",' 3
check "a worker name built on it survives three passes" \
  "$contains" apps/web/component.yaml 'workerName: on-demand-isr-web' \
  'workerName: on-demand-isr-2-web' 3
check "a bucket name built on it survives three passes" \
  "$contains" apps/web/wiring.fixture.json '"r2_bucket_name": "prod-on-demand-isr-prod"' \
  '"r2_bucket_name": "prod-on-demand-isr-2-prod"' 3
check "a domain containing the baseline's domain survives three passes" \
  "$contains" intent.yaml 'BASE_DOMAIN: on-demand-isr.example.com' \
  'BASE_DOMAIN: on-demand-isr.example.com.au' 3
check "a subdomain containing the placeholder survives three passes" \
  "$contains" apps/web/component.yaml 'workersDevSubdomain: your-workers-subdomain' \
  'workersDevSubdomain: your-workers-subdomain-2' 3
check "a site name containing the baseline's name survives three passes" \
  "$contains" apps/web/app/site.ts 'export const SITE_NAME = "On-Demand Incremental Static Regeneration";' \
  'export const SITE_NAME = "On-Demand Incremental Static Regeneration 2";' 3
prefixed='{"reponame":"acme-on-demand-isr","productname":"Sam'"'"'s Tees & Mugs","productdomain":"issues.acme.dev","githuborg":"acme-inc","subdomain":"acme","orunWorkspace":"ws_79BDXAZQ"}'
check "a slug that ENDS in the baseline's slug survives three passes (the e2e fixture's)" \
  "$prefixed" apps/web/wrangler.jsonc '"service": "on-demand-isr-web-stage"' \
  '"service": "acme-on-demand-isr-web-stage"' 3
check "…and so does its bucket name" \
  "$prefixed" apps/web/wiring.fixture.json '"r2_bucket_name": "stg-on-demand-isr-stage"' \
  '"r2_bucket_name": "stg-acme-on-demand-isr-stage"' 3
check "…and, with no domain, its placeholder (which ends in the baseline's domain)" \
  '{"reponame":"acme-on-demand-isr","productname":"Sam'"'"'s Tees & Mugs","githuborg":"acme-inc","subdomain":"acme"}' \
  intent.yaml '      BASE_DOMAIN: on-demand-isr.example.com' \
  '      BASE_DOMAIN: acme-on-demand-isr.example.com' 3

# --verify runs in every phase. Without the product's values it cannot tell
# the product's own identity from a leftover; with them it can. A real
# leftover must fail it either way.
verify() { # NAME VALUES FILE CONTENT WANT(pass|fail) [--values]
  local name="$1" values="$2" file="$3" content="$4" want="$5" withvalues="${6:-}" tmp got
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  mkdir -p "$tmp/$(dirname "$file")" "$tmp/.rebrand"
  printf '%s\n' "$content" > "$tmp/$file"
  printf '%s\n' "$values" > "$tmp/.rebrand/values.json"
  git -C "$tmp" add -A
  if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --verify ${withvalues:+--values .rebrand/values.json} >/dev/null 2>&1); then got=pass; else got=fail; fi
  rm -rf "$tmp"
  if [ "$got" = "$want" ]; then echo "   ok  $name"; else echo "   ✕  $name: --verify ${got}ed, want $want" >&2; fail=1; fi
}
echo "── rebrand --verify: the product's own identity is not residue"
verify "given the values, a slug containing the baseline's passes" \
  "$contains" package.json '"name": "on-demand-isr-2"' pass --values
verify "without them it cannot know, and fails" \
  "$contains" package.json '"name": "on-demand-isr-2"' fail
verify "given the values, a real leftover still fails" \
  "$acme" package.json '"name": "on-demand-isr"' fail --values
verify "a leftover worker name fails" \
  "$acme" apps/web/wrangler.jsonc '"name": "on-demand-isr-web-stage",' fail --values
verify "a leftover bucket name fails" \
  "$acme" apps/web/wiring.fixture.json '"r2_bucket_name": "stg-on-demand-isr-stage"' fail --values
verify "THE HAZARD: the Pascal form anywhere fails (no rule renames it — so nothing may spell it)" \
  "$acme" apps/web/components/banner.tsx 'export function OnDemandIsrBanner() {}' fail --values
verify "a clean product passes" \
  "$acme" package.json '"name": "acme-issues"' pass --values
verify "a product whose own name carries the Pascal form passes, given the values" \
  '{"reponame":"acme-issues","productname":"OnDemandIsr Outlet","productdomain":"issues.acme.dev"}' \
  apps/web/app/site.ts 'export const SITE_NAME = "OnDemandIsr Outlet";' pass --values
verify "GitHub's own words are not residue" \
  "$acme" apps/web/lib/settings.ts "return Boolean(setting('GITHUB_APP_ID') && setting('GITHUB_APP_PK_PEM'));" pass --values
verify "the template's upstream names are not residue" \
  "$acme" README.md 'vercel/on-demand-isr, nextjs/on-demand-isr, https://on-demand-isr.vercel.app' pass --values
verify "…but the slug in plain prose still is" \
  "$acme" README.md 'the on-demand-isr site' fail --values

echo "── rebrand: a residue it cannot rename fails the rebrand itself"
tmp="$(mktemp -d)"; git -C "$tmp" init -q; mkdir -p "$tmp/.rebrand" "$tmp/apps/web"
printf '%s\n' "$acme" > "$tmp/.rebrand/values.json"
printf 'const x = "ON_DEMAND_ISR_TOKEN"\n' > "$tmp/apps/web/x.ts"
git -C "$tmp" add -A
if (cd "$tmp" && node "$rebrand" --baseline-identity "$identity" --values .rebrand/values.json --allow-dirty >/dev/null 2>&1); then
  echo "   ✕  an unrenamable env-var prefix passed the rebrand" >&2; fail=1
else
  echo "   ok  an unrenamable env-var prefix fails the rebrand, naming the file"
fi
rm -rf "$tmp"

[ "$fail" -eq 0 ] || exit 1
echo "rebrand.test.sh: ok"
