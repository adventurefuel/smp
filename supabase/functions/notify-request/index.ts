// Sends Web Push alerts to every phone/computer the owner turned alerts on for.
// Called by the database (x-hook-secret) on each new appointment request / purchase
// request, or by a signed-in owner from the dashboard ("Send test alert").
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-hook-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const money = (n: number) => "$" + Number(n).toLocaleString("en-US", { maximumFractionDigits: 2 });
const dayLabel = (d: string | null) =>
  d ? new Date(d + "T12:00:00Z").toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric", timeZone: "UTC" }) : null;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const { data: cfg } = await sb.from("private_config").select("*").eq("id", 1).single();
  if (!cfg?.vapid_private) return json({ error: "Push keys are not configured" }, 500);

  const body = await req.json().catch(() => ({}));
  let payload: Record<string, unknown>;

  if (req.headers.get("x-hook-secret") === cfg.hook_secret) {
    if (body.appointment_id) {
      const { data: a } = await sb.from("appointments")
        .select("code,name,phone,goal,preferred_date,preferred_time,request_type,service_name,option_label,price")
        .eq("id", body.appointment_id).single();
      if (!a) return json({ error: "appointment not found" }, 404);
      const when = [dayLabel(a.preferred_date), a.preferred_time].filter(Boolean).join(" \u00b7 ") || "no date picked";
      const svc = a.service_name ? a.service_name + (a.option_label ? " (" + a.option_label + ")" : "") : null;
      const title = a.request_type === "booking"
        ? `New booking \u00b7 ${svc}${a.price ? " \u00b7 " + money(a.price) : ""}`
        : `New consultation request${svc ? " \u00b7 " + svc : ""}`;
      payload = {
        title,
        body: `${a.name} \u00b7 ${a.phone} \u00b7 ${when}${!svc && a.goal ? " \u00b7 " + a.goal : ""}`,
        tag: a.code, url: "/store.html#appointments",
      };
    } else if (body.order_id) {
      const { data: o } = await sb.from("orders").select("code,name,phone,offer_name,qty,total").eq("id", body.order_id).single();
      if (!o) return json({ error: "order not found" }, 404);
      payload = {
        title: `New purchase request · ${money(o.total)}`,
        body: `${o.name} · ${o.phone} · ${o.qty > 1 ? o.qty + " × " : ""}${o.offer_name}`,
        tag: o.code, url: "/store.html#purchases",
      };
    } else return json({ error: "bad request" }, 400);
  } else {
    const token = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: u } = await sb.auth.getUser(token);
    if (!u?.user) return json({ error: "Sign in again to send a test alert" }, 401);
    const { data: a } = await sb.from("admins").select("user_id").eq("user_id", u.user.id).maybeSingle();
    if (!a) return json({ error: "Owner access required" }, 403);
    payload = {
      title: "Swurl Kurl test alert",
      body: "Phone alerts are on. New appointments and purchases will arrive like this.",
      tag: "test-" + Date.now(), url: "/store.html#appointments",
    };
  }

  webpush.setVapidDetails(cfg.vapid_subject, cfg.vapid_public, cfg.vapid_private);
  const { data: subs } = await sb.from("push_subscriptions").select("id,endpoint,p256dh,auth");
  let sent = 0, removed = 0;
  const failures: unknown[] = [];
  await Promise.all((subs || []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(payload), { TTL: 3600, urgency: "high" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) { await sb.from("push_subscriptions").delete().eq("id", s.id); removed++; }
      else failures.push({ code, msg: String((e as { body?: string }).body || e) });
    }
  }));
  return json({ sent, removed, devices: subs?.length || 0, failures });
});
