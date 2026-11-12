import styles from '../styles/Home.module.scss';
import { REPOSITORY, SOURCE_URL } from './site';

// Shown above the sample issues until a GitHub App is connected
// (lib/settings.ts): what the page will list, and where the steps are.
export default function ConnectNotice() {
  return (
    <p className={styles.explanation_notes} data-notice="connect-github-app">
      These are sample issues: no GitHub App is connected yet.{' '}
      <a href={`${SOURCE_URL}#connecting-a-github-app`} target="_blank" rel="noreferrer">
        Connect one
      </a>{' '}
      to list the issues of {REPOSITORY} here.
    </p>
  );
}
