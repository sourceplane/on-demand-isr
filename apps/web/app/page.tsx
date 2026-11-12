import styles from '../styles/Home.module.scss';
import Link from 'next/link';
import {
  CommentIcon,
  IssueIcon,
  StarIcon,
  ForkIcon,
  GitHubIcon
} from './icons';
import { fetchIssueAndRepoData } from '../lib/github';
import Explanation from './explanation';
import { Time } from './time-ago';
import ConnectNotice from './connect-notice';
import { OWNER, REPO, SOURCE_URL } from './site';

export default async function Page() {
  const { issues, forks_count, stargazers_count, connected } =
    await fetchIssueAndRepoData();

  return (
    <main className={styles.main}>
      <Explanation />
      {!connected && <ConnectNotice />}
      <div className={styles.repo}>
        <div className={styles.repo_title}>
          <GitHubIcon />{' '}
          <a
            href={SOURCE_URL}
            target="_blank"
            rel="noreferrer"
          >
            {OWNER}
          </a>{' '}
          / <Link href="/">{REPO}</Link>
        </div>
        <div className={styles.forks_stars}>
          <a
            href={`${SOURCE_URL}/fork`}
            target="_blank"
            rel="noreferrer"
          >
            <ForkIcon /> {new Number(forks_count).toLocaleString()}
          </a>
          <a
            href={SOURCE_URL}
            target="_blank"
            rel="noreferrer"
          >
            <StarIcon /> {new Number(stargazers_count).toLocaleString()}
          </a>
        </div>
      </div>
      <div className={styles.issues}>
        {issues.map((issue: any) => (
          <IssueLink key={issue.number} issue={issue} />
        ))}
      </div>
    </main>
  );
}

function IssueLink({ issue }: { issue: any }) {
  return (
    <Link href={`/${issue.number}`} className={styles.issue}>
      <div className={styles.left}>
        <IssueIcon />
        <div>
          <div className={styles.issue_title}>{issue.title}</div>
          <div className={styles.issue_desc}>
            {`#${issue.number} opened `}
            {` by ${issue.user.login}`}
          </div>
        </div>
      </div>
      <div className={styles.right}>
        <Time time={issue.created_at} />
        <div className={styles.comment_count}>
          <CommentIcon /> {new Number(issue.comments).toLocaleString()}
        </div>
      </div>
    </Link>
  );
}
