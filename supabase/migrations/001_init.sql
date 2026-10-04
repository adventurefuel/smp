-- Swurl Kurl Studios — appointments + purchase requests, owner login, phone push
-- Applies to the dedicated "swurl-kurl" Supabase project.
create extension if not exists pg_net with schema extensions;

-- ---------- helpers ----------
create or replace function public.norm_phone(p text) returns text
language sql immutable set search_path = public as $fn$
  select case when length(d) = 10
    then '(' || substr(d,1,3) || ') ' || substr(d,4,3) || '-' || substr(d,7,4) end
  from (select right(regexp_replace(coalesce(p,''), '\D', '', 'g'), 10) as d) x
$fn$;

-- ---------- tables ----------
create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- One-time setup codes. Whoever signs up and enters an unused code becomes an owner.
create table public.claim_codes (
  code text primary key,
  label text,
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz
);

create table public.offers (
  id text primary key,
  name text not null,
  description text,
  price numeric(10,2) not null check (price >= 0),
  regular_price numeric(10,2),
  active boolean not null default true,
  sort int not null default 0
);

create sequence public.appt_seq start 1001;
create table public.appointments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('SK-A' || nextval('public.appt_seq')),
  created_at timestamptz not null default now(),
  source text not null check (source in ('scheduler','form')),
  name text not null,
  phone text not null,
  email text,
  goal text,
  contact_pref text,
  best_time text,
  lead_source text,
  preferred_date date,
  preferred_time text check (preferred_time in ('Morning','Afternoon','Evening')),
  notes text,
  status text not null default 'new' check (status in ('new','confirmed','completed','cancelled','no_show')),
  admin_notes text
);
create index appointments_created_idx on public.appointments (created_at desc);
create index appointments_status_idx on public.appointments (status);
create index appointments_phone_idx on public.appointments (phone, created_at desc);

create sequence public.order_seq start 1001;
create table public.orders (
  id uuid primary key default gen_random_uuid(),
  code text not null unique default ('SK-P' || nextval('public.order_seq')),
  created_at timestamptz not null default now(),
  offer_id text references public.offers(id) on delete set null,
  offer_name text not null,
  qty int not null default 1 check (qty between 1 and 5),
  unit_price numeric(10,2) not null,
  total numeric(10,2) not null,
  name text not null,
  phone text not null,
  email text,
  preferred_date date,
  notes text,
  status text not null default 'new' check (status in ('new','confirmed','paid','completed','cancelled')),
  paid_at timestamptz,
  admin_notes text
);
create index orders_created_idx on public.orders (created_at desc);
create index orders_status_idx on public.orders (status);
create index orders_phone_idx on public.orders (phone, created_at desc);

create table public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_id uuid references auth.users(id) on delete cascade,
  label text,
  created_at timestamptz not null default now()
);
create index push_user_idx on public.push_subscriptions (user_id);

-- server-only secrets (no RLS policies => only the service role can read)
create table public.private_config (
  id int primary key default 1 check (id = 1),
  vapid_public text, vapid_private text, vapid_subject text,
  hook_secret text not null default encode(extensions.gen_random_bytes(24), 'hex'),
  fn_url text
);

-- ---------- auth helpers ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $fn$
  select exists (select 1 from public.admins where user_id = auth.uid())
$fn$;

create or replace function public.claim_owner(p_code text) returns boolean
language plpgsql volatile security definer set search_path = public as $fn$
declare v_code text := upper(trim(coalesce(p_code, '')));
begin
  if auth.uid() is null then raise exception 'Sign in first.'; end if;
  if exists (select 1 from public.admins where user_id = auth.uid()) then return true; end if;
  update public.claim_codes set used_by = auth.uid(), used_at = now()
    where code = v_code and used_by is null;
  if not found then raise exception 'That setup code is not valid or was already used.'; end if;
  insert into public.admins (user_id) values (auth.uid()) on conflict do nothing;
  return true;
end $fn$;

-- ---------- row level security ----------
alter table public.admins enable row level security;
alter table public.claim_codes enable row level security;
alter table public.offers enable row level security;
alter table public.appointments enable row level security;
alter table public.orders enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.private_config enable row level security;

create policy "admins read self" on public.admins for select to authenticated using (user_id = (select auth.uid()));

create policy "public read active" on public.offers for select to anon, authenticated using (active or (select public.is_admin()));
create policy "admin update" on public.offers for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin insert" on public.offers for insert to authenticated with check ((select public.is_admin()));

create policy "admin all" on public.appointments for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin all" on public.orders for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "admin all" on public.push_subscriptions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- ---------- public request functions (the only way the site writes data) ----------
create or replace function public.request_appointment(
  p_name text, p_phone text, p_email text, p_source text, p_goal text,
  p_contact_pref text, p_best_time text, p_lead_source text,
  p_date date, p_time text, p_notes text)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare
  v_phone text := public.norm_phone(p_phone);
  v_name text := left(trim(coalesce(p_name,'')), 80);
  v_email text := nullif(left(trim(coalesce(p_email,'')), 120), '');
  v_row public.appointments%rowtype;
