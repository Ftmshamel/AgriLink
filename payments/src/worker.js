/**
 * AgriLink payment endpoint.
 *
 * The app cannot talk to Xendit directly: creating an invoice needs the secret
 * key, and anything shipped inside an APK can be read by unzipping it. So this
 * worker exists for one reason only - to hold that key. It has no database and
 * keeps no state; it forwards two calls and hands back what Xendit says.
 *
 *   POST /invoice          create an invoice, return its id and payment URL
 *   GET  /invoice?id=...   ask whether that invoice has been paid
 */

const XENDIT = 'https://api.xendit.co/v2/invoices';

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });

/** Xendit authenticates with the secret key as a Basic username, no password. */
const authHeader = (secret) => 'Basic ' + btoa(secret + ':');

/** Xendit reports PAID and SETTLED separately; both mean the buyer has paid. */
const isPaid = (status) => status === 'PAID' || status === 'SETTLED';

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') {
      return json({ ok: true, configured: Boolean(env.XENDIT_SECRET) });
    }

    if (!env.XENDIT_SECRET) {
      return json({ error: 'XENDIT_SECRET is not set on this worker.' }, 500);
    }

    // Not real authentication - the app is public, so this token ships inside
    // the APK too. It only stops a stranger who stumbles on the URL from
    // running up invoices on the account. Real per-user auth needs Firebase
    // Auth, which is listed as remaining work.
    if (env.APP_TOKEN && request.headers.get('x-agrilink-token') !== env.APP_TOKEN) {
      return json({ error: 'Not allowed.' }, 403);
    }

    if (url.pathname === '/invoice' && request.method === 'POST') {
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: 'Body must be JSON.' }, 400);
      }

      const amount = Number(body.amount);
      if (!Number.isFinite(amount) || amount <= 0) {
        return json({ error: 'Amount must be a positive number of pesos.' }, 400);
      }

      // Xendit requires external_id to be unique per invoice; the order
      // reference is exactly that, and it lets us match a payment back to an
      // order without this worker storing anything.
      const externalId = String(body.reference || '').trim();
      if (!externalId) {
        return json({ error: 'Missing order reference.' }, 400);
      }

      const upstream = await fetch(XENDIT, {
        method: 'POST',
        headers: {
          authorization: authHeader(env.XENDIT_SECRET),
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          external_id: externalId,
          amount,
          currency: 'PHP',
          description: String(body.description || 'AgriLink order').slice(0, 255),
          success_redirect_url: env.SUCCESS_URL || undefined,
          invoice_duration: 3600,
        }),
      });

      const payload = await upstream.json().catch(() => ({}));
      if (!upstream.ok) {
        // Pass Xendit's own wording through; a bare status code tells the
        // buyer nothing about what went wrong.
        const detail =
          payload?.message || payload?.error_code || 'Xendit rejected the request.';
        return json({ error: detail }, upstream.status);
      }

      return json({
        id: payload.id,
        url: payload.invoice_url,
        reference: payload.external_id,
        status: payload.status,
        amount: payload.amount,
        currency: payload.currency,
        paid: isPaid(payload.status),
      });
    }

    if (url.pathname === '/invoice' && request.method === 'GET') {
      const id = url.searchParams.get('id');
      if (!id) return json({ error: 'Missing id.' }, 400);

      const upstream = await fetch(`${XENDIT}/${encodeURIComponent(id)}`, {
        headers: { authorization: authHeader(env.XENDIT_SECRET) },
      });
      const payload = await upstream.json().catch(() => ({}));
      if (!upstream.ok) {
        const detail =
          payload?.message || payload?.error_code || 'Could not read that invoice.';
        return json({ error: detail }, upstream.status);
      }

      return json({
        id: payload.id,
        status: payload.status,
        reference: payload.external_id,
        amount: payload.amount,
        currency: payload.currency,
        method: payload.payment_method || '',
        channel: payload.payment_channel || '',
        paid: isPaid(payload.status),
      });
    }

    return json({ error: 'Not found.' }, 404);
  },
};
