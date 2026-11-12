// The site's identity, written once. The page title reads SITE_NAME; the
// repository the page lists the issues of — and every link to it — is
// SOURCE_URL. Instantiating the site under a new name rewrites both to that
// name and its own repository, so keep them literal and on one line each.
// prettier-ignore
export const SITE_NAME = "On-Demand Incremental Static Regeneration";
// prettier-ignore
export const SOURCE_URL = "https://github.com/sourceplane/on-demand-isr";

// "owner/name", read from SOURCE_URL: the repository whose issues the page
// shows, and whose owner's GitHub App installation reads them.
export const REPOSITORY = SOURCE_URL.replace("https://github.com/", "");
export const [OWNER, REPO] = REPOSITORY.split("/") as [string, string];
