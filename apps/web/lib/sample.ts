// The issues the page shows until a GitHub App is connected (lib/settings.ts):
// in GitHub's own shapes, so the pages render them exactly as they will render
// the repository's. They are about this site, not anyone's real issues; each
// links to the README's section on connecting the App.
import { SOURCE_URL } from '../app/site';

const CONNECT = `${SOURCE_URL}#connecting-a-github-app`;
export const SAMPLE_ISSUES = [
  {
    id: 3,
    number: 3,
    title: 'Connect a GitHub App to list this repository’s issues',
    comments: 0,
    created_at: '2026-11-12T09:00:00Z',
    html_url: CONNECT,
    user: { login: 'sample' },
    body: [
      'These are sample issues. The page lists the repository’s own issues once its GitHub App is connected:',
      '',
      '1. Create a GitHub App with read-only access to **Issues**, subscribed to **Issues** events, its webhook pointed at `/api/webhook`.',
      '2. Install it on the repository.',
      '3. Store `GITHUB_APP_ID`, `GITHUB_APP_PK_PEM` and `GITHUB_WEBHOOK_SECRET` as Orun secrets, and redeploy.',
      '',
      'The README’s "Connecting a GitHub App" has every step.'
    ].join('\n')
  },
  {
    id: 2,
    number: 2,
    title: 'How a webhook regenerates this page',
    comments: 1,
    created_at: '2026-11-11T09:00:00Z',
    html_url: CONNECT,
    user: { login: 'sample' },
    body: [
      'When an issue changes, GitHub calls the webhook, which checks its signature and drops this page from the cache:',
      '',
      '```ts',
      "revalidatePath('/');",
      'revalidatePath(`/${issueNumber}`);',
      '```',
      '',
      'The next visit renders the page again and caches it until the next change.'
    ].join('\n')
  },
  {
    id: 1,
    number: 1,
    title: 'Pages are served from the cache',
    comments: 0,
    created_at: '2026-11-10T09:00:00Z',
    html_url: CONNECT,
    user: { login: 'sample' },
    body: 'Each page is rendered once and kept in an R2 bucket, with a Durable Object recording which pages a webhook has dropped. A visit reads the cache, not GitHub.'
  }
];

export interface SampleComment {
  id: number;
  html_url: string;
  user: { login: string; avatar_url?: string };
  created_at: string;
  body: string;
}

export const SAMPLE_COMMENTS: Record<number, SampleComment[]> = {
  2: [
    {
      id: 21,
      html_url: CONNECT,
      user: { login: 'sample' },
      created_at: '2026-11-11T10:00:00Z',
      body: 'Try it once the App is connected: open an issue and refresh the page.'
    }
  ]
};

