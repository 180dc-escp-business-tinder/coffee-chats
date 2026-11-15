-- Coffee Chats: database setup for Supabase
-- Paste this whole file into Supabase > SQL Editor > New query, edit the two admin emails
-- at the bottom, then click Run. Running it again is safe.

-- 1. Tables. Each one holds JSON documents, one row per document.
create table if not exists public.profiles    (id uuid primary key references auth.users(id) on delete cascade, data jsonb not null);
create table if not exists public.private     (id uuid primary key references auth.users(id) on delete cascade, data jsonb not null);
create table if not exists public.inbox       (id uuid primary key references auth.users(id) on delete cascade, data jsonb not null);
create table if not exists public.rounds      (id text primary key, data jsonb not null);
create table if not exists public.public_docs (id text primary key, data jsonb not null);
create table if not exists public.admins      (email text primary key);

-- Signed-in members can reach these tables (the rules in step 4 decide which rows); logged-out visitors can't.
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles, public.private, public.inbox, public.rounds, public.public_docs to authenticated;
grant select on public.admins to authenticated;
revoke all on public.profiles, public.private, public.inbox, public.rounds, public.public_docs, public.admins from anon;

-- 2. Who is who.
create or replace function public.is_180dc() returns boolean
language sql stable as $$
  select coalesce(lower(auth.jwt() ->> 'email') like '%@180dc.org', false)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_180dc() and exists (select 1 from public.admins where email = lower(auth.jwt() ->> 'email'))
$$;
grant execute on function public.is_180dc() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- 3. Only @180dc.org addresses can create an account at all.
create or replace function public.only_180dc_signups() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.email is null or lower(new.email) not like '%@180dc.org' then
    raise exception 'Only @180dc.org email addresses can sign up';
  end if;
  return new;
end $$;
drop trigger if exists only_180dc_signups on auth.users;
create trigger only_180dc_signups before insert on auth.users
  for each row execute function public.only_180dc_signups();

-- 4. Access rules.
alter table public.profiles    enable row level security;
alter table public.private     enable row level security;
alter table public.inbox       enable row level security;
alter table public.rounds      enable row level security;
alter table public.public_docs enable row level security;
alter table public.admins      enable row level security;

-- Profiles (the blind cards): every member reads them, each member writes only their own.
drop policy if exists "members read cards" on public.profiles;
drop policy if exists "add own card" on public.profiles;
drop policy if exists "edit own card" on public.profiles;
drop policy if exists "remove card" on public.profiles;
create policy "members read cards" on public.profiles for select to authenticated using (public.is_180dc());
create policy "add own card"       on public.profiles for insert to authenticated with check (public.is_180dc() and id = auth.uid());
create policy "edit own card"      on public.profiles for update to authenticated using (id = auth.uid()) with check (public.is_180dc() and id = auth.uid());
create policy "remove card"        on public.profiles for delete to authenticated using (id = auth.uid() or public.is_admin());

-- Private info (real name, email, picks, feedback): only the member and P&O.
drop policy if exists "read own private" on public.private;
drop policy if exists "add own private" on public.private;
drop policy if exists "edit own private" on public.private;
drop policy if exists "remove private" on public.private;
create policy "read own private"   on public.private for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "add own private"    on public.private for insert to authenticated with check (public.is_180dc() and id = auth.uid());
create policy "edit own private"   on public.private for update to authenticated using (id = auth.uid()) with check (public.is_180dc() and id = auth.uid());
create policy "remove private"     on public.private for delete to authenticated using (public.is_admin());

-- Inbox (your matches): you read yours, only P&O writes.
drop policy if exists "read own inbox" on public.inbox;
drop policy if exists "P&O writes inbox" on public.inbox;
create policy "read own inbox"     on public.inbox for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "P&O writes inbox"   on public.inbox for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Rounds (full pair lists with real names): P&O only.
drop policy if exists "P&O only rounds" on public.rounds;
create policy "P&O only rounds"    on public.rounds for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Round status and stats: every member reads, only P&O writes.
drop policy if exists "members read public" on public.public_docs;
drop policy if exists "P&O writes public" on public.public_docs;
create policy "members read public" on public.public_docs for select to authenticated using (public.is_180dc());
create policy "P&O writes public"   on public.public_docs for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Admin list: P&O can see it; changes happen only here in the SQL editor.
drop policy if exists "P&O reads admins" on public.admins;
create policy "P&O reads admins"   on public.admins for select to authenticated using (public.is_admin());

-- 5. Live updates (the app refreshes when something changes).
do $$
declare t text;
begin
  foreach t in array array['profiles','private','inbox','rounds','public_docs'] loop
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
       and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- 6. Team and role are private (only you, your matches and P&O see them), so the deck can't read them.
--    This tells a member which people on their own campus are on a different team, without saying which team.
create or replace function public.same_campus_other_teams() returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id
  from public.profiles p
  join public.private v   on v.id = p.id
  join public.profiles mp on mp.id = auth.uid()
  join public.private mv  on mv.id = auth.uid()
  where public.is_180dc()
    and p.id <> auth.uid()
    and p.data->>'campus' = mp.data->>'campus'
    and coalesce(v.data->>'team','') <> ''
    and coalesce(mv.data->>'team','') <> ''
    and v.data->>'team' <> mv.data->>'team'
$$;
revoke execute on function public.same_campus_other_teams() from public, anon;
grant execute on function public.same_campus_other_teams() to authenticated;

-- Older cards kept team and role on the public card. Move them to the private record.
update public.private v
   set data = jsonb_strip_nulls(jsonb_build_object('team', p.data->'team', 'role', p.data->'role')) || v.data
  from public.profiles p
 where p.id = v.id and (p.data ? 'team' or p.data ? 'role');
update public.profiles set data = data - 'team' - 'role' where data ? 'team' or data ? 'role';

-- 7. P&O admins: put the real addresses here (lowercase), then run.
--    To add someone later, run just this line with their address.
insert into public.admins (email) values
  ('your.name@180dc.org'),
  ('gab.surname@180dc.org')
on conflict do nothing;
