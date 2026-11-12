import { isConnected } from '../../../lib/settings';

// The deploy's smoke check, and a quick way to tell whether the GitHub App is
// connected: the Worker answers it (no static file can), and it calls nothing.
export function GET() {
  return Response.json(
    { ok: true, connected: isConnected() },
    { headers: { 'cache-control': 'no-store' } }
  );
}

export const dynamic = 'force-dynamic';
