// Swurl Kurl CRM — bot (agent) API.
//
// What a connected bot can do:
//   READ   clients, requests, bookings (visits), purchase requests, a summary
//   WRITE  add a note to a client (stored separately from the owner's private notes)
// What it can never see: payments, the owner's private notes, internal admin notes, prices paid.
//
// Auth: `Authorization: Bearer skb_...` (key made in the store app > Bot access). Keys are stored
// only as a SHA-256 hash and can be revoked at any time. 120 requests / minute / key.
//
// Also: POST /emit (called by the database with x-hook-secret) sends the signed outbound webhook,
// and POST /webhook-test (signed-in owner only) sends a test event to the saved webhook URL.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (b: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json", ...extra } });

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

// ---- exactly which columns a bot may see -------------------------------------------------
const CLIENT_COLS = "id,created_at,updated_at,name,phone,email,referred_by,lead_source,stage,package_name,follow_up_on";
const VISIT_COLS = "id,created_at,client_id,kind,starts_at,duration_min,status";
const REQUEST_COLS =
  "id,code,created_at,source,name,phone,email,goal,contact_pref,best_time,lead_source,preferred_date,preferred_time,notes,status,service_name,option_label,price,request_type,inquiry_type,referred_by,client_id";
const ORDER_COLS = "id,code,created_at,offer_name,qty,name,phone,email,preferred_date,notes,status,referred_by,client_id";
const NOTE_COLS = "id,created_at,client_id,agent_label,category,body";

const STAGES = ["lead", "contacted", "consult_booked", "session_1", "session_2", "complete", "not_a_fit"];
const CATEGORIES = ["note", "hesitation", "objection", "follow_up", "outcome"];
const EVENTS = ["request.created", "booking.created", "visit.scheduled", "purchase.created"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const RATE_PER_MIN = 120;

const enc = new TextEncoder();
const hex = (buf: ArrayBuffer) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
const sha256 = async (s: string) => hex(await crypto.subtle.digest("SHA-256", enc.encode(s)));
async function hmac(secret: string, msg: string) {
  const k = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return hex(await crypto.subtle.sign("HMAC", k, enc.encode(msg)));
}
const safeEq = (a: string, b: string) => {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
};
const clampInt = (v: string | null, def: number, min: number, max: number) => {
  const n = parseInt(v ?? "", 10);
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : def;
};
const isoOrNull = (v: string | null) => {
  if (!v) return null;
  const d = new Date(v);
  return isNaN(d.getTime()) ? null : d.toISOString();
};
const dateOrNull = (v: string | null) => (v && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : null);

// only https, and never an internal address
function webhookUrlOk(u: string | null | undefined): boolean {
  if (!u) return false;
  try {
    const x = new URL(u);
    if (x.protocol !== "https:") return false;
    const h = x.hostname.toLowerCase();
    if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal") || h.endsWith(".local")) return false;
    if (/^\d+\.\d+\.\d+\.\d+$/.test(h)) {
      const [a, b] = h.split(".").map(Number);
      if (a === 10 || a === 127 || a === 0 || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168)) return false;
    }
    if (h.startsWith("[")) return false;
    return true;
  } catch {
    return false;
  }
}

// ---- outbound webhook --------------------------------------------------------------------
async function deliver(event: string, data: unknown, opts: { force?: boolean } = {}) {
  const { data: w } = await sb.from("agent_webhook").select("*").eq("id", 1).single();
  if (!w) return { ok: false, error: "No webhook settings" };
  if (!opts.force && (!w.enabled || !(w.events || []).includes(event))) return { ok: true, skipped: true };
  if (!webhookUrlOk(w.url)) return { ok: false, error: "Webhook URL must be a public https address" };
  if (!w.secret) return { ok: false, error: "Webhook has no signing secret" };

  const body = JSON.stringify({ id: crypto.randomUUID(), event, created_at: new Date().toISOString(), data });
  let status = 0, error: string | null = null, text = "";
  for (let attempt = 0; attempt < 2; attempt++) {
    const ts = String(Math.floor(Date.now() / 1000));
    const sig = await hmac(w.secret, `${ts}.${body}`);
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 8000);
    try {
      const r = await fetch(w.url, {
        method: "POST",
        signal: ctl.signal,
        redirect: "manual",
        headers: {
          "Content-Type": "application/json",
          "User-Agent": "SwurlKurl-CRM-Webhook/1",
          "X-SwurlKurl-Event": event,
          "X-SwurlKurl-Timestamp": ts,
          "X-SwurlKurl-Signature": "sha256=" + sig,
        },
        body,
      });
      status = r.status;
      text = (await r.text().catch(() => "")).slice(0, 300);
      error = status >= 200 && status < 300 ? null : `HTTP ${status}`;
    } catch (e) {
      status = 0;
      error = e instanceof Error && e.name === "AbortError" ? "Timed out after 8 seconds" : "Could not reach the webhook URL";
    } finally {
      clearTimeout(timer);
    }
    if (!error || (status >= 400 && status < 500)) break;
    await new Promise((r) => setTimeout(r, 2000));
  }
  await sb.from("agent_webhook").update({ last_at: new Date().toISOString(), last_status: status, last_error: error }).eq("id", 1);
  return { ok: !error, status, error, response: text };
}

