#!/usr/bin/env python3
"""The connected e2e's Worker secrets, as `wrangler dev` reads them (.dev.vars).

    dev-vars.py <app.pem> <app-id> <webhook-secret> <stand-in-origin>

A dotenv file: the App's private key on one line with its newlines written as
`\\n` inside double quotes (dotenv expands them), the App ID, the webhook
secret, and E2E_GITHUB_ORIGIN, which only testing/lib/e2e-worker.mjs reads.
"""
import sys

pem, app_id, secret, origin = sys.argv[1:5]
key = open(pem).read().strip().replace("\n", "\\n")
print(f'GITHUB_APP_ID="{app_id}"')
print(f'GITHUB_APP_PK_PEM="{key}"')
print(f'GITHUB_WEBHOOK_SECRET="{secret}"')
print(f'E2E_GITHUB_ORIGIN="{origin}"')
