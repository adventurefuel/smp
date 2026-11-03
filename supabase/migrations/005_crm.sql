-- CRM + appointment schedule for the store app (owner-only; same is_admin() gate as the rest).
-- Additive and DROP-free. New website requests are linked to a client automatically.

create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  name text not null,
  phone text,
  phone_key text,
  email text,
  referred_by text,
  lead_source text,
  stage text not null default 'lead'
    check (stage in ('lead','contacted','consult_booked','session_1','session_2','complete','not_a_fit')),
  package_name text,
  package_price numeric(10,2),
  follow_up_on date,
  follow_up_note text
);
create unique index if not exists clients_phone_key_uq on public.clients (phone_key) where phone_key is not null;
create index if not exists clients_stage_idx on public.clients (stage);
create index if not exists clients_follow_up_idx on public.clients (follow_up_on) where follow_up_on is not null;

create table if not exists public.visits (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null default 'consultation'
    check (kind in ('consultation','session_1','session_2','touch_up','other')),
  starts_at timestamptz not null,
  duration_min integer not null default 60 check (duration_min > 0 and duration_min <= 600),
  status text not null default 'scheduled'
    check (status in ('scheduled','completed','cancelled','no_show')),
  request_id uuid references public.appointments(id) on delete set null,
  notes text
);
create index if not exists visits_starts_idx on public.visits (starts_at);
create index if not exists visits_client_idx on public.visits (client_id);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null default 'payment' check (kind in ('deposit','payment','refund')),
  amount numeric(10,2) not null check (amount > 0),
  method text,
  paid_on date not null default current_date,
  note text
);
create index if not exists payments_client_idx on public.payments (client_id);

create table if not exists public.client_notes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  client_id uuid not null references public.clients(id) on delete cascade,
  kind text not null default 'note' check (kind in ('note','event')),
  body text not null
);
create index if not exists client_notes_client_idx on public.client_notes (client_id, created_at desc);

alter table public.appointments add column if not exists client_id uuid references public.clients(id) on delete set null;
alter table public.orders add column if not exists client_id uuid references public.clients(id) on delete set null;
create index if not exists appointments_client_idx on public.appointments (client_id);
create index if not exists orders_client_idx on public.orders (client_id);

-- keep phone_key (last 10 digits) and updated_at current
create or replace function private.clients_touch() returns trigger
language plpgsql set search_path to 'public' as $$
begin
  new.phone_key := nullif(right(regexp_replace(coalesce(new.phone,''), '\D', '', 'g'), 10), '');
  if length(coalesce(new.phone_key,'')) <> 10 then new.phone_key := null; end if;
  new.updated_at := now();
  return new;
end $$;
create or replace trigger clients_touch before insert or update on public.clients
  for each row execute function private.clients_touch();

-- find-or-create a client by phone; returns the client id
create or replace function private.upsert_client(
  p_name text, p_phone text, p_email text, p_referred_by text, p_lead_source text, p_stage text default 'lead')
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_key text := nullif(right(regexp_replace(coalesce(p_phone,''), '\D', '', 'g'), 10), '');
  v_id uuid;
begin
  if length(coalesce(v_key,'')) = 10 then
    select id into v_id from public.clients where phone_key = v_key;
  end if;
  if v_id is null then
    insert into public.clients (name, phone, email, referred_by, lead_source, stage)
    values (left(trim(p_name), 120), p_phone, nullif(trim(coalesce(p_email,'')), ''),
            nullif(trim(coalesce(p_referred_by,'')), ''), nullif(trim(coalesce(p_lead_source,'')), ''),
            coalesce(p_stage, 'lead'))
    returning id into v_id;
  else
    update public.clients set
      email = coalesce(email, nullif(trim(coalesce(p_email,'')), '')),
      referred_by = coalesce(referred_by, nullif(trim(coalesce(p_referred_by,'')), '')),
      lead_source = coalesce(lead_source, nullif(trim(coalesce(p_lead_source,'')), ''))
    where id = v_id;
  end if;
  return v_id;
end $$;
revoke all on function private.upsert_client(text,text,text,text,text,text) from public, anon, authenticated;

-- new website request -> client (training inquiries stay out of the client list)
create or replace function private.link_request_client() returns trigger
language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid;
begin
  -- Never let CRM bookkeeping block a website request: on any error, the request still saves.
  begin
    if tg_table_name = 'appointments' then
      if new.inquiry_type = 'training' then return new; end if;
      v_id := private.upsert_client(new.name, new.phone, new.email, new.referred_by, new.lead_source, 'lead');
      insert into public.client_notes (client_id, kind, body)
        values (v_id, 'event', 'Request ' || new.code || ' came in' ||
          case when new.request_type = 'booking' then ' (service booking)' else '' end ||
          case when new.source is not null then ' via the ' || new.source else '' end || '.');
    else
      v_id := private.upsert_client(new.name, new.phone, new.email, new.referred_by, null, 'lead');
      insert into public.client_notes (client_id, kind, body)
        values (v_id, 'event', 'Purchase request ' || new.code || ' came in: ' || new.offer_name || ', $' || new.total || '.');
    end if;
    new.client_id := v_id;
  exception when others then
    new.client_id := null;
  end;
  return new;
end $$;
revoke all on function private.link_request_client() from public, anon, authenticated;
create or replace trigger appointments_link_client before insert on public.appointments
  for each row execute function private.link_request_client();
create or replace trigger orders_link_client before insert on public.orders
  for each row execute function private.link_request_client();

-- backfill existing real requests (skips [TEST] rows and training inquiries)
do $$
declare r record; v_id uuid;
begin
  for r in select * from public.appointments
           where client_id is null and inquiry_type = 'client' and name not ilike '[TEST]%'
           order by created_at loop
    v_id := private.upsert_client(r.name, r.phone, r.email, r.referred_by, r.lead_source,
              case r.status when 'new' then 'lead' when 'confirmed' then 'contacted'
                            when 'completed' then 'contacted' else 'not_a_fit' end);
    update public.appointments set client_id = v_id where id = r.id;
    insert into public.client_notes (client_id, kind, body, created_at)
      values (v_id, 'event', 'Request ' || r.code || ' came in (imported).', r.created_at);
  end loop;
  for r in select * from public.orders
           where client_id is null and name not ilike '[TEST]%' order by created_at loop
    v_id := private.upsert_client(r.name, r.phone, r.email, r.referred_by, null, 'lead');
    update public.orders set client_id = v_id where id = r.id;
    insert into public.client_notes (client_id, kind, body, created_at)
      values (v_id, 'event', 'Purchase request ' || r.code || ' came in (imported).', r.created_at);
  end loop;
end $$;

-- owner-only access
alter table public.clients enable row level security;
alter table public.visits enable row level security;
alter table public.payments enable row level security;
alter table public.client_notes enable row level security;
do $$
declare t text;
begin
  foreach t in array array['clients','visits','payments','client_notes'] loop
    if not exists (select 1 from pg_policies where schemaname='public' and tablename=t and policyname='admin all') then
      execute format('create policy "admin all" on public.%I for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()))', t);
    end if;
  end loop;
end $$;
revoke all on public.clients, public.visits, public.payments, public.client_notes from anon;
