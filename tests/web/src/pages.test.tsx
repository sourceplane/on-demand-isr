import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { renderToString } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { OWNER, REPO, REPOSITORY, SITE_NAME, SOURCE_URL } from "@app/app/site";
import { SAMPLE_ISSUES } from "@app/lib/sample";
import { APP_ID, KEYS, fakeGitHub, issue } from "./fake-github";

// The template's pages, rendered as the Worker renders them: `/` lists the
// repository's issues under the template's explanation, `/[id]` shows one
// with its comments as highlighted Markdown. Before an App is connected both
// render the sample issues under a notice that says how to connect one.

// next/image needs the build's image config; the pages' avatars render as a
// plain <img> here.
vi.mock("next/image", () => ({
  default: ({ src, alt }: { src: string | { src: string }; alt: string }) => (
    <img src={typeof src === "string" ? src : src.src} alt={alt} />
  ),
}));

const ENV = ["GITHUB_APP_ID", "GITHUB_APP_PK_PEM"] as const;
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
  vi.unstubAllGlobals();
});

// The text of the rendered HTML, entities decoded and React's <!-- --> text
// separators removed, for comparing words.
const text = (html: string) =>
  html
    .replace(/<!-- -->/g, "")
    .replace(/<[^>]+>/g, " ")
    .replace(/&#x27;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/\s+/g, " ");

async function home() {
  const { default: Page } = await import("@app/app/page");
  return renderToString(await Page());
}
async function issuePage(id: string) {
  const { default: IssuePage } = await import("@app/app/[id]/page");
  const { default: IssueLayout } = await import("@app/app/[id]/layout");
  const params = Promise.resolve({ id });
  return renderToString(await IssueLayout({ params, children: await IssuePage({ params }) }));
}

describe("unconnected", () => {
  it("/ lists the sample issues under the connect notice, on this site's repository", async () => {
    vi.stubGlobal("fetch", vi.fn());
    const html = await home();
    const t = text(html);
    for (const sample of SAMPLE_ISSUES) expect(t).toContain(sample.title);
    expect(html).toContain('data-notice="connect-github-app"');
    expect(t).toContain(`to list the issues of ${REPOSITORY} here`);
    expect(html).toContain(`href="${SOURCE_URL}#connecting-a-github-app"`);
    expect(t).toContain(`${OWNER} / ${REPO}`);
    expect(html).toContain(`href="${SOURCE_URL}/fork"`);
    for (const sample of SAMPLE_ISSUES) expect(html).toContain(`href="/${sample.number}"`);
  });

  it("/[id] renders a sample issue's Markdown, code highlighted, with its comment", async () => {
    vi.stubGlobal("fetch", vi.fn());
    const html = await issuePage("2");
    expect(html).toContain('data-notice="connect-github-app"');
    expect(html).toMatch(/<code class="hljs language-ts">[\s\S]*<span class="hljs-/);
    expect(text(html)).toContain("Try it once the App is connected");
    expect(html).toContain(`href="${SOURCE_URL}/issues/2"`);
  });
});

describe("connected", () => {
  function connect(issues = [issue(2, "Second & last", "Fixed in `main`"), issue(1, "First")]) {
    process.env.GITHUB_APP_ID = APP_ID;
    process.env.GITHUB_APP_PK_PEM = KEYS.privateKey;
    const gh = fakeGitHub({
      owner: OWNER,
      repository: REPOSITORY,
      issues,
      stars: 1234,
      forks: 56,
      comments: {
        2: [
          { id: 1, html_url: "", created_at: "2026-11-02T00:00:00Z", body: "Looks **good**", user: { login: "octocat" } },
          { id: 2, html_url: "", created_at: "2026-11-02T00:00:00Z", body: "Deployed", user: { login: "vercel[bot]" } },
        ],
      },
    });
    vi.stubGlobal("fetch", gh.fetch);
    return gh;
  }

  it("/ lists the repository's issues, its stars and forks, and no notice", async () => {
    connect();
    const html = await home();
    const t = text(html);
    expect(t).toContain("Second & last");
    expect(t).toContain("#2 opened by octocat");
    expect(t).toContain("1,234");
    expect(t).toContain("56");
    expect(html).not.toContain("data-notice");
    for (const sample of SAMPLE_ISSUES) expect(t).not.toContain(sample.title);
  });

  it("/[id] renders the issue and its comments, leaving out bots' (as the template does)", async () => {
    connect();
    const html = await issuePage("2");
    const t = text(html);
    expect(t).toContain("Fixed in main");
    expect(html).toContain("<strong>good</strong>");
    expect(t).not.toContain("Deployed");
    expect(html).toContain('src="https://avatars.githubusercontent.com/u/583231"');
    expect(html).not.toContain("data-notice");
  });
});

describe("the template's frame", () => {
  it("titles the page with the site's name", async () => {
    const { metadata } = await import("@app/app/layout");
    expect(metadata.title).toBe(SITE_NAME);
  });

  it("explains on-demand ISR on this site's repository, with no Vercel hosting claims", async () => {
    const { default: Explanation } = await import("@app/app/explanation");
    const html = renderToString(<Explanation />);
    expect(html).toContain(`href="${SOURCE_URL}"`);
    expect(html).toContain(`href="${SOURCE_URL}/issues/new"`);
    expect(text(html)).toContain(`${REPO} ` + "` repo change");
    expect(html).not.toMatch(/Vercel|Serverless Function/);
    expect(html).toContain("revalidatePath()");
  });

  it("keeps the template's stylesheet, compiled with sass", () => {
    const scss = readFileSync(resolve(__dirname, "../../../apps/web/styles/Home.module.scss"), "utf8");
    expect(scss).toContain(".issue_title");
  });
});
