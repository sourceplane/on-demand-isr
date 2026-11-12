# web-tests

The port's vitest suite — the site seam (its name and its repository), the GitHub App settings read per request, the App's RS256 JWT and installation token against an in-process GitHub, the issues and sample issues the pages render, the webhook's signature check and the paths it revalidates, and /api/health

The test suite for **web**. It deploys nothing: its lane installs, builds and runs the tests.

|              |                      |
| ------------ | -------------------- |
| Type         | `turbo-package`      |
| Source       | `tests/web`          |
| Package      | `@app/web-tests`     |
| Environments | `dev`: `quick-check` |

## Depends on

- (none)

## Depended on by

- (none)
