-- Barbershop referral program + "learn how to SMP" training inquiries.
-- Additive only: new columns and two new request functions. The older
-- request_appointment / reserve_offer functions are left in place.

alter table public.appointments add column referred_by text;
alter table public.appointments add column inquiry_type text not null default 'client'
  check (inquiry_type in ('client','training'));
alter table public.orders add column referred_by text;

-- Consultation / call-back / training request (used by every form on the site).
create or replace function public.submit_request(
  p_name text, p_phone text, p_email text, p_source text, p_goal text,
  p_contact_pref text, p_best_time text, p_lead_source text, p_date date,
  p_time text, p_notes text, p_referred_by text, p_inquiry text)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare
  v_phone text := public.norm_phone(p_phone);
  v_name text := left(trim(coalesce(p_name,'')), 80);
  v_email text := nullif(left(trim(coalesce(p_email,'')), 120), '');
  v_ref text := nullif(left(trim(coalesce(p_referred_by,'')), 80), '');
  v_inq text := case when p_inquiry = 'training' then 'training' else 'client' end;
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
    raise exception 'Too many requests from this number in the last hour. Please try again later.';
  end if;
  if (select count(*) from public.appointments where created_at > now() - interval '1 hour') >= 100 then
    raise exception 'We are getting a lot of requests right now. Please try again in a little while.';
  end if;

  insert into public.appointments (source, name, phone, email, goal, contact_pref, best_time, lead_source,
                                   preferred_date, preferred_time, notes, referred_by, inquiry_type)
  values (p_source, v_name, v_phone, v_email,
          left(coalesce(p_goal,''),60), left(coalesce(p_contact_pref,''),30), left(coalesce(p_best_time,''),30),
          left(coalesce(p_lead_source,''),40), p_date, p_time,
          nullif(left(trim(coalesce(p_notes,'')), 500), ''), v_ref, v_inq)
  returning * into v_row;
  return jsonb_build_object('code', v_row.code, 'type', v_row.inquiry_type);
end $fn$;

revoke all on function public.submit_request(text,text,text,text,text,text,text,text,date,text,text,text,text) from public;
grant execute on function public.submit_request(text,text,text,text,text,text,text,text,date,text,text,text,text) to anon, authenticated;

-- Package reservation (The Comeback) with the referring barbershop.
create or replace function public.reserve_offer_ref(
  p_offer text, p_qty int, p_name text, p_phone text, p_email text, p_date date, p_notes text, p_referred_by text)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare
  v_phone text := public.norm_phone(p_phone);
  v_name text := left(trim(coalesce(p_name,'')), 80);
  v_email text := nullif(left(trim(coalesce(p_email,'')), 120), '');
  v_ref text := nullif(left(trim(coalesce(p_referred_by,'')), 80), '');
  v_offer public.offers%rowtype;
  v_qty int := greatest(1, least(5, coalesce(p_qty, 1)));
  v_row public.orders%rowtype;
begin
  select * into v_offer from public.offers where id = p_offer and active and kind = 'package' and price > 0;
  if not found then raise exception 'That offer is no longer available.'; end if;
  if length(v_name) < 2 then raise exception 'Add your name.'; end if;
  if v_phone is null then raise exception 'Enter a 10-digit mobile number.'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That email address looks off.'; end if;
  if p_date is not null and (p_date < current_date - 1 or p_date > current_date + 366) then
    raise exception 'Pick a date within the next year.';
  end if;
  if (select count(*) from public.orders where phone = v_phone and created_at > now() - interval '1 hour') >= 3 then
    raise exception 'Too many requests from this number in the last hour. Please try again later.';
  end if;
  if (select count(*) from public.orders where created_at > now() - interval '1 hour') >= 60 then
    raise exception 'We are getting a lot of requests right now. Please try again in a little while.';
  end if;

  insert into public.orders (offer_id, offer_name, qty, unit_price, total, name, phone, email, preferred_date, notes, referred_by)
  values (v_offer.id, v_offer.name, v_qty, v_offer.price, v_offer.price * v_qty, v_name, v_phone, v_email,
          p_date, nullif(left(trim(coalesce(p_notes,'')), 500), ''), v_ref)
  returning * into v_row;
  return jsonb_build_object('code', v_row.code, 'total', v_row.total, 'offer', v_row.offer_name);
end $fn$;

revoke all on function public.reserve_offer_ref(text,int,text,text,text,date,text,text) from public;
grant execute on function public.reserve_offer_ref(text,int,text,text,text,date,text,text) to anon, authenticated;
