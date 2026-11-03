-- Some bots (e.g. Grok Routines) give you a "sender key" the webhook must present.
-- Optional; owner-only (agent_webhook already has the admin-only policy). Additive.
alter table public.agent_webhook add column if not exists sender_key text;