async function handleEmit(table: string, id: string) {
  if (!UUID.test(id)) return json({ error: "bad id" }, 400);
  if (table === "appointments") {
    const { data: a } = await sb.from("appointments").select(REQUEST_COLS).eq("id", id).single();
    if (!a) return json({ error: "not found" }, 404);
    if (a.inquiry_type === "training") return json({ ok: true, skipped: "training inquiry" });
    const event = a.request_type === "booking" ? "booking.created" : "request.created";
    const { data: c } = a.client_id ? await sb.from("clients").select(CLIENT_COLS).eq("id", a.client_id).single() : { data: null };
    return json(await deliver(event, { request: a, client: c }));
  }
  if (table === "orders") {
    const { data: o } = await sb.from("orders").select(ORDER_COLS).eq("id", id).single();
    if (!o) return json({ error: "not found" }, 404);
    const { data: c } = o.client_id ? await sb.from("clients").select(CLIENT_COLS).eq("id", o.client_id).single() : { data: null };
    return json(await deliver("purchase.created", { purchase_request: o, client: c }));
  }
  if (table === "visits") {
    const { data: v } = await sb.from("visits").select(VISIT_COLS).eq("id", id).single();
    if (!v) return json({ error: "not found" }, 404);
    if (v.status !== "scheduled") return json({ ok: true, skipped: "not scheduled" });
    const { data: c } = await sb.from("clients").select(CLIENT_COLS).eq("id", v.client_id).single();
    return json(await deliver("visit.scheduled", { visit: v, client: c }));
  }
  return json({ error: "bad table" }, 400);
}

