# web

The on-demand ISR site (Next.js on Cloudflare Workers + Static Assets via @opennextjs/cloudflare, per environment; R2 + Durable Objects as the Next.js cache; a GitHub App's webhook regenerates the pages; sample issues until an App is connected)

A Cloudflare Worker with Static Assets (server rendering plus static files), deployed per environment by its CI lane.

|              |                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------ |
| Type         | `cloudflare-workers-assets-turbo`                                                                                  |
| Source       | `apps/web`                                                                                                         |
| Package      | `@app/web`                                                                                                         |
| Environments | `dev`: `verify` · `stage`: `verify`, `deploy` on a push to `main` · `prod`: `verify`, `deploy` on a push to `main` |

## Depends on

- **cloudflare-r2** — Provisions the Cloudflare R2 bucket the app binds (stage and prod)

## Depended on by

- (none)
