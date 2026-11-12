import crypto from 'crypto';
import { revalidatePath } from 'next/cache';
import { setting } from '../../../lib/settings';

export async function POST(request: Request) {
  // No secret, no webhook: the template keyed its HMAC with '' when the secret
  // was unset, which anyone can compute. Until GITHUB_WEBHOOK_SECRET is set,
  // nothing may revalidate the pages.
  const secret = setting('GITHUB_WEBHOOK_SECRET');
  if (!secret) {
    return new Response('Webhook not configured: set GITHUB_WEBHOOK_SECRET.', {
      status: 503,
    });
  }

  try {
    const text = await request.text();

    const signature = crypto
      .createHmac('sha256', secret)
      .update(text)
      .digest('hex');

    const trusted = Buffer.from(`sha256=${signature}`, 'ascii');
    const untrusted = Buffer.from(
      request.headers.get('x-hub-signature-256') || '',
      'ascii'
    );

    if (!crypto.timingSafeEqual(trusted, untrusted)) {
      console.log('[Next.js] Invalid signature.', {
        trusted: trusted.toString('hex'),
        untrusted: untrusted.toString('hex'),
      });
      return new Response('Invalid signature.', {
        status: 400,
      });
    }

    const payload = JSON.parse(text);
    const issueNumber = payload.issue?.number;

    console.log('[Next.js] Revalidating /');
    revalidatePath('/');

    if (issueNumber) {
      console.log(`[Next.js] Revalidating /${issueNumber}`);
      revalidatePath(`/${issueNumber}`);
    }
  } catch (error) {
    return new Response(`Webhook error: ${error.message}`, {
      status: 400,
    });
  }

  return new Response('Success!', {
    status: 200,
  });
}
