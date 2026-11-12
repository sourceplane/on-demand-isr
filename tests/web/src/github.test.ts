import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { OWNER, REPOSITORY } from "@app/app/site";
import { SAMPLE_COMMENTS, SAMPLE_ISSUES } from "@app/lib/sample";
import { APP_ID, KEYS, TOKEN, fakeGitHub, issue, readJwt } from "./fake-github";

// lib/github.ts, the template's GitHub App client, on this site's repository:
// it signs the App's JWT (RS256, with the PKCS#1 key GitHub issues), finds
// the installation of the repository's owner, takes an installation token
// (refreshed when GitHub answers 401) and reads the repository's issues.
// Without the App's settings it calls GitHub for nothing and answers the
// sample issues.

const ENV = ["GITHUB_APP_ID", "GITHUB_APP_PK_PEM", "GITHUB_WEBHOOK_SECRET"] as const;
const saved: Record<string, string | undefined> = {};
beforeEach(() => {
  for (const k of ENV) {
    saved[k] = process.env[k];
    delete process.env[k];
  }
  vi.resetModules(); // lib/github keeps its installation token in module scope
});
afterEach(() => {
  for (const k of ENV) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  vi.unstubAllGlobals();
});

function connect() {
  process.env.GITHUB_APP_ID = APP_ID;
  process.env.GITHUB_APP_PK_PEM = KEYS.privateKey;
}
const github = () => import("@app/lib/github");
// next/navigation's notFound() throws an error Next turns into the 404 page.
const isNotFound = (e: unknown) => String((e as { digest?: string }).digest ?? "").includes("404");

