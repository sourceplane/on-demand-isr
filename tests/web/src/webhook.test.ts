import { createHmac } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// app/api/webhook, the template's door for GitHub's webhook: a delivery whose
// x-hub-signature-256 is the HMAC-SHA256 of its raw body under
// GITHUB_WEBHOOK_SECRET drops `/` and the issue's own page from the cache
// (revalidatePath); any other is refused (400) and drops nothing. With no
// secret configured the template keyed its HMAC with '' — anyone could sign
// — so here the door is shut (503) until the secret is set.

const { revalidatePath } = vi.hoisted(() => ({ revalidatePath: vi.fn() }));
vi.mock("next/cache", () => ({ revalidatePath }));

const SECRET = "the-webhook-secret";
const CONTEXT = Symbol.for("__cloudflare-context__");
const saved = process.env.GITHUB_WEBHOOK_SECRET;

beforeEach(() => {
  revalidatePath.mockReset();
  process.env.GITHUB_WEBHOOK_SECRET = SECRET;
});
afterEach(() => {
  if (saved === undefined) delete process.env.GITHUB_WEBHOOK_SECRET;
  else process.env.GITHUB_WEBHOOK_SECRET = saved;
  delete (globalThis as Record<symbol, unknown>)[CONTEXT];
});

const sign = (body: string, secret = SECRET) => `sha256=${createHmac("sha256", secret).update(body).digest("hex")}`;

async function deliver(body: string, signature?: string) {
  const { POST } = await import("@app/app/api/webhook/route");
  const headers = new Headers({ "content-type": "application/json", "x-github-event": "issues" });
  if (signature !== undefined) headers.set("x-hub-signature-256", signature);
  const res = await POST(new Request("https://on-demand-isr-web-stage.example.workers.dev/api/webhook", { method: "POST", headers, body }));
  return { status: res.status, text: await res.text() };
}

const opened = JSON.stringify({ action: "opened", issue: { number: 7, title: "New" } });

describe("POST /api/webhook", () => {
  it("revalidates / and the issue's page for a correctly signed delivery", async () => {
    expect(await deliver(opened, sign(opened))).toEqual({ status: 200, text: "Success!" });
    expect(revalidatePath.mock.calls).toEqual([["/"], ["/7"]]);
  });

  it("revalidates only / for a signed delivery that names no issue (GitHub's ping)", async () => {
    const ping = JSON.stringify({ zen: "Keep it logically awesome.", hook_id: 1 });
    expect((await deliver(ping, sign(ping))).status).toBe(200);
    expect(revalidatePath.mock.calls).toEqual([["/"]]);
  });

  it("refuses a delivery signed with another secret, and drops nothing", async () => {
    expect(await deliver(opened, sign(opened, "not-the-secret"))).toEqual({ status: 400, text: "Invalid signature." });
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("refuses a body changed after signing", async () => {
    const tampered = opened.replace('"number":7', '"number":8');
    expect((await deliver(tampered, sign(opened))).status).toBe(400);
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("refuses a missing or malformed signature", async () => {
    for (const signature of [undefined, "", "sha256=", "sha1=abc", sign(opened).slice(0, -2)]) {
      const { status } = await deliver(opened, signature);
      expect(status, String(signature)).toBe(400);
    }
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("refuses a signed body that is not JSON", async () => {
    expect((await deliver("not json", sign("not json"))).status).toBe(400);
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("is shut (503) while no secret is configured, whatever is sent — even an HMAC under ''", async () => {
    delete process.env.GITHUB_WEBHOOK_SECRET;
    for (const signature of [undefined, sign(opened, ""), sign(opened)]) {
      const { status, text } = await deliver(opened, signature);
      expect(status).toBe(503);
      expect(text).toMatch(/GITHUB_WEBHOOK_SECRET/);
    }
    expect(revalidatePath).not.toHaveBeenCalled();
  });

  it("reads the secret from the Worker's env during a request", async () => {
    delete process.env.GITHUB_WEBHOOK_SECRET;
    (globalThis as Record<symbol, unknown>)[CONTEXT] = { env: { GITHUB_WEBHOOK_SECRET: "worker-secret" }, ctx: {}, cf: {} };
    expect((await deliver(opened, sign(opened, "worker-secret"))).status).toBe(200);
    expect((await deliver(opened, sign(opened))).status).toBe(400);
  });
});

describe("GET /api/health", () => {
  it("answers ok, and whether the App is connected, uncached", async () => {
    const { GET } = await import("@app/app/api/health/route");
    const saved2 = { id: process.env.GITHUB_APP_ID, pk: process.env.GITHUB_APP_PK_PEM };
    try {
      delete process.env.GITHUB_APP_ID;
      delete process.env.GITHUB_APP_PK_PEM;
      let res = GET();
      expect(res.headers.get("cache-control")).toBe("no-store");
      expect(await res.json()).toEqual({ ok: true, connected: false });
      process.env.GITHUB_APP_ID = "1";
      process.env.GITHUB_APP_PK_PEM = "pem";
      res = GET();
      expect(await res.json()).toEqual({ ok: true, connected: true });
    } finally {
      if (saved2.id === undefined) delete process.env.GITHUB_APP_ID;
      else process.env.GITHUB_APP_ID = saved2.id;
      if (saved2.pk === undefined) delete process.env.GITHUB_APP_PK_PEM;
      else process.env.GITHUB_APP_PK_PEM = saved2.pk;
    }
  });
});
