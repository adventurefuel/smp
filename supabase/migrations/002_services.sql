-- Services catalog (bookings + consultation-only services) and service-aware appointment requests.
-- (Applied to the live project as 002a_services_catalog + 002b_book_service_fn.)

alter table public.offers add column category text not null default 'general';
alter table public.offers add column kind text not null default 'book' check (kind in ('package','book','consult'));
alter table public.offers add column options jsonb not null default '[]'::jsonb;

update public.offers set kind = 'package', category = 'smp', sort = 1 where id = 'comeback';

insert into public.offers (id, name, description, price, regular_price, kind, category, options, sort) values
  ('microblading', 'Eyebrow Precision Microblading', 'Precision-shaped, natural-looking brows.', 325, null, 'book', 'brows', '[]', 2),
  ('haircut', 'Designer Haircut', 'A precision cut tailored to you, from a barber with 25 years behind the chair.', 100, null, 'book', 'grooming', '[]', 3),
  ('massage', 'Massage Therapy', 'Therapeutic massage, booked by the hour.', 70, null, 'book', 'wellness',
     '[{"label":"1 hour","price":70},{"label":"90 minutes","price":100}]', 4),
  ('couples-massage', 'Couples Massage', 'Side-by-side massage for two. 1 hour.', 130, null, 'book', 'wellness',
     '[{"label":"1 hour (for two)","price":130}]', 5),
  ('facials', 'Facials & Exfoliation', 'Pricing is shared during your consultation.', 0, null, 'consult', 'grooming', '[]', 6),
  ('trt', 'TRT Consultation', 'Schedule a consultation to talk through your goals and next steps.', 0, null, 'consult', 'wellness', '[]', 7),
  ('hormone', 'Hormone Therapy', 'Schedule a consultation to talk through your goals and next steps.', 0, null, 'consult', 'wellness', '[]', 8),
  ('weight-loss', 'Weight Loss', 'Schedule a consultation to talk through your goals and next steps.', 0, null, 'consult', 'wellness', '[]', 9),
  ('iv-therapy', 'IV Therapy', 'Schedule a consultation to talk through your goals and next steps.', 0, null, 'consult', 'wellness', '[]', 10);

alter table public.appointments add column service_id text references public.offers(id) on delete set null;
alter table public.appointments add column service_name text;
alter table public.appointments add column option_label text;
alter table public.appointments add column price numeric(10,2);
alter table public.appointments add column request_type text not null default 'consultation'
  check (request_type in ('consultation','booking'));

-- Server-validated service booking: price always comes from the offers table, never the browser.
create or replace function public.book_service(
  p_service text, p_option text, p_name text, p_phone text, p_email text,
  p_date date, p_time text, p_notes text)
returns jsonb language plpgsql volatile security definer set search_path = public as $fn$
declare
  v_phone text := public.norm_phone(p_phone);
  v_name text := left(trim(coalesce(p_name,'')), 80);
  v_email text := nullif(left(trim(coalesce(p_email,'')), 120), '');
  v_offer public.offers%rowtype;
  v_type text := 'consultation';
  v_price numeric := null;
  v_opt text := null;
  v_o jsonb;
  v_row public.appointments%rowtype;
begin
  select * into v_offer from public.offers where id = p_service and active and kind in ('book','consult');
  if not found then raise exception 'That service is not available right now.'; end if;
  if length(v_name) < 2 then raise exception 'Add your name.'; end if;
  if v_phone is null then raise exception 'Enter a 10-digit mobile number.'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That email address looks off.'; end if;
  if p_date is not null and (p_date < current_date - 1 or p_date > current_date + 366) then
    raise exception 'Pick a date within the next year.';
  end if;
  if p_time is not null and p_time not in ('Morning','Afternoon','Evening') then p_time := null; end if;

  if v_offer.kind = 'book' then
    v_type := 'booking';
    if p_date is null or p_time is null then raise exception 'Pick a date and a time for your booking.'; end if;
    if jsonb_array_length(v_offer.options) > 0 then
      select o into v_o from jsonb_array_elements(v_offer.options) o where o->>'label' = p_option limit 1;
      if v_o is null then raise exception 'Pick a duration.'; end if;
      v_opt := v_o->>'label'; v_price := (v_o->>'price')::numeric;
    else
      v_price := v_offer.price;
    end if;
  end if;

  if (select count(*) from public.appointments where phone = v_phone and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many requests from this number in the last hour. Please message Terrence on WhatsApp.';
  end if;
  if (select count(*) from public.appointments where created_at > now() - interval '1 hour') >= 100 then
    raise exception 'We are getting a lot of requests right now. Please message Terrence on WhatsApp.';
  end if;

  insert into public.appointments (source, name, phone, email, preferred_date, preferred_time, notes,
                                   service_id, service_name, option_label, price, request_type)
  values ('scheduler', v_name, v_phone, v_email, p_date, p_time,
          nullif(left(trim(coalesce(p_notes,'')), 500), ''),
          v_offer.id, v_offer.name, v_opt, v_price, v_type)
  returning * into v_row;
  return jsonb_build_object('code', v_row.code, 'type', v_row.request_type, 'service', v_row.service_name, 'price', v_row.price);
end $fn$;

revoke all on function public.book_service(text,text,text,text,text,date,text,text) from public;
grant execute on function public.book_service(text,text,text,text,text,date,text,text) to anon, authenticated;

-- reserve_offer now only accepts package offers (e.g. The Comeback)
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
  select * into v_offer from public.offers where id = p_offer and active and kind = 'package' and price > 0;
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
