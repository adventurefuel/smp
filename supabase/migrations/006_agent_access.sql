-- Bot (agent) access to the CRM: read-only API keys + "add a note" + outbound webhook.
-- Owner-managed from the store app. Additive and DROP-free.
-- The bot never touches the database directly: it calls the `agent-api` edge function,
-- which checks the key, shows only an allowlisted set of fields (no payments, no private notes),
-- and can only ADD notes (stored in agent_notes, never in the owner's private notes).

create table if not exists public.agent_keys (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  label text not null,
  key_prefix text not null,          -- first characters of the key, for recognising it in the list
  key_hash text not null unique,     -- sha256(hex) of the full key; the key itself is never stored
  last_used_at timestamptz,
  revoked_at timestamptz
);

create table if not exists public.agent_notes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client_id uuid not null references public.clients(id) on delete cascade,
  key_id uuid references public.agent_keys(id) on delete set null,
  agent_label text,
  category text not null default 'note'
    check (category in ('note','hesitation','objection','follow_up','outcome')),
  body text not null check (length(body) between 1 and 2000)
);
create index if not exists agent_notes_client_idx on public.agent_notes (client_id, created_at desc);

create table if not exists public.agent_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  key_id uuid references public.agent_keys(id) on delete cascade,
  method text,
  path text,
  status integer
);
create index if not exists agent_log_key_idx on public.agent_log (key_id, created_at desc);

-- one row of outbound-webhook settings
create table if not exists public.agent_webhook (
  id integer primary key default 1 check (id = 1),
  url text,
  secret text,
  enabled boolean not null default false,
  events text[] not null default array['request.created','booking.created','visit.scheduled'],
  last_at timestamptz,
  last_status integer,
  last_error text
);
insert into public.agent_webhook (id) values (1) on conflict (id) do nothing;

-- owner-only access (same gate as the rest of the store app)
alter table public.agent_keys enable row level security;
alter table public.agent_notes enable row level security;
alter table public.agent_log enable row level security;
alter table public.agent_webhook enable row level security;
do $$
declare t text;
begin
  foreach t in array array['agent_keys','agent_notes','agent_log','agent_webhook'] loop
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='admin all') then
      execute format('create policy "admin all" on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    end if;
  end loop;
end $$;
revoke all on public.agent_keys, public.agent_notes, public.agent_log, public.agent_webhook from anon;

-- Tell the agent-api function a new request / purchase / visit exists so it can call the bot's webhook.
-- Never blocks or fails the original insert.
create or replace function private.agent_emit() returns trigger
language plpgsql security definer set search_path to 'public', 'extensions' as $$
declare c public.private_config%rowtype; w public.agent_webhook%rowtype; v_url text;
begin
  begin
    select * into w from public.agent_webhook where id = 1;
    if w.enabled and w.url is not null then
      select * into c from public.private_config where id = 1;
      if c.fn_url is not null then
        v_url := replace(c.fn_url, 'notify-request', 'agent-api/emit');
        perform net.http_post(
          url := v_url,
          body := jsonb_build_object('table', tg_table_name, 'id', new.id),
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret));
      end if;
    end if;
  exception when others then
    null;
  end;
  return new;
end $$;
revoke all on function private.agent_emit() from public, anon, authenticated;

create or replace trigger appointments_agent_emit after insert on public.appointments
  for each row execute function private.agent_emit();
create or replace trigger orders_agent_emit after insert on public.orders
  for each row execute function private.agent_emit();
create or replace trigger visits_agent_emit after insert on public.visits
  for each row execute function private.agent_emit();
