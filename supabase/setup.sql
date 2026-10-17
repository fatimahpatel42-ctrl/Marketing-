-- ============================================================
-- Marketing Dashboard: Supabase setup
-- Paste this whole file into Supabase > SQL Editor > New query, then Run.
-- Safe to run more than once.
-- ============================================================

-- 1. Tables. Each one stores its records as JSON, like the original dashboard.
do $$
declare t text;
begin
  foreach t in array array['profiles','invites','team','inbox','items','approvals','slots','insights','kit','ideas','brands'] loop
    execute format('create table if not exists public.%I (
      id text primary key default replace(gen_random_uuid()::text, ''-'', ''''),
      data jsonb not null default ''{}''::jsonb,
      created_by uuid default auth.uid(),
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now())', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

create index if not exists items_owner_idx on public.items ((data->>'owner'));
create index if not exists inbox_item_idx on public.inbox ((data->>'itemId'));
create index if not exists team_uid_idx on public.team ((data->>'uid'));

-- 2. Who is signed in, and what they're allowed to do.
create or replace function public.my_role() returns text language sql stable security definer set search_path = public as
$$ select data->>'role' from profiles where id = auth.uid()::text $$;
create or replace function public.my_member() returns text language sql stable security definer set search_path = public as
$$ select id from team where data->>'uid' = auth.uid()::text limit 1 $$;
create or replace function public.my_access() returns text language sql stable security definer set search_path = public as
$$ select coalesce(data->>'access','own') from team where data->>'uid' = auth.uid()::text limit 1 $$;
create or replace function public.is_owner() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce(public.my_role() = 'owner', false) $$;
create or replace function public.is_team() returns boolean language sql stable security definer set search_path = public as
$$ select coalesce(public.my_role() in ('owner','team'), false) $$;
create or replace function public.is_manager() returns boolean language sql stable security definer set search_path = public as
$$ select public.is_owner() or (coalesce(public.my_role() = 'team', false) and coalesce(public.my_access() = 'manager', false)) $$;

-- 3. Access rules (row-level security).
do $$
declare r record;
begin
  for r in select policyname, tablename from pg_policies where schemaname = 'public'
    and tablename in ('profiles','invites','team','inbox','items','approvals','slots','insights','kit','ideas','brands') loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- Logins: you see your own; managers see everyone. Only the invite function creates them.
create policy profiles_read on public.profiles for select using (id = auth.uid()::text or public.is_manager());

-- Invite codes: managers only.
create policy invites_all on public.invites for all using (public.is_manager()) with check (public.is_manager());

-- Team list, series, insights, brand kit and rules: the team reads, managers change.
create policy team_read on public.team for select using (public.is_team());
create policy team_write on public.team for all using (public.is_manager()) with check (public.is_manager());
create policy slots_read on public.slots for select using (public.is_team());
create policy slots_write on public.slots for all using (public.is_manager()) with check (public.is_manager());
create policy insights_read on public.insights for select using (public.is_team());
create policy insights_write on public.insights for all using (public.is_manager()) with check (public.is_manager());
create policy kit_read on public.kit for select using (public.is_team());
create policy kit_write on public.kit for all using (public.is_manager()) with check (public.is_manager());
create policy brands_read on public.brands for select using (public.is_team());
create policy brands_write on public.brands for all using (public.is_manager()) with check (public.is_manager());

-- Ideas: anyone on the team adds; managers or the person who added it can change or delete.
create policy ideas_read on public.ideas for select using (public.is_team());
create policy ideas_add on public.ideas for insert with check (public.is_team());
create policy ideas_change on public.ideas for update using (public.is_manager() or created_by = auth.uid());
create policy ideas_delete on public.ideas for delete using (public.is_manager() or created_by = auth.uid());

-- Approvals: only the owner (you) can approve.
create policy approvals_read on public.approvals for select using (public.is_team());
create policy approvals_write on public.approvals for all using (public.is_owner()) with check (public.is_owner());

-- Requests: brands see and reply to their own; managers see all.
create policy inbox_read on public.inbox for select using (public.is_manager() or created_by = auth.uid());
create policy inbox_add on public.inbox for insert with check (auth.uid() is not null and created_by = auth.uid());
create policy inbox_change on public.inbox for update using (public.is_manager() or created_by = auth.uid()) with check (public.is_manager() or created_by = auth.uid());
create policy inbox_delete on public.inbox for delete using (public.is_manager());

-- Work items: managers see everything; editors only what's assigned to them;
-- posters also see approved work; brands see the work for their own requests.
create policy items_read on public.items for select using (
  public.is_manager()
  or data->>'owner' = public.my_member()
  or (public.my_access() = 'poster' and data->>'stage' in ('scheduled','published'))
  or exists (select 1 from public.inbox r where r.data->>'itemId' = items.id and r.created_by = auth.uid()));
create policy items_add on public.items for insert with check (public.is_manager());
create policy items_change on public.items for update
  using (public.is_manager() or data->>'owner' = public.my_member() or (public.my_access() = 'poster' and data->>'stage' in ('scheduled','published')))
  with check (public.is_manager() or data->>'owner' = public.my_member() or (public.my_access() = 'poster' and data->>'stage' in ('scheduled','published')));
create policy items_delete on public.items for delete using (public.is_manager());

-- 4. The approval lock: nothing is scheduled or published without your approval,
--    and editors can't reassign work or move dates.
create or replace function public.items_guard() returns trigger language plpgsql security definer set search_path = public as $$
declare
  os text := coalesce(old.data->>'stage','');
  ns text := coalesce(new.data->>'stage','');
begin
  new.updated_at := now();
  if public.is_owner() then return new; end if;
  if ns <> os and ns in ('scheduled','published') and os <> 'scheduled'
     and not exists (select 1 from public.approvals a where a.id = new.id) then
    raise exception 'Only the approver can schedule or publish this';
  end if;
  if not public.is_manager() then
    if coalesce(new.data->>'owner','') <> coalesce(old.data->>'owner','')
       or coalesce(new.data->>'brand','') <> coalesce(old.data->>'brand','')
       or coalesce(new.data->>'publishDate','') <> coalesce(old.data->>'publishDate','') then
      raise exception 'You can''t change who it''s assigned to, the brand or the go-live date';
    end if;
    if ns <> os and not ((os in ('briefed','production') and ns = 'review') or (os = 'scheduled' and ns = 'published')) then
      raise exception 'You can''t move this item to that stage';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists items_guard on public.items;
create trigger items_guard before update on public.items for each row execute function public.items_guard();

-- 5. Invite codes: check one before sign-up, then claim it once signed in.
create or replace function public.check_invite(p_code text, p_username text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.invites
    where id = upper(trim(p_code)) and lower(data->>'username') = lower(trim(p_username))
      and coalesce((data->>'used')::boolean, false) = false) $$;
grant execute on function public.check_invite(text, text) to anon, authenticated;

create or replace function public.claim_invite(p_code text, p_username text) returns text
language plpgsql security definer set search_path = public as $$
declare inv record;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select * into inv from public.invites
    where id = upper(trim(p_code)) and lower(data->>'username') = lower(trim(p_username))
      and coalesce((data->>'used')::boolean, false) = false
    for update;
  if not found then raise exception 'That invite code isn''t valid'; end if;
  insert into public.profiles (id, data, created_by)
    values (auth.uid()::text, jsonb_strip_nulls(jsonb_build_object('username', lower(trim(p_username)), 'name', inv.data->>'name',
            'role', inv.data->>'role', 'entity', inv.data->>'entity')), auth.uid())
    on conflict (id) do update set data = excluded.data, updated_at = now();
  if inv.data->>'team_id' is not null then
    update public.team set data = data || jsonb_build_object('uid', auth.uid()::text), updated_at = now() where id = inv.data->>'team_id';
  end if;
  update public.invites set data = data || jsonb_build_object('used', true, 'usedBy', auth.uid()::text), updated_at = now() where id = inv.id;
  return inv.data->>'role';
end $$;
revoke execute on function public.claim_invite(text, text) from public, anon;
grant execute on function public.claim_invite(text, text) to authenticated;

-- 6. File storage for designs, videos and the brand kit (private, 50 MB per file).
insert into storage.buckets (id, name, public, file_size_limit)
values ('files', 'files', false, 52428800)
on conflict (id) do update set file_size_limit = excluded.file_size_limit;
drop policy if exists "dashboard files read" on storage.objects;
drop policy if exists "dashboard files upload" on storage.objects;
drop policy if exists "dashboard files delete" on storage.objects;
create policy "dashboard files read" on storage.objects for select to authenticated using (bucket_id = 'files');
create policy "dashboard files upload" on storage.objects for insert to authenticated with check (bucket_id = 'files' and public.is_team());
create policy "dashboard files delete" on storage.objects for delete to authenticated using (bucket_id = 'files' and (public.is_manager() or owner = auth.uid()));

-- 7. Live updates, so changes appear without refreshing.
do $$
declare t text;
begin
  foreach t in array array['profiles','invites','team','inbox','items','approvals','slots','insights','kit','ideas','brands'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;

-- Next: run the private setup snippet Fatimah received separately (owner login and existing data).
