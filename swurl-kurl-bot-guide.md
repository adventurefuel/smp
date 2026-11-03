# Swurl Kurl CRM — Bot Connection Guide

For the Grok "CLOSER" agent (and any other bot). Paste this whole page into the bot's instructions, then give it the API key through its secret/credential field.

## What the bot can and can't do

**Can:** read clients, website requests, appointments and purchase requests; add notes to a client.
**Can't:** see payments, see the owner's private notes or internal admin notes, change a client's stage, edit or delete anything, create clients.

Notes the bot adds are stored separately and show in the client's timeline in the store app labelled "Bot note". Limit: 120 requests per minute per key.

## 1. Connect

- **Base URL:** `https://eyzhywxehxoqtrjzooab.supabase.co/functions/v1/agent-api`
- **Auth header on every request:** `Authorization: Bearer skb_...` (the key from Store → Bot access → Create key; it is shown once)
- Quick test: `GET {base}/health` should answer `{"ok":true,"agent":"<key name>",...}`

```bash
curl -s -H "Authorization: Bearer $SKB_KEY" "$BASE/summary"
```

A revoked or wrong key answers `401`. Revoking a key in the store app cuts the bot off immediately.

## 2. Endpoints

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | Confirms the key works |
| GET | `/summary` | Counts by stage, unhandled new requests, follow-ups due, next appointments |
| GET | `/clients` | Filters: `stage`, `q` (name/phone/email), `updated_since` (ISO time), `follow_up_due=true`, `limit` (max 200), `offset` |
| GET | `/clients/{id}` | Client plus appointments, requests, purchase requests and bot notes |
| GET | `/requests` | Filters: `status`, `type` (`consultation` or `booking`), `since`, `limit`, `offset`. Training inquiries are left out unless `include_training=true` |
| GET | `/purchase-requests` | Filters: `status`, `since`. Amounts are not included |
| GET | `/visits` | Appointments. Filters: `from`, `to`, `status`, `client_id` |
| POST | `/clients/{id}/notes` | Body: `{"body":"...","category":"note"}` (max 2000 characters) |

**Stages:** `lead`, `contacted`, `consult_booked`, `session_1`, `session_2`, `complete`, `not_a_fit`
**Note categories:** `note`, `hesitation`, `objection`, `follow_up`, `outcome`
**Request status:** `new`, `confirmed`, `completed`, `cancelled`, `no_show`
**Appointment status:** `scheduled`, `completed`, `cancelled`, `no_show`

Add a note:

```bash
curl -s -X POST -H "Authorization: Bearer $SKB_KEY" -H "Content-Type: application/json" \
  -d '{"body":"Likes the results but worried about cost. Asked about payment options.","category":"hesitation"}' \
  "$BASE/clients/CLIENT_ID/notes"
```

Contact details (`phone`, `email`) are included so the bot can follow up with people who asked to be contacted. Check `contact_pref` and `notes` on a request before reaching out, and only contact people who requested it.

## 3. Webhook (optional — instant alerts)

In Store → Bot access → "Get pinged…", paste the webhook address the bot gives you, tick the events, switch it on and press Save. Copy the signing secret into the bot.

Events: `request.created`, `booking.created`, `visit.scheduled`, `purchase.created`, plus `test.ping` for the "Send a test" button.

Each delivery is a `POST` with JSON `{ "id", "event", "created_at", "data": {...} }`, where `data` holds the `request` (or `visit` / `purchase_request`) and the matching `client`. Headers:

- `X-SwurlKurl-Event` — the event name
- `X-SwurlKurl-Timestamp` — Unix seconds
- `X-SwurlKurl-Signature` — `sha256=` + hex HMAC-SHA256 of `timestamp + "." + rawBody` using the signing secret

If the bot gives you a **sender key** (Grok Routines does), paste it into the "Sender key" box in the Bot access tab. It is sent on every message as `Authorization: Bearer <sender key>` (and `X-Api-Key`). The signature headers still go along too, so the bot can verify them if it wants to.

Answer with any `2xx` quickly. One automatic retry follows a timeout or 5xx. The store app shows the last delivery result.

Verify it (Node):

```js
import crypto from 'node:crypto';
function verify(secret, headers, rawBody){
  const ts=headers['x-swurlkurl-timestamp'], sig=headers['x-swurlkurl-signature']||'';
  if(!ts||Math.abs(Date.now()/1000-Number(ts))>300) return false;   // reject old messages
  const want='sha256='+crypto.createHmac('sha256',secret).update(ts+'.'+rawBody).digest('hex');
  return sig.length===want.length && crypto.timingSafeEqual(Buffer.from(sig),Buffer.from(want));
}
```

Python:

```python
import hmac, hashlib, time
def verify(secret, headers, raw_body: bytes) -> bool:
    ts = headers.get("x-swurlkurl-timestamp", ""); sig = headers.get("x-swurlkurl-signature", "")
    if not ts or abs(time.time() - int(ts)) > 300: return False
    want = "sha256=" + hmac.new(secret.encode(), ts.encode() + b"." + raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(sig, want)
```

## 4. Suggested working pattern for the CLOSER

1. On each webhook (or on a schedule), `GET /requests?status=new` and `GET /clients?follow_up_due=true`.
2. For each person, `GET /clients/{id}` to see history and earlier bot notes before writing anything.
3. After every conversation, `POST` a note: use `hesitation` for the reason someone is unsure, `objection` for a specific pushback to pass to Terrence, `follow_up` for the agreed next step, and `outcome` for the result.
4. Never invent client details. If something isn't in the data, say so in the note.

## 5. Troubleshooting

- `401 Invalid or revoked API key` — key typed wrong, or revoked. Make a new one.
- `429` — over 120 requests a minute; wait 30 seconds.
- `405 This key can only read data and add notes` — the bot tried a write that isn't allowed.
- Webhook shows an error in the store app — the bot's address is down or answered with an error; press "Send a test" after fixing it.