describe("unconnected (no App ID or no private key)", () => {
  it("answers the sample issues and calls GitHub for nothing", async () => {
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    const { fetchIssueAndRepoData } = await github();
    const data = await fetchIssueAndRepoData();
    expect(data.connected).toBe(false);
    expect(data.issues).toEqual(SAMPLE_ISSUES);
    expect(data.stargazers_count).toBe(0);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("answers each sample issue's page, and the 404 page for any other", async () => {
    vi.stubGlobal("fetch", vi.fn());
    const { fetchIssuePageData } = await github();
    for (const sample of SAMPLE_ISSUES) {
      const page = await fetchIssuePageData(String(sample.number));
      expect(page.connected).toBe(false);
      expect(page.issue).toEqual(sample);
      expect(page.comments).toEqual(SAMPLE_COMMENTS[sample.number] ?? []);
    }
    await expect(fetchIssuePageData("999")).rejects.toSatisfy(isNotFound);
  });

  it("is still unconnected with only one of the two settings", async () => {
    process.env.GITHUB_APP_ID = APP_ID;
    const fetch = vi.fn();
    vi.stubGlobal("fetch", fetch);
    const { fetchIssueAndRepoData } = await github();
    expect((await fetchIssueAndRepoData()).connected).toBe(false);
    expect(fetch).not.toHaveBeenCalled();
  });
});

describe("the GitHub App's JWT and installation token", () => {
  it("signs an RS256 JWT with the App's PKCS#1 key, issued by the App ID, valid for ten minutes", async () => {
    connect();
    const gh = fakeGitHub({ owner: OWNER, repository: REPOSITORY });
    vi.stubGlobal("fetch", gh.fetch);
    const { setAccessToken } = await github();
    const before = Math.floor(Date.now() / 1000);
    expect(await setAccessToken()).toBe(TOKEN);
    const call = gh.calls.find((c) => c.path === "/app/installations");
    const jwt = readJwt(call!.authorization)!;
    expect(jwt.valid).toBe(true);
    expect(jwt.header.alg).toBe("RS256");
    expect(String(jwt.payload.iss)).toBe(APP_ID);
    expect(jwt.payload.iat).toBeGreaterThanOrEqual(before - 61);
    expect(jwt.payload.iat).toBeLessThanOrEqual(before - 59);
    expect(jwt.payload.exp - jwt.payload.iat).toBe(660);
  });

  it("takes the token of the installation on the repository's owner, whatever its case", async () => {
    connect();
    const gh = fakeGitHub({
      owner: OWNER,
      repository: REPOSITORY,
      installations: [
        { id: 7, account: { login: "someone-else" } },
        { id: 42, account: { login: OWNER.toUpperCase() } },
      ],
    });
    vi.stubGlobal("fetch", gh.fetch);
    const { setAccessToken } = await github();
    expect(await setAccessToken()).toBe(TOKEN);
    expect(gh.calls.map((c) => `${c.method} ${c.path}`)).toEqual([
      "GET /app/installations",
      "POST /app/installations/42/access_tokens",
    ]);
  });

  it("says plainly when the App is not installed on the repository's owner", async () => {
    connect();
    const gh = fakeGitHub({ owner: OWNER, repository: REPOSITORY, installations: [{ id: 7, account: { login: "someone-else" } }] });
    vi.stubGlobal("fetch", gh.fetch);
    const { setAccessToken } = await github();
    await expect(setAccessToken()).rejects.toThrow(new RegExp(`no installation for ${OWNER}.*${REPOSITORY}`));
  });

  it("refuses to sign without the App's settings", async () => {
    vi.stubGlobal("fetch", fakeGitHub({ owner: OWNER, repository: REPOSITORY }).fetch);
    const { setAccessToken } = await github();
    await expect(setAccessToken()).rejects.toThrow(/GITHUB_APP_ID and GITHUB_APP_PK_PEM must be set/);
  });
});

describe("connected: the repository's issues", () => {
  it("lists the repository's issues and counts, refreshing the token on GitHub's 401", async () => {
    connect();
    const gh = fakeGitHub({
      owner: OWNER,
      repository: REPOSITORY,
      issues: [issue(2, "Second"), issue(1, "First")],
      stars: 1234,
      forks: 56,
    });
    vi.stubGlobal("fetch", gh.fetch);
    const { fetchIssueAndRepoData } = await github();
    const data = await fetchIssueAndRepoData();
    expect(data.connected).toBe(true);
    expect(data.issues.map((i: { title: string }) => i.title)).toEqual(["Second", "First"]);
    expect(data.stargazers_count).toBe(1234);
    expect(data.forks_count).toBe(56);
    // The template's first reads carry no token yet: GitHub answers 401, the
    // client signs in as the App and retries with the installation token.
    expect(gh.calls.filter((c) => c.path === `/repos/${REPOSITORY}/issues`).map((c) => c.authorization)).toEqual([
      "Bearer undefined",
      `Bearer ${TOKEN}`,
    ]);
    // …and keeps that token for the next read.
    const before = gh.calls.length;
    await fetchIssueAndRepoData();
    expect(gh.calls.slice(before).every((c) => c.authorization === `Bearer ${TOKEN}`)).toBe(true);
  });

  it("reads one issue with its comments, and a missing one is the 404 page", async () => {
    connect();
    const gh = fakeGitHub({
      owner: OWNER,
      repository: REPOSITORY,
      issues: [issue(3, "Third", "Body")],
      comments: { 3: [{ id: 9, html_url: "", created_at: "2026-11-02T00:00:00Z", body: "A comment", user: { login: "hubot" } }] },
    });
    vi.stubGlobal("fetch", gh.fetch);
    const { fetchIssuePageData } = await github();
    const page = await fetchIssuePageData("3");
    expect(page.connected).toBe(true);
    expect(page.issue.title).toBe("Third");
    expect(page.comments.map((c: { body: string }) => c.body)).toEqual(["A comment"]);
    await expect(fetchIssuePageData("4")).rejects.toSatisfy(isNotFound);
  });

  it("reads only this site's repository", async () => {
    connect();
    const gh = fakeGitHub({ owner: OWNER, repository: REPOSITORY, issues: [issue(1, "One")] });
    vi.stubGlobal("fetch", gh.fetch);
    const { fetchIssueAndRepoData, fetchIssuePageData } = await github();
    await fetchIssueAndRepoData();
    await fetchIssuePageData("1");
    const repos = gh.calls.map((c) => c.path).filter((p) => p.startsWith("/repos/"));
    expect(repos.length).toBeGreaterThan(0);
    for (const p of repos) expect(p.startsWith(`/repos/${REPOSITORY}`)).toBe(true);
  });
});
