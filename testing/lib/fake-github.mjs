#!/usr/bin/env node
// THE E2E'S STAND-IN FOR api.github.com — the slice the site calls, offline.
//
//   node fake-github.mjs --port N --public-key FILE --app-id ID --repository OWNER/NAME
//
// /app/installations and /app/installations/42/access_tokens answer only a
// JWT that VERIFIES: RS256, signed by the private key whose public half is
// --public-key, issued (`iss`) by --app-id, not expired — the App's own
// authentication, checked the way GitHub checks it. Everything under
// /repos/OWNER/NAME answers only the installation token that mints. One
// issue to begin with; `POST /__issue {number,title,body}` opens another (a
// change upstream the site must not show until the webhook says so), and
// `GET /__calls` lists every call with how it authenticated: jwt-ok,
// jwt-bad, token, or none.
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i < 0 || !process.argv[i + 1]) throw new Error(`fake-github: --${name} is required`);
  return process.argv[i + 1];
}
const port = Number(arg("port"));
const publicKey = fs.readFileSync(arg("public-key"), "utf8");
const appId = arg("app-id");
const repository = arg("repository");
const owner = repository.split("/")[0];
const TOKEN = "ghs_e2e_installation_token";
const calls = [];
const issues = [
  {
    id: 1001,
    number: 1,
    title: "First issue, from the stand-in",
    comments: 0,
    created_at: "2026-11-01T10:00:00Z",
    html_url: `https://github.com/${repository}/issues/1`,
    body: "Read through the App's installation token.\n\n```js\nconsole.log('cached');\n```",
    user: { login: "octocat" },
  },
];

function jwtState(authorization) {
  const m = /^Bearer ([^.]+)\.([^.]+)\.([^.]+)$/.exec(authorization || "");
  if (!m) return "none";
  try {
    const header = JSON.parse(Buffer.from(m[1], "base64url").toString());
    const payload = JSON.parse(Buffer.from(m[2], "base64url").toString());
    const signed = crypto.verify("RSA-SHA256", Buffer.from(`${m[1]}.${m[2]}`), publicKey, Buffer.from(m[3], "base64url"));
    const now = Math.floor(Date.now() / 1000);
    const ok = header.alg === "RS256" && signed && String(payload.iss) === appId && payload.exp > now && payload.iat <= now;
    return ok ? "jwt-ok" : "jwt-bad";
  } catch {
    return "jwt-bad";
  }
}

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

http
  .createServer((req, res) => {
    let raw = "";
    req.on("data", (c) => (raw += c));
    req.on("end", () => {
      const path = new URL(req.url, "http://stand-in").pathname;
      if (path === "/__calls") return send(res, 200, calls);
      if (path === "/__issue" && req.method === "POST") {
        const { number, title, body } = JSON.parse(raw);
        issues.unshift({
          id: 1000 + number, number, title, body, comments: 0,
          created_at: new Date().toISOString(), html_url: `https://github.com/${repository}/issues/${number}`,
          user: { login: "hubot" },
        });
        return send(res, 200, { ok: true });
      }
      const authorization = req.headers.authorization || "";
      const auth = authorization === `Bearer ${TOKEN}` ? "token" : jwtState(authorization);
      calls.push({ method: req.method, path, auth });

      if (path === "/app/installations") {
        return auth === "jwt-ok"
          ? send(res, 200, [{ id: 7, account: { login: "someone-else" } }, { id: 42, account: { login: owner } }])
          : send(res, 401, { message: "A JSON web token could not be decoded" });
      }
      if (path === "/app/installations/42/access_tokens" && req.method === "POST") {
        return auth === "jwt-ok" ? send(res, 201, { token: TOKEN }) : send(res, 401, { message: "Bad credentials" });
      }
      if (auth !== "token") return send(res, 401, { message: "Bad credentials" });
      const base = `/repos/${repository}`;
      if (path === base) return send(res, 200, { full_name: repository, stargazers_count: 1234, forks_count: 56 });
      if (path === `${base}/issues`) return send(res, 200, issues);
      const m = new RegExp(`^${base}/issues/(\\d+)(/comments)?$`).exec(path);
      if (m) {
        const issue = issues.find((i) => String(i.number) === m[1]);
        if (!issue) return send(res, 404, { message: "Not Found" });
        return send(res, 200, m[2] ? [] : issue);
      }
      return send(res, 404, { message: "Not Found" });
    });
  })
  .listen(port, "127.0.0.1", () => console.log(`fake-github: ${repository} on 127.0.0.1:${port}`));