begin
  if p_source not in ('scheduler','form') then raise exception 'Something went wrong. Please try again.'; end if;
  if length(v_name) < 2 then raise exception 'Add your name.'; end if;
  if v_phone is null then raise exception 'Enter a 10-digit mobile number.'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That email address looks off.'; end if;
  if p_date is not null and (p_date < current_date - 1 or p_date > current_date + 366) then
    raise exception 'Pick a date within the next year.';
  end if;
  if p_time is not null and p_time not in ('Morning','Afternoon','Evening') then p_time := null; end if;
  if (select count(*) from public.appointments where phone = v_phone and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many requests from this number in the last hour. Please message Terrence on WhatsApp.';
  end if;
  if (select count(*) from public.appointments where created_at > now() - interval '1 hour') >= 100 then
    raise exception 'We are getting a lot of requests right now. Please message Terrence on WhatsApp.';
  end if;

  insert into public.appointments (source, name, phone, email, goal, contact_pref, best_time, lead_source,
                                   preferred_date, preferred_time, notes)
  values (p_source, v_name, v_phone, v_email,
          left(coalesce(p_goal,''),60), left(coalesce(p_contact_pref,''),30), left(coalesce(p_best_time,''),30),
          left(coalesce(p_lead_source,''),40), p_date, p_time, nullif(left(trim(coalesce(p_notes,'')), 500), ''))
  returning * into v_row;
  return jsonb_build_object('code', v_row.code);
end $fn$;

create or replace function public.reserve_offer(
  p_offer text, p_qty int, p_name text, p_phone text, p_email text, p_date date, p_notes text)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare
  v_phone text := public.norm_phone(p_phone);
  v_name text := left(trim(coalesce(p_name,'')), 80);
  v_email text := nullif(left(trim(coalesce(p_email,'')), 120), '');
  v_offer public.offers%rowtype;
  v_qty int := greatest(1, least(5, coalesce(p_qty, 1)));
  v_row public.orders%rowtype;
begin
  select * into v_offer from public.offers where id = p_offer and active;
  if not found then raise exception 'That offer is no longer available.'; end if;
  if length(v_name) < 2 then raise exception 'Add your name.'; end if;
  if v_phone is null then raise exception 'Enter a 10-digit mobile number.'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That email address looks off.'; end if;
  if p_date is not null and (p_date < current_date - 1 or p_date > current_date + 366) then
    raise exception 'Pick a date within the next year.';
  end if;
  if (select count(*) from public.orders where phone = v_phone and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Too many requests from this number in the last hour. Please message Terrence on WhatsApp.';
  end if;
  if (select count(*) from public.orders where created_at > now() - interval '1 hour') >= 60 then
    raise exception 'We are getting a lot of requests right now. Please message Terrence on WhatsApp.';
  end if;

  insert into public.orders (offer_id, offer_name, qty, unit_price, total, name, phone, email, preferred_date, notes)
  values (v_offer.id, v_offer.name, v_qty, v_offer.price, v_offer.price * v_qty, v_name, v_phone, v_email,
          p_date, nullif(left(trim(coalesce(p_notes,'')), 500), ''))
  returning * into v_row;
  return jsonb_build_object('code', v_row.code, 'total', v_row.total, 'offer', v_row.offer_name);
end $fn$;

-- ---------- lifecycle ----------
create or replace function public.order_status_change() returns trigger
language plpgsql security definer set search_path = public as $fn$
begin
  if new.status is distinct from old.status and new.status in ('paid','completed') and new.paid_at is null then
    new.paid_at := now();
  end if;
  if new.status in ('new','confirmed','cancelled') then new.paid_at := null; end if;
  return new;
end $fn$;
create trigger orders_status before update on public.orders
  for each row execute function public.order_status_change();

-- ---------- phone push: call the edge function on every new request ----------
create or replace function public.push_hook() returns trigger
language plpgsql security definer set search_path = public, extensions as $fn$
declare c public.private_config%rowtype;
begin
  select * into c from public.private_config where id = 1;
  if c.fn_url is not null then
    perform net.http_post(
      url := c.fn_url,
      body := case when tg_table_name = 'orders' then jsonb_build_object('order_id', new.id)
                   else jsonb_build_object('appointment_id', new.id) end,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-hook-secret', c.hook_secret));
  end if;
  return new;
end $fn$;
create trigger appointments_push after insert on public.appointments
  for each row execute function public.push_hook();
create trigger orders_push after insert on public.orders
  for each row execute function public.push_hook();

-- ---------- grants ----------
revoke all on function public.request_appointment(text,text,text,text,text,text,text,text,date,text,text) from public;
revoke all on function public.reserve_offer(text,int,text,text,text,date,text) from public;
revoke all on function public.claim_owner(text) from public;
revoke all on function public.is_admin() from public;
grant execute on function public.request_appointment(text,text,text,text,text,text,text,text,date,text,text) to anon, authenticated;
grant execute on function public.reserve_offer(text,int,text,text,text,date,text) to anon, authenticated;
grant execute on function public.claim_owner(text) to authenticated;
grant execute on function public.is_admin() to authenticated;

-- ---------- realtime for the dashboard ----------
alter publication supabase_realtime add table public.appointments, public.orders;

-- ---------- starter data ----------
insert into public.offers (id, name, description, price, regular_price, sort) values
  ('comeback', 'The Comeback — 2 SMP Sessions',
   'Two scalp micropigmentation sessions during the 21-day campaign.', 1500, 2000, 1);

-- trigger functions live outside the public API
create schema if not exists private;
alter function public.push_hook() set schema private;
alter function public.order_status_change() set schema private;
