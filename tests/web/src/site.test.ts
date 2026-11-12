import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { OWNER, REPO, REPOSITORY, SITE_NAME, SOURCE_URL } from "@app/app/site";

// The identity seam a product's bootstrap rewrites (app/site.ts): one literal
// line each. SITE_NAME is the page title; SOURCE_URL is the repository the
// page lists the issues of, and every link to it.
const app = resolve(__dirname, "../../../apps/web");

describe("site identity (apps/web/app/site.ts)", () => {
  it("names the site and its own repository", () => {
    expect(SITE_NAME.trim()).not.toBe("");
    expect(SOURCE_URL).toMatch(/^https:\/\/github\.com\/[A-Za-z0-9-]+\/[a-z0-9-]+$/);
  });

  it("derives owner/name from SOURCE_URL", () => {
    expect(REPOSITORY).toBe(`${OWNER}/${REPO}`);
    expect(`https://github.com/${REPOSITORY}`).toBe(SOURCE_URL);
  });

  it("keeps both on a literal line of their own", () => {
    const src = readFileSync(resolve(app, "app/site.ts"), "utf8");
    expect(src).toMatch(/^export const SITE_NAME = "[^"\n]+";$/m);
    expect(src).toMatch(/^export const SOURCE_URL = "https:\/\/github\.com\/[^"\n]+";$/m);
  });

  it("is the only repository the app names (the template hard-coded the nextjs organisation's)", () => {
    for (const f of ["app/page.tsx", "app/[id]/layout.tsx", "app/explanation.tsx", "lib/github.ts"]) {
      const src = readFileSync(resolve(app, f), "utf8");
      expect(src, f).not.toMatch(/github\.com\/nextjs|\/repos\/nextjs|'nextjs'/);
    }
  });
});
