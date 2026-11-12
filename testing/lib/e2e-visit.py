#!/usr/bin/env python3
"""What a visitor (and GitHub) does to the served Worker — testing/e2e.test.sh's stages 3 and 4.

    e2e-visit.py born      <url> <values.json>
    e2e-visit.py connected <url> <values.json>    (E2E_GITHUB, E2E_WEBHOOK_SECRET)

`born` is a fresh product with no GitHub App: `/` lists the sample issues
under the product's name and the notice that says how to connect an App,
on the product's own repository; each sample issue's page renders its
Markdown, code highlighted; a missing issue is the 404 page; `/api/health`
says not connected; the webhook is shut (503), whatever is sent.

`connected` is the same product with the App's three settings as Worker
secrets and api.github.com answered by the stand-in (testing/lib/fake-github.mjs,
which checks the App's RS256 JWT with its public key): `/` lists the
repository's issues and is then served from the cache (the stand-in is not
called again); a new issue upstream does not show; a forged, unsigned or
tampered webhook is refused and drops nothing; a signed `issues` delivery
drops `/` and the issue's page, so the next visit renders them again — the
new issue listed and its page served — and the one after is cached again.
"""
import hashlib
import hmac
import html
import json
import os
import re
import sys
import urllib.error
import urllib.request

mode, base, values = sys.argv[1], sys.argv[2], json.load(open(sys.argv[3]))
name = values["productname"]
repo = values["reponame"]
org = values.get("githuborg") or "sourceplane"
repository = f"{org}/{repo}"
source = f"https://github.com/{repository}"
# The baseline's own site name: residue in a product named anything else.
BASELINE_NAME = "On-Demand Incremental Static Regeneration"
renamed = name != BASELINE_NAME
problems = []


def bad(m):
    problems.append(m)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


opener = urllib.request.build_opener(NoRedirect)


def request(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=dict(headers or {}), method=method)
    try:
        r = opener.open(req, timeout=90)
    except urllib.error.HTTPError as e:
        r = e
    return r.status, r.headers, r.read()


def get(path):
    s, h, b = request(base + path)
    return s, h, b.decode("utf-8", "replace")


def text(page):
    """The page's words: React's <!-- --> separators and tags dropped, entities decoded."""
    page = page.replace("<!-- -->", "")
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", page)))


def title_of(page):
    m = re.search(r"<title>(.*?)</title>", page, re.S)
    return html.unescape(m.group(1)) if m else None


def webhook(body, signature=None, event="issues"):
    headers = {"content-type": "application/json", "x-github-event": event}
    if signature is not None:
        headers["x-hub-signature-256"] = signature
    s, _, b = request(base + "/api/webhook", data=body.encode(), headers=headers, method="POST")
    return s, b.decode("utf-8", "replace")


def sign(body, secret):
    return "sha256=" + hmac.new(secret.encode(), body.encode(), hashlib.sha256).hexdigest()


def done(summary):
    if problems:
        for p in problems:
            print(f"  ✕ {p}", file=sys.stderr)
        sys.exit(1)
    print(f"   {summary}")


def frame(page, where):
    """What every page carries: the product's name as its title, its own repository."""
    if title_of(page) != name:
        bad(f"{where}: the title is {title_of(page)!r}, not the product's name {name!r}")
    if renamed and BASELINE_NAME in text(page):
        bad(f"{where}: still names the baseline's site {BASELINE_NAME!r}")
    if f'href="{source}"' not in page:
        bad(f"{where}: no link to the product's own repository {source}")
    if re.search(r"github\.com/nextjs|nextjs/on-demand-isr", page):
        bad(f"{where}: still links the template's repository")


SAMPLE_TITLES = ["Connect a GitHub App to list this repository’s issues",
                 "How a webhook regenerates this page", "Pages are served from the cache"]

if mode == "born":
    s, h, page = get("/")
    if s != 200:
        bad(f"/ answered {s}")
    frame(page, "/")
    t = text(page)
    for title in SAMPLE_TITLES:
        if title not in t:
            bad(f"/ does not list the sample issue {title!r}")
    if 'data-notice="connect-github-app"' not in page or f"to list the issues of {repository} here" not in t:
        bad("/ does not say how to connect a GitHub App, on the product's repository")
    if f'href="{source}#connecting-a-github-app"' not in page:
        bad("/'s notice does not link the README's 'Connecting a GitHub App'")
    for n in (1, 2, 3):
        s, _, issue = get(f"/{n}")
        if s != 200:
            bad(f"/{n} (a sample issue) answered {s}")
            continue
        frame(issue, f"/{n}")
        if 'data-notice="connect-github-app"' not in issue:
            bad(f"/{n} does not carry the connect notice")
    s, _, issue = get("/2")
    if not re.search(r'<code class="hljs language-ts">.*?<span class="hljs-', issue, re.S):
        bad("/2's code block is not highlighted (marked + highlight.js on the Worker)")
    s, _, _ = get("/404040")
    if s != 404:
        bad(f"a missing issue answered {s}, not 404")
    s, h, health = get("/api/health")
    if s != 200 or json.loads(health or "{}") != {"ok": True, "connected": False}:
        bad(f"/api/health answered {s} {health!r}, not ok and not connected")
    body = json.dumps({"action": "opened", "issue": {"number": 1}})
    for sig in (None, sign(body, ""), sign(body, "a-guess")):
        s, b = webhook(body, sig)
        if s != 503 or "GITHUB_WEBHOOK_SECRET" not in b:
            bad(f"with no secret configured the webhook answered {s} {b[:60]!r} to signature {sig and sig[:14]}, not 503")
    s, _, _ = get("/_next/static/does-not-exist.js")
    if s != 404:
        bad(f"a missing static file answered {s}, not 404")
    done("sample issues listed under the connect notice, on the product's repository; issue pages highlighted; "
         "404 for a missing issue; /api/health not connected; the webhook shut (503) with no secret")

