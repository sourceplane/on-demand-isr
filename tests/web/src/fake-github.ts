import { generateKeyPairSync, verify } from "node:crypto";

// An in-process stand-in for the slice of api.github.com the app calls, as a
// `fetch`: the App's installations and an installation token (both behind a
// JWT it verifies with the App's public key), then a repository, its issues,
// one issue and its comments (behind that token). It records every call.

// A private key in the format GitHub issues App keys in (PKCS#1, "BEGIN RSA
// PRIVATE KEY"), and its public half for checking signatures.
export const KEYS = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  privateKeyEncoding: { type: "pkcs1", format: "pem" },
  publicKeyEncoding: { type: "spki", format: "pem" },
});
export const APP_ID = "12345";
export const TOKEN = "ghs_installation_token";

export interface Call {
  method: string;
  path: string;
  authorization: string;
}

export interface Issue {
  id: number;
  number: number;
  title: string;
  comments: number;
  created_at: string;
  html_url: string;
  body: string;
  user: { login: string; avatar_url?: string };
}

export function issue(number: number, title: string, body = ""): Issue {
  return {
    id: 1000 + number,
    number,
    title,
    comments: 0,
    created_at: "2026-11-01T10:00:00Z",
    html_url: `https://github.com/acme/issues/issues/${number}`,
    body,
    user: { login: "octocat", avatar_url: "https://avatars.githubusercontent.com/u/583231" },
  };
}

// The JWT's three parts, checked: RS256, signed by KEYS.privateKey.
export function readJwt(authorization: string) {
  const m = /^Bearer ([^.]+)\.([^.]+)\.([^.]+)$/.exec(authorization);
  if (!m) return null;
  const [, h, p, s] = m as unknown as [string, string, string, string];
  const header = JSON.parse(Buffer.from(h, "base64url").toString());
  const payload = JSON.parse(Buffer.from(p, "base64url").toString());
  const valid = verify("RSA-SHA256", Buffer.from(`${h}.${p}`), KEYS.publicKey, Buffer.from(s, "base64url"));
  return { header, payload, valid };
}

export function fakeGitHub(opts: {
  owner: string;
  repository: string;
  installations?: { id: number; account: { login: string } }[];
  issues?: Issue[];
  comments?: Record<number, { id: number; html_url: string; created_at: string; body: string; user: { login: string } }[]>;
  stars?: number;
  forks?: number;
}) {
  const calls: Call[] = [];
  const installations = opts.installations ?? [{ id: 42, account: { login: opts.owner } }];
  const state = { issues: opts.issues ?? [], comments: opts.comments ?? {} };
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

  const fetch = async (input: string | URL | Request, init?: RequestInit) => {
    const request = new Request(input, init);
    const url = new URL(request.url);
    const authorization = request.headers.get("authorization") ?? "";
    calls.push({ method: request.method, path: url.pathname, authorization });
    if (url.origin !== "https://api.github.com") return json({ message: "not GitHub" }, 599);

    const jwtOk = () => {
      const jwt = readJwt(authorization);
      return Boolean(jwt?.valid && jwt.header.alg === "RS256" && String(jwt.payload.iss) === APP_ID);
    };
    if (url.pathname === "/app/installations") {
      return jwtOk() ? json(installations) : json({ message: "A JSON web token could not be decoded" }, 401);
    }
    const token = /^\/app\/installations\/(\d+)\/access_tokens$/.exec(url.pathname);
    if (token && request.method === "POST") {
      return jwtOk() && installations.some((i) => String(i.id) === token[1])
        ? json({ token: TOKEN }, 201)
        : json({ message: "Bad credentials" }, 401);
    }
    if (authorization !== `Bearer ${TOKEN}`) return json({ message: "Bad credentials" }, 401);

    const base = `/repos/${opts.repository}`;
    if (url.pathname === base) {
      return json({ full_name: opts.repository, stargazers_count: opts.stars ?? 0, forks_count: opts.forks ?? 0 });
    }
    if (url.pathname === `${base}/issues`) return json(state.issues);
    const one = new RegExp(`^${base}/issues/(\\d+)(/comments)?$`).exec(url.pathname);
    if (one) {
      const found = state.issues.find((i) => String(i.number) === one[1]);
      if (!found) return json({ message: "Not Found" }, 404);
      return json(one[2] ? (state.comments[found.number] ?? []) : found);
    }
    return json({ message: "Not Found" }, 404);
  };
  return { fetch, calls, state };
}
