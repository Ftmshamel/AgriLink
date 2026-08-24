# AgriLink payments worker

A single Cloudflare Worker that exists for one reason: to hold the Xendit
secret key. Creating an invoice requires that key, and anything shipped inside
an APK can be read by unzipping it, so the key cannot live in the Flutter app.

The worker keeps no database and no state. It forwards two calls to Xendit and
returns what Xendit says.

| Route | Method | Does |
| ----- | ------ | ---- |
| `/health` | GET | Reports whether the secret is configured |
| `/invoice` | POST | Creates an invoice — `{ amount, reference, description }` |
| `/invoice?id=…` | GET | Reports whether that invoice has been paid |

`amount` is in **pesos**. `reference` becomes Xendit's `external_id`, which is
how a payment is matched back to an order without this worker storing anything.

Xendit reports `PENDING`, `PAID`, `SETTLED`, and `EXPIRED`. Both `PAID` and
`SETTLED` count as paid.

## Deploying

You need a Xendit account and a Cloudflare account. Neither can be created for
you — both need your own email and confirmation.

```powershell
cd C:\Users\LAPTOP\AgriLink\payments

# 1. Sign in to Cloudflare (opens a browser)
npx wrangler login

# 2. Store the secrets. These are typed into the prompt and stored on
#    Cloudflare — they are never written to this folder or to git.
npx wrangler secret put XENDIT_SECRET   # paste xnd_development_… from Xendit
npx wrangler secret put APP_TOKEN       # any long random string you invent

# 3. Deploy
npx wrangler deploy
```

In the Xendit dashboard the test key is under **Settings → Developers → API
Keys**, in **Test mode**, and starts with `xnd_development_`. Give the key
**write permission on Invoices** — a read-only key can check an invoice but
cannot create one.

`wrangler deploy` prints the live URL, something like
`https://agrilink-payments.<your-subdomain>.workers.dev`. That URL and the
`APP_TOKEN` go into the Flutter app; the Xendit secret never does.

Check it answers before wiring the app to it:

```powershell
curl.exe https://agrilink-payments.<your-subdomain>.workers.dev/health
# {"ok":true,"configured":true}
```

## What APP_TOKEN is and is not

It is a shared string the app sends with each request, so a stranger who finds
the worker URL cannot run up invoices on the Xendit account. It ships inside
the APK, so a determined person can extract it — it is a speed bump, not real
authentication. Per-user auth needs Firebase Auth, which is listed as remaining
work on the project.
