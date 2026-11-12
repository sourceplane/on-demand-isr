import { initOpenNextCloudflareForDev } from '@opennextjs/cloudflare';
import type { NextConfig } from 'next';
import path from 'node:path';

const nextConfig: NextConfig = {
  // Upstream's: `"use cache"` caches the issues the pages read (lib/github.ts),
  // and the webhook drops them with revalidatePath. On Workers that cache is
  // the R2 bucket and Durable Objects open-next.config.ts names.
  experimental: {
    useCache: true,
    inlineCss: true,
  },
  images: {
    // The avatars come from GitHub's own image host, as sized as the page
    // needs: nothing for an image optimiser to do, so the Worker carries none.
    unoptimized: true,
    remotePatterns: [
      {
        protocol: 'https',
        hostname: 'avatars.githubusercontent.com',
        port: '',
        pathname: '/u/**'
      }
    ]
  },
  logging: {
    fetches: {
      fullUrl: true
    }
  },
  // Required by @opennextjs/cloudflare, which bundles `.next/standalone/**`
  // into the Worker. Traced from the monorepo root so workspace dependencies
  // resolve from the root node_modules.
  output: 'standalone',
  outputFileTracingRoot: path.join(__dirname, '../..'),
  // Dev server only (`next build` ignores it): orun.work's live Preview tab
  // loads `next dev` from the preview's own host, and Next.js refuses the hot
  // reload and other /_next/* dev requests from an origin it is not told
  // about. These are the preview's hosts, prod's and stage's.
  allowedDevOrigins: [
    '*.orun-preview.app',
    'preview-gateway-stage.oruncloud.workers.dev'
  ]
};

export default nextConfig;

// `next dev` reaches the Worker's bindings (the R2 cache bucket, the cache
// Durable Objects) through a local miniflare built from wrangler.jsonc.
initOpenNextCloudflareForDev();
