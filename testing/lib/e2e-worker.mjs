// THE E2E'S OWN ENTRY, never shipped: the built Worker, with its requests to
// api.github.com sent to the local stand-in (testing/lib/fake-github.mjs).
//
// The template's client (apps/web/lib/github.ts) builds
// `https://api.github.com/…` itself and calls the global fetch, and the
// product carries no option for another host. So this wraps the global fetch
// BEFORE the Worker's modules load (a dynamic import, after the wrap: Next.js
// captures the fetch it patches when its server starts) and sends a request
// for api.github.com to E2E_GITHUB_ORIGIN, path, method, headers and body as
// they were. Everything else is untouched, and the product code is exactly
// what deploys. It re-exports the two Durable Object classes the config binds
// (the tag cache and the revalidation queue), as the built Worker does.
// testing/e2e.test.sh copies this next to the staged build's .open-next/ and
// serves it with a copy of wrangler.jsonc whose `main` is this file.
let origin = "";
const realFetch = globalThis.fetch;
globalThis.fetch = (input, init) => {
  const request = new Request(input, init);
  const url = new URL(request.url);
  if (origin && url.hostname === "api.github.com") {
    return realFetch(new Request(new URL(url.pathname + url.search, origin), request));
  }
  return realFetch(input, init);
};
const built = await import("./.open-next/worker.js");
export const DOQueueHandler = built.DOQueueHandler;
export const DOShardedTagCache = built.DOShardedTagCache;
export default {
  fetch(request, env, ctx) {
    origin = env.E2E_GITHUB_ORIGIN || "";
    return built.default.fetch(request, env, ctx);
  },
};
