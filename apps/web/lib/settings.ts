import 'server-only';
import { getCloudflareContext } from '@opennextjs/cloudflare';

// The GitHub App's settings, read per request from the Worker's environment:
// GITHUB_APP_ID and GITHUB_APP_PK_PEM (the App's private key) authenticate as
// the App, and GITHUB_WEBHOOK_SECRET checks every webhook's signature. All
// three are optional Orun secrets the deploy pushes to the Worker after the
// build (tooling/wire/worker-secrets.mjs), so no build ever carries them.
// Outside a Worker request — `next build`, `next dev` without its bindings,
// the tests — they come from process.env, as the template read them.
export type Setting = 'GITHUB_APP_ID' | 'GITHUB_APP_PK_PEM' | 'GITHUB_WEBHOOK_SECRET';

export function setting(name: Setting): string {
  try {
    const value = (getCloudflareContext().env as unknown as Record<string, unknown>)[name];
    if (typeof value === 'string' && value) return value;
  } catch {
    // Not inside a Worker request.
  }
  return process.env[name] || '';
}

// Connected once the App can authenticate. Until then every page renders the
// sample issues (lib/sample.ts) under a notice that says how to connect it.
export function isConnected(): boolean {
  return Boolean(setting('GITHUB_APP_ID') && setting('GITHUB_APP_PK_PEM'));
}