// ---- bot endpoints -----------------------------------------------------------------------
async function botRoutes(req: Request, url: URL, route: string, key: { id: string; label: string }) {
  const q = url.searchParams;
  const limit = clampInt(q.get("limit"), 50, 1, 200);
  const offset = clampInt(q.get("offset"), 0, 0, 100000);
  const page = { limit, offset, returned: 0 };
  const parts = route.split("/").filter(Boolean);

  if (req.method === "GET") {
    if (parts.length === 0 || parts[0] === "health") {
      return json({ ok: true, agent: key.label, permissions: ["read", "add_notes"], time: new Date().toISOString() });
    }

    if (parts[0] === "summary") {
      const today = new Date().toISOString().slice(0, 10);
      const weekAgo = new Date(Date.now() - 7 * 864e5).toISOString();
      const counts: Record<string, number> = {};
      for (const s of STAGES) {
        const { count } = await sb.from("clients").select("id", { count: "exact", head: true }).eq("stage", s);
        counts[s] = count ?? 0;
      }
      const { count: newReq } = await sb.from("appointments").select("id", { count: "exact", head: true })
        .eq("status", "new").neq("inquiry_type", "training");
      const { count: reqWeek } = await sb.from("appointments").select("id", { count: "exact", head: true })
        .gte("created_at", weekAgo).neq("inquiry_type", "training");
      const { count: due } = await sb.from("clients").select("id", { count: "exact", head: true })
        .lte("follow_up_on", today).not("stage", "in", "(complete,not_a_fit)");
      const { data: next } = await sb.from("visits").select(VISIT_COLS).eq("status", "scheduled")
        .gte("starts_at", new Date().toISOString()).order("starts_at").limit(10);
      return json({ clients_by_stage: counts, new_requests_unhandled: newReq ?? 0, requests_last_7_days: reqWeek ?? 0, follow_ups_due: due ?? 0, upcoming_visits: next ?? [] });
    }

    if (parts[0] === "clients" && parts.length === 1) {
      let query = sb.from("clients").select(CLIENT_COLS).order("updated_at", { ascending: false }).range(offset, offset + limit - 1);
      const stage = q.get("stage");
      if (stage) {
        if (!STAGES.includes(stage)) return json({ error: "stage must be one of: " + STAGES.join(", ") }, 400);
        query = query.eq("stage", stage);
      }
      const since = isoOrNull(q.get("updated_since"));
      if (since) query = query.gte("updated_at", since);
      if (q.get("follow_up_due") === "true") {
        query = query.lte("follow_up_on", new Date().toISOString().slice(0, 10)).not("stage", "in", "(complete,not_a_fit)");
      }
      const term = (q.get("q") || "").replace(/[^\w@.+\- ]/g, "").trim().slice(0, 60);
      if (term) query = query.or(`name.ilike.%${term}%,phone.ilike.%${term}%,email.ilike.%${term}%`);
      const { data, error } = await query;
      if (error) return json({ error: "query failed" }, 500);
      return json({ clients: data, page: { ...page, returned: data?.length ?? 0 } });
    }

    if (parts[0] === "clients" && parts.length === 2) {
      if (!UUID.test(parts[1])) return json({ error: "bad client id" }, 400);
      const id = parts[1];
      const { data: c } = await sb.from("clients").select(CLIENT_COLS).eq("id", id).maybeSingle();
      if (!c) return json({ error: "client not found" }, 404);
      const [v, r, o, n] = await Promise.all([
        sb.from("visits").select(VISIT_COLS).eq("client_id", id).order("starts_at", { ascending: false }).limit(100),
        sb.from("appointments").select(REQUEST_COLS).eq("client_id", id).order("created_at", { ascending: false }).limit(100),
        sb.from("orders").select(ORDER_COLS).eq("client_id", id).order("created_at", { ascending: false }).limit(100),
        sb.from("agent_notes").select(NOTE_COLS).eq("client_id", id).order("created_at", { ascending: false }).limit(200),
      ]);
      return json({ client: c, visits: v.data ?? [], requests: r.data ?? [], purchase_requests: o.data ?? [], bot_notes: n.data ?? [] });
    }

    if (parts[0] === "requests" && parts.length === 1) {
      let query = sb.from("appointments").select(REQUEST_COLS).order("created_at", { ascending: false }).range(offset, offset + limit - 1);
      if (q.get("status")) query = query.eq("status", q.get("status")!);
      if (q.get("type")) query = query.eq("request_type", q.get("type")!);
      if (q.get("include_training") !== "true") query = query.neq("inquiry_type", "training");
      const since = isoOrNull(q.get("since"));
      if (since) query = query.gte("created_at", since);
      const { data, error } = await query;
      if (error) return json({ error: "query failed" }, 500);
      return json({ requests: data, page: { ...page, returned: data?.length ?? 0 } });
    }

    if (parts[0] === "purchase-requests" && parts.length === 1) {
      let query = sb.from("orders").select(ORDER_COLS).order("created_at", { ascending: false }).range(offset, offset + limit - 1);
      if (q.get("status")) query = query.eq("status", q.get("status")!);
      const since = isoOrNull(q.get("since"));
      if (since) query = query.gte("created_at", since);
      const { data, error } = await query;
      if (error) return json({ error: "query failed" }, 500);
      return json({ purchase_requests: data, page: { ...page, returned: data?.length ?? 0 } });
    }

    if (parts[0] === "visits" && parts.length === 1) {
      let query = sb.from("visits").select(VISIT_COLS).order("starts_at", { ascending: true }).range(offset, offset + limit - 1);
      if (q.get("status")) query = query.eq("status", q.get("status")!);
      if (q.get("client_id")) {
        if (!UUID.test(q.get("client_id")!)) return json({ error: "bad client_id" }, 400);
        query = query.eq("client_id", q.get("client_id")!);
      }
      const from = isoOrNull(q.get("from")) ?? (dateOrNull(q.get("from")) ? q.get("from")! : null);
      const to = isoOrNull(q.get("to")) ?? (dateOrNull(q.get("to")) ? q.get("to")! : null);
      if (from) query = query.gte("starts_at", from);
      if (to) query = query.lt("starts_at", to);
      const { data, error } = await query;
      if (error) return json({ error: "query failed" }, 500);
      return json({ visits: data, page: { ...page, returned: data?.length ?? 0 } });
    }
    return json({ error: "Unknown endpoint" }, 404);
  }

  if (req.method === "POST" && parts[0] === "clients" && parts.length === 3 && parts[2] === "notes") {
    if (!UUID.test(parts[1])) return json({ error: "bad client id" }, 400);
    const b = await req.json().catch(() => null);
    const text = typeof b?.body === "string" ? b.body.trim() : "";
    const category = b?.category ?? "note";
    if (!text) return json({ error: "body is required" }, 400);
    if (text.length > 2000) return json({ error: "body is limited to 2000 characters" }, 400);
    if (!CATEGORIES.includes(category)) return json({ error: "category must be one of: " + CATEGORIES.join(", ") }, 400);
    const { data: c } = await sb.from("clients").select("id").eq("id", parts[1]).maybeSingle();
    if (!c) return json({ error: "client not found" }, 404);
    const { data, error } = await sb.from("agent_notes")
      .insert({ client_id: parts[1], key_id: key.id, agent_label: key.label, category, body: text })
      .select(NOTE_COLS).single();
    if (error) return json({ error: "could not save note" }, 500);
    return json({ note: data }, 201);
  }

  return json({ error: req.method === "GET" ? "Unknown endpoint" : "This key can only read data and add notes" }, req.method === "GET" ? 404 : 405);
}