elif mode == "connected":
    gh = os.environ["E2E_GITHUB"]
    secret = os.environ["E2E_WEBHOOK_SECRET"]

    def calls():
        s, _, b = request(gh + "/__calls")
        return json.loads(b)

    def reads(c, path):
        return sum(1 for x in c if x["path"] == path and x["auth"] == "token")

    issues_path = f"/repos/{repository}/issues"
    s, h, page = get("/")
    if s != 200:
        bad(f"/ answered {s}")
    frame(page, "/ (connected)")
    t = text(page)
    if "First issue, from the stand-in" not in t:
        bad("/ does not list the repository's issue from GitHub")
    if "data-notice" in page:
        bad("/ still shows the connect notice with an App connected")
    for title in SAMPLE_TITLES:
        if title in t:
            bad(f"/ still lists the sample issue {title!r}")
    if "1,234" not in t:
        bad("/ does not show the repository's stars")
    c1 = calls()
    if not any(x["path"] == "/app/installations" and x["auth"] == "jwt-ok" for x in c1):
        bad("the Worker never authenticated as the App with a valid RS256 JWT")
    if any(x["auth"] == "jwt-bad" for x in c1):
        bad("the stand-in refused a JWT the Worker signed")
    if reads(c1, issues_path) < 1:
        bad("the Worker never read the repository's issues with the installation token")
    if any(not x["path"].startswith((f"/repos/{repository}", "/app/")) for x in c1):
        bad(f"the Worker read beyond the product's repository: {sorted({x['path'] for x in c1})}")

    # Served from the cache: GitHub is not asked again.
    s, h, again = get("/")
    if (h.get("x-nextjs-cache") or "").upper() != "HIT":
        bad(f"the second visit to / was {h.get('x-nextjs-cache')!r}, not a cache HIT")
    if reads(calls(), issues_path) != reads(c1, issues_path):
        bad("the second visit to / read GitHub again")

    # A new issue upstream does not show until the webhook says so.
    request(gh + "/__issue", data=json.dumps({"number": 2, "title": "Second issue, opened later",
                                               "body": "Opened **after** the page was cached."}).encode(),
            headers={"content-type": "application/json"}, method="POST")
    s, h, stale = get("/")
    if "Second issue, opened later" in text(stale):
        bad("a new issue showed before any webhook (the page was not served from the cache)")
    before = reads(calls(), issues_path)

    body = json.dumps({"action": "opened", "issue": {"number": 2, "title": "Second issue, opened later"}})
    for label, sig, payload in (("unsigned", None, body),
                                ("signed with another secret", sign(body, "not-the-secret"), body),
                                ("tampered after signing", sign(body, secret), body.replace('"number": 2', '"number": 3')),
                                ("truncated signature", sign(body, secret)[:-4], body)):
        s, b = webhook(payload, sig)
        if s != 400:
            bad(f"a {label} delivery answered {s} {b[:60]!r}, not 400")
    s, h, still = get("/")
    if "Second issue, opened later" in text(still) or reads(calls(), issues_path) != before:
        bad("a refused delivery regenerated the page")

    s, b = webhook(body, sign(body, secret))
    if s != 200 or b != "Success!":
        bad(f"a signed delivery answered {s} {b[:60]!r}, not 200 Success!")
    s, h, fresh = get("/")
    if "Second issue, opened later" not in text(fresh):
        bad("after a signed delivery, / does not list the new issue")
    if (h.get("x-nextjs-cache") or "").upper() == "HIT":
        bad("the visit after a signed delivery was still a cache HIT")
    if reads(calls(), issues_path) <= before:
        bad("the regenerated / did not read GitHub")
    s, h, cached = get("/")
    if (h.get("x-nextjs-cache") or "").upper() != "HIT":
        bad(f"the visit after the regeneration was {h.get('x-nextjs-cache')!r}, not cached again")
    s, _, issue2 = get("/2")
    if s != 200 or "Opened after the page was cached." not in text(issue2):
        bad(f"/2 answered {s} without the new issue's body")
    frame(issue2, "/2 (connected)")
    s, _, health = get("/api/health")
    if json.loads(health or "{}") != {"ok": True, "connected": True}:
        bad(f"/api/health says {health!r}, not connected")
    done("the repository's issues listed (the App's RS256 JWT verified), served from the R2 cache; a new issue hidden "
         "until a signed webhook — forged, unsigned, tampered and truncated ones refused — then regenerated and cached again")
else:
    sys.exit(f"unknown mode {mode}")
