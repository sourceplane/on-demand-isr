import 'server-only';
import jwt from 'jsonwebtoken';
import { notFound } from 'next/navigation';
import { OWNER, REPOSITORY } from '../app/site';
import { SAMPLE_COMMENTS, SAMPLE_ISSUES } from './sample';
import { isConnected, setting } from './settings';

let accessToken;

async function getAccessToken(installationId: number, token: string) {
  const data = await fetchGitHub(
    `/app/installations/${installationId}/access_tokens`,
    token,
    { method: 'POST' }
  );
  return data.token;
}

function getGitHubJWT() {
  if (!setting('GITHUB_APP_ID') || !setting('GITHUB_APP_PK_PEM')) {
    throw new Error(
      'GITHUB_APP_ID and GITHUB_APP_PK_PEM must be set (Orun secrets, or .env.local for next dev)'
    );
  }

  return jwt.sign(
    {
      iat: Math.floor(Date.now() / 1000) - 60,
      iss: setting('GITHUB_APP_ID'),
      exp: Math.floor(Date.now() / 1000) + 60 * 10 // 10 minutes is the max
    },
    setting('GITHUB_APP_PK_PEM'),
    {
      algorithm: 'RS256'
    }
  );
}

async function getInstallation(token: string) {
  const installations = await fetchGitHub('/app/installations', token);
  return installations.find(
    (i: any) => i.account.login.toLowerCase() === OWNER.toLowerCase()
  );
}

function createGitHubRequest(path: string, token: string, opts: any = {}) {
  return fetch(`https://api.github.com${path}`, {
    ...opts,
    headers: {
      ...opts.headers,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/vnd.github.v3+json'
    }
  });
}

export async function fetchGitHub(path: string, token: string, opts: any = {}) {
  let req = await createGitHubRequest(path, token, opts);

  if (req.status === 401) {
    // JWT has expired, cache a new token
    await setAccessToken();
    // Retry request with new cached access token
    req = await createGitHubRequest(path, accessToken, opts);
  }

  return req.json();
}

export async function readAccessToken() {
  // check if exists
  if (!accessToken) {
    await setAccessToken();
  }

  return accessToken;
}

export async function setAccessToken() {
  const jwt = getGitHubJWT();
  const installation = await getInstallation(jwt);
  if (!installation) {
    throw new Error(
      `The GitHub App has no installation for ${OWNER}: install it on ${REPOSITORY}`
    );
  }
  accessToken = await getAccessToken(installation.id, jwt);

  return accessToken;
}

export async function fetchIssueAndRepoData() {
  'use cache';

  if (!isConnected()) {
    console.log('[Next.js] No GitHub App connected: sample issues for /');
    return { issues: SAMPLE_ISSUES, stargazers_count: 0, forks_count: 0, connected: false };
  }

  const [issues, repoDetails] = await Promise.all([
    fetchGitHub(`/repos/${REPOSITORY}/issues`, accessToken),
    fetchGitHub(`/repos/${REPOSITORY}`, accessToken)
  ]);

  console.log('[Next.js] Fetching data for /');
  console.log(`[Next.js] Issues: ${issues.length}`);

  return {
    issues,
    stargazers_count: repoDetails.stargazers_count,
    forks_count: repoDetails.forks_count,
    connected: true
  };
}

export async function fetchIssuePageData(id: string) {
  'use cache';

  if (!isConnected()) {
    const issue = SAMPLE_ISSUES.find((i) => String(i.number) === id);
    if (!issue) {
      notFound();
    }
    return {
      issue,
      comments: SAMPLE_COMMENTS[issue.number] || [],
      stargazers_count: 0,
      forks_count: 0,
      connected: false
    };
  }

  const [issue, comments, repoDetails] = await Promise.all([
    fetchGitHub(`/repos/${REPOSITORY}/issues/${id}`, accessToken),
    fetchGitHub(
      `/repos/${REPOSITORY}/issues/${id}/comments`,
      accessToken
    ),
    fetchGitHub(`/repos/${REPOSITORY}`, accessToken)
  ]);

  console.log(`[Next.js] Fetching data for /${id}`);
  console.log(`[Next.js] [${id}] Comments: ${comments.length}`);

  if (issue.message === 'Not Found') {
    notFound();
  }

  return {
    issue,
    comments,
    stargazers_count: repoDetails.stargazers_count,
    forks_count: repoDetails.forks_count,
    connected: true
  };
}
