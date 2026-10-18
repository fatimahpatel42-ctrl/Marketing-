-- ============================================================
-- Marketing Dashboard: password reset
-- Paste into Supabase > SQL Editor > New query, then Run. Safe to run more than once.
-- ============================================================

-- 1. Reset codes. Only managers can create or see them, and a manager
--    can never create one for the owner's login.
create table if not exists public.resets (
  id text primary key,
  data jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now());
alter table public.resets enable row level security;
drop policy if exists resets_read on public.resets;
drop policy if exists resets_add on public.resets;
drop policy if exists resets_delete on public.resets;
drop policy if exists resets_update on public.resets;
create policy resets_read on public.resets for select using (public.is_manager());
create policy resets_add on public.resets for insert with check (
  public.is_manager()
  and (public.is_owner() or not exists (
    select 1 from public.profiles p where lower(p.data->>'username') = lower(resets.data->>'username') and p.data->>'role' = 'owner')));
create policy resets_delete on public.resets for delete using (public.is_manager());
create policy resets_update on public.resets for update using (public.is_manager()) with check (public.is_manager());
grant all on public.resets to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.resets;
exception when others then null;
end $$;

-- 2. Use a reset code to choose a new password (works without being signed in).
--    The code works once, for one username, and expires after 24 hours.
--    Five wrong codes in a row lock resets for that username for an hour.
create or replace function public.reset_password(p_username text, p_code text, p_password text)
returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_user text := lower(trim(p_username));
  v_uid uuid;
  r record;
  fails int;
begin
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'Choose a password of at least 8 characters';
  end if;
  select count(*) into fails from public.resets
    where id like 'FAIL:' || v_user || ':%' and created_at > now() - interval '1 hour';
  if fails >= 5 then
    raise exception 'Too many wrong codes. Try again in an hour or ask for a new code';
  end if;
  select * into r from public.resets
    where id = upper(trim(p_code)) and lower(data->>'username') = v_user
      and coalesce((data->>'used')::boolean, false) = false
      and created_at > now() - interval '24 hours'
    for update;
  if not found then
    insert into public.resets (id, data, created_by)
      values ('FAIL:' || v_user || ':' || gen_random_uuid()::text, jsonb_build_object('username', v_user, 'fail', true), null);
    return false;
  end if;
  select id::uuid into v_uid from public.profiles where lower(data->>'username') = v_user;
  if v_uid is null then
    raise exception 'No login found for that username';
  end if;
  update auth.users set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
    where id = v_uid;
  update public.resets set data = data || jsonb_build_object('used', true, 'usedAt', now()), updated_at = now() where id = r.id;
  delete from public.resets where id like 'FAIL:' || v_user || ':%';
  begin
    delete from auth.sessions where user_id = v_uid;
  exception when others then null;
  end;
  return true;
end $$;
revoke execute on function public.reset_password(text, text, text) from public;
grant execute on function public.reset_password(text, text, text) to anon, authenticated;

-- 3. If the OWNER forgets their password, run this in the SQL Editor
--    (change the code), then use "Forgot password?" with username fatimah and that code:
--
--    insert into public.resets (id, data) values ('OWNR-RSET', '{"username":"fatimah"}');
