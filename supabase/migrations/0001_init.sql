-- Stashbar backend schema.
-- Run this once in the Supabase SQL editor (or `supabase db push`).
-- Every table is protected by row-level security: a user can only ever
-- read or write their own rows.

-- ---------------------------------------------------------------------------
-- Links
-- ---------------------------------------------------------------------------
create table if not exists public.links (
  id                uuid primary key,
  user_id           uuid not null default auth.uid() references auth.users (id) on delete cascade,
  url               text not null,
  original_url      text not null,
  title             text not null default '',
  host              text not null default '',
  description       text,
  favicon_url       text,
  og_image_url      text,
  tags              text[] not null default '{}',
  notes             text not null default '',
  is_pinned         boolean not null default false,
  is_archived       boolean not null default false,
  is_deleted        boolean not null default false,   -- tombstone so deletes reach other Macs
  opened_at         timestamptz,
  archived_at       timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(), -- client edit time (last write wins)
  server_updated_at timestamptz not null default now()  -- set by trigger; used as the pull cursor
);

create index if not exists links_user_server_updated_idx
  on public.links (user_id, server_updated_at);

create or replace function public.touch_server_updated_at()
returns trigger language plpgsql as $$
begin
  new.server_updated_at := now();
  return new;
end $$;

drop trigger if exists links_touch on public.links;
create trigger links_touch before insert or update on public.links
  for each row execute function public.touch_server_updated_at();

alter table public.links enable row level security;

drop policy if exists "links: own rows" on public.links;
create policy "links: own rows" on public.links
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Profiles (display name + avatar choice)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id            uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  display_name  text,
  avatar_style  int not null default 0,     -- 0..3 monogram styles
  avatar_path   text,                       -- object path in the `avatars` bucket
  updated_at    timestamptz not null default now()
);

alter table public.profiles enable row level security;

drop policy if exists "profiles: own row" on public.profiles;
create policy "profiles: own row" on public.profiles
  for all using (id = auth.uid()) with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- Devices ("Your Macs" in Settings → Account)
-- ---------------------------------------------------------------------------
create table if not exists public.devices (
  id            uuid primary key,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name          text not null,
  model         text,
  last_seen_at  timestamptz not null default now()
);

alter table public.devices enable row level security;

drop policy if exists "devices: own rows" on public.devices;
create policy "devices: own rows" on public.devices
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Feedback (written by the website form and the app; nobody can read it back
-- through the API — read it in the Supabase dashboard)
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('bug', 'idea', 'question', 'love')),
  message     text not null check (char_length(message) between 1 and 5000),
  email       text check (email is null or char_length(email) <= 320),
  app_info    text check (app_info is null or char_length(app_info) <= 500),
  created_at  timestamptz not null default now()
);

alter table public.feedback enable row level security;

drop policy if exists "feedback: anyone can submit" on public.feedback;
create policy "feedback: anyone can submit" on public.feedback
  for insert to anon, authenticated with check (true);

-- ---------------------------------------------------------------------------
-- Delete account: removes the auth user; links, profile and devices cascade.
-- ---------------------------------------------------------------------------
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not signed in';
  end if;
  -- The app removes the avatar through the Storage API before calling this,
  -- since Supabase blocks direct deletes from storage.objects.
  delete from auth.users where id = uid;
end $$;

revoke all on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;

-- ---------------------------------------------------------------------------
-- Avatar storage: public-read bucket, each user writes only their own folder.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars: owner write" on storage.objects;
create policy "avatars: owner write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars: owner update" on storage.objects;
create policy "avatars: owner update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "avatars: owner delete" on storage.objects;
create policy "avatars: owner delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
