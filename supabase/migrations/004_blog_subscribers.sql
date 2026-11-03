-- The Heart of the Matter blog: email subscribers.
-- Public visitors can only call subscribe_blog(); only the owner can read the list (store app, Subscribers tab).
create table if not exists public.blog_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  first_name text,
  source text,
  created_at timestamptz not null default now(),
  unsubscribed_at timestamptz
);
create unique index if not exists blog_subscribers_email_key on public.blog_subscribers (lower(email));
alter table public.blog_subscribers enable row level security;
create policy "admin all" on public.blog_subscribers for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.subscribe_blog(p_email text, p_name text default null, p_source text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_email text := lower(left(trim(coalesce(p_email,'')), 120));
  v_name text := nullif(left(trim(coalesce(p_name,'')), 60), '');
  v_src text := nullif(left(trim(coalesce(p_source,'')), 40), '');
  v_existing public.blog_subscribers%rowtype;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'That email address looks off.';
  end if;
  if (select count(*) from public.blog_subscribers where created_at > now() - interval '1 hour') >= 200 then
    raise exception 'We are getting a lot of sign-ups right now. Please try again in a little while.';
  end if;
  select * into v_existing from public.blog_subscribers where lower(email) = v_email;
  if found then
    if v_existing.unsubscribed_at is not null then
      update public.blog_subscribers set unsubscribed_at = null, first_name = coalesce(v_name, first_name) where id = v_existing.id;
    end if;
    return jsonb_build_object('status','already');
  end if;
  insert into public.blog_subscribers (email, first_name, source) values (v_email, v_name, v_src);
  return jsonb_build_object('status','subscribed');
end $$;

revoke all on function public.subscribe_blog(text,text,text) from public;
grant execute on function public.subscribe_blog(text,text,text) to anon, authenticated;
