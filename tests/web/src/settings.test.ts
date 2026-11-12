import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// lib/settings.ts: the GitHub App's three settings are read on every call,
// from the Worker's env while a request is being served and from the process
// otherwise (next build, next dev, these tests); the App counts as connected
// only with both its ID and its private key.

const ENV = ["GITHUB_APP_ID", "GITHUB_APP_PK_PEM", "GITHUB_WEBHOOK_SECRET"] as const;
// Where @opennextjs/cloudflare's getCloudflareContext() finds the Worker's
// context while a request is being served.
const CONTEXT = Symbol.for("__cloudflare-context__");
const saved: Record<string, string | undefined> = {};

beforeEach(() => {
  for (const k of ENV) {
    saved[k] = process.env[k];
    delete process.env[k];
  }
  vi.resetModules();
});
afterEach(() => {
  for (const k of ENV) {
    if (saved[k] === undefined) delete process.env[k];
    else process.env[k] = saved[k];
  }
  delete (globalThis as Record<symbol, unknown>)[CONTEXT];
});

const settings = () => import("@app/lib/settings");

describe("setting()", () => {
  it("is empty when nothing is set", async () => {
    const { setting, isConnected } = await settings();
    for (const k of ENV) expect(setting(k)).toBe("");
    expect(isConnected()).toBe(false);
  });

  it("reads the process outside a Worker request", async () => {
    process.env.GITHUB_WEBHOOK_SECRET = "from-process";
    const { setting } = await settings();
    expect(setting("GITHUB_WEBHOOK_SECRET")).toBe("from-process");
  });

  it("prefers the Worker's env during a request, read on every call", async () => {
    process.env.GITHUB_APP_ID = "from-process";
    const { setting } = await settings();
    const env: Record<string, string> = { GITHUB_APP_ID: "from-worker" };
    (globalThis as Record<symbol, unknown>)[CONTEXT] = { env, ctx: {}, cf: {} };
    expect(setting("GITHUB_APP_ID")).toBe("from-worker");
    env.GITHUB_APP_ID = "rotated";
    expect(setting("GITHUB_APP_ID")).toBe("rotated");
    delete env.GITHUB_APP_ID;
    expect(setting("GITHUB_APP_ID")).toBe("from-process");
  });
});

describe("isConnected()", () => {
  it("needs both the App ID and its private key", async () => {
    const { isConnected } = await settings();
    process.env.GITHUB_APP_ID = "12345";
    expect(isConnected()).toBe(false);
    process.env.GITHUB_APP_PK_PEM = "-----BEGIN RSA PRIVATE KEY-----";
    expect(isConnected()).toBe(true);
    delete process.env.GITHUB_APP_ID;
    expect(isConnected()).toBe(false);
  });

  it("does not need the webhook secret (reading is not revalidating)", async () => {
    const { isConnected } = await settings();
    process.env.GITHUB_APP_ID = "12345";
    process.env.GITHUB_APP_PK_PEM = "-----BEGIN RSA PRIVATE KEY-----";
    expect(isConnected()).toBe(true);
  });
});
