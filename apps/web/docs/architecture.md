# web — architecture

Built by the turbo pipeline from `apps/web` and deployed with wrangler.

|                     |                                                 |
| ------------------- | ----------------------------------------------- |
| Worker config       | `apps/web/wrangler.template.jsonc`              |
| Entry               | `.open-next/worker.js`                          |
| Compatibility date  | `2026-10-01`                                    |
| Compatibility flags | `nodejs_compat`, `global_fetch_strictly_public` |

## Bindings

| Binding                     | Kind            | Source                                |
| --------------------------- | --------------- | ------------------------------------- |
| `NEXT_INC_CACHE_R2_BUCKET`  | R2 bucket       | `r2_bucket_name` from `cloudflare-r2` |
| `NEXT_CACHE_DO_QUEUE`       | Durable Object  | class `DOQueueHandler`                |
| `NEXT_TAG_CACHE_DO_SHARDED` | Durable Object  | class `DOShardedTagCache`             |
| `WORKER_SELF_REFERENCE`     | Service binding | Worker `on-demand-isr-web-__ENV__`    |
| `ASSETS`                    | Static assets   | `.open-next/assets`                   |

Identifiers marked _from_ a component are filled in at deploy time from
that component's published outputs for the environment being deployed.

## Wiring

Resolved at deploy time from secrets the infrastructure lanes publish (names only):

- `WIRING_CLOUDFLARE_R2_PROD`
- `WIRING_CLOUDFLARE_R2_STAGE`

## Secrets resolved by the lane (names only)

- `GITHUB_APP_ID` (optional)
- `GITHUB_APP_PK_PEM` (optional)
- `GITHUB_WEBHOOK_SECRET` (optional)