// ---- entry -------------------------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  const route = url.pathname.replace(/^.*?\/agent-api/, "") || "/";

  // database -> function: send the outbound webhook
  if (route === "/emit") {
    if (req.method !== "POST") return json({ error: "POST only" }, 405);
    const { data: cfg } = await sb.from("private_config").select("hook_secret").eq("id", 1).single();
    const got = req.headers.get("x-hook-secret") || "";
    if (!cfg?.hook_secret || !safeEq(got, cfg.hook_secret)) return json({ error: "forbidden" }, 403);
    const b = await req.json().catch(() => ({}));
    return await handleEmit(String(b.table || ""), String(b.id || ""));
  }

  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim() || (req.headers.get("x-api-key") || "").trim();

  // signed-in owner: send a test event to the saved webhook
  if (route === "/webhook-test") {
    if (req.method !== "POST") return json({ error: "POST only" }, 405);
    const { data: u } = await sb.auth.getUser(bearer);
    if (!u?.user) return json({ error: "Sign in again" }, 401);
    const { data: adm } = await sb.from("admins").select("user_id").eq("user_id", u.user.id).maybeSingle();
    if (!adm) return json({ error: "Owner access required" }, 403);
    const r = await deliver("test.ping", { message: "Test event from Swurl Kurl CRM. If you can read this, the webhook works." }, { force: true });
    return json(r);
  }

  // bot requests
  if (!bearer.startsWith("skb_")) return json({ error: "Missing or invalid API key. Send it as: Authorization: Bearer skb_..." }, 401);
  const hash = await sha256(bearer);
  const { data: key } = await sb.from("agent_keys").select("id,label,revoked_at").eq("key_hash", hash).maybeSingle();
  if (!key || key.revoked_at) return json({ error: "Invalid or revoked API key" }, 401);

  const since = new Date(Date.now() - 60_000).toISOString();
  const { count } = await sb.from("agent_log").select("id", { count: "exact", head: true }).eq("key_id", key.id).gte("created_at", since);
  if ((count ?? 0) >= RATE_PER_MIN) {
    return json({ error: `Rate limit: ${RATE_PER_MIN} requests per minute` }, 429, { "Retry-After": "30" });
  }

  let res: Response;
  try {
    res = await botRoutes(req, url, route, { id: key.id, label: key.label });
  } catch (_e) {
    res = json({ error: "Something went wrong" }, 500);
  }
  // bookkeeping must never break the response
  try {
    await Promise.all([
      sb.from("agent_log").insert({ key_id: key.id, method: req.method, path: route.slice(0, 120), status: res.status }),
      sb.from("agent_keys").update({ last_used_at: new Date().toISOString() }).eq("id", key.id),
    ]);
  } catch (_e) { /* ignore */ }
  return res;
});
