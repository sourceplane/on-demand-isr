// OpenNext Cloudflare adapter config.
//
// The template caches the GitHub issues its pages read with `"use cache"`
// (lib/github.ts) and, when GitHub's webhook says an issue changed, drops the
// pages that show it with `revalidatePath` (app/api/webhook). That is Next's
// page and data cache plus its tag cache, which on Workers live in bindings:
//
//   incremental cache → R2 (NEXT_INC_CACHE_R2_BUCKET): every rendered page
//                       and `"use cache"` entry, under the build's id, so a
//                       new deploy renders afresh with the Worker's settings
//   tag cache         → a sharded Durable Object (NEXT_TAG_CACHE_DO_SHARDED):
//                       which paths were revalidated when, consulted on every
//                       cache read so a dropped page is rendered again
//   queue             → a Durable Object (NEXT_CACHE_DO_QUEUE): deduplicated
//                       background revalidation of stale ISR entries, which
//                       calls the Worker back through WORKER_SELF_REFERENCE
//
// The bucket is provisioned by infra/terraform/cloudflare-r2 and wired into
// wrangler.jsonc per environment; the Durable Objects are classes the
// generated Worker exports (DOQueueHandler, DOShardedTagCache) and the
// `migrations` in wrangler.template.jsonc create on deploy. No D1, no KV.
// Nothing is copied into the bucket at deploy (no populateCache): the build
// renders `/` without the App's settings, so each page is rendered on its
// first visit, with them, and cached from then on.
import { defineCloudflareConfig } from "@opennextjs/cloudflare/config";
import r2IncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/r2-incremental-cache";
import doQueue from "@opennextjs/cloudflare/overrides/queue/do-queue";
import doShardedTagCache from "@opennextjs/cloudflare/overrides/tag-cache/do-sharded-tag-cache";

export default defineCloudflareConfig({
  incrementalCache: r2IncrementalCache,
  queue: doQueue,
  tagCache: doShardedTagCache({ baseShardSize: 12 }),
});
