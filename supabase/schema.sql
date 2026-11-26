-- Progress Tracker: Supabase database foundation
-- Run in Supabase SQL Editor. All user-owned records are protected by RLS.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  timezone text not null default 'Africa/Lagos',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.lessons (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  lesson_date date not null,
  note text not null check (char_length(trim(note)) between 1 and 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, lesson_date)
);

create index if not exists lessons_user_date_idx
  on public.lessons (user_id, lesson_date desc);

create table if not exists public.course_completions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  completion_month date not null,
  created_at timestamptz not null default now(),
  unique (user_id, completion_month)
);

create table if not exists public.reminder_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  email_enabled boolean not null default false,
  push_enabled boolean not null default false,
  start_hour smallint not null default 16 check (start_hour between 0 and 23),
  end_hour smallint not null default 22 check (end_hour between 0 and 23),
  interval_hours smallint not null default 2 check (interval_hours between 1 and 12),
  timezone text not null default 'Africa/Lagos',
  updated_at timestamptz not null default now(),
  check (end_hour >= start_hour)
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  unique (user_id, endpoint)
);

create index if not exists push_subscriptions_user_idx
  on public.push_subscriptions (user_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists lessons_set_updated_at on public.lessons;
create trigger lessons_set_updated_at before update on public.lessons
for each row execute function public.set_updated_at();

drop trigger if exists reminder_preferences_set_updated_at on public.reminder_preferences;
create trigger reminder_preferences_set_updated_at before update on public.reminder_preferences
for each row execute function public.set_updated_at();

-- Create a profile and default reminder preferences for every new account.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''));

  insert into public.reminder_preferences (user_id)
  values (new.id);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.lessons enable row level security;
alter table public.course_completions enable row level security;
alter table public.reminder_preferences enable row level security;
alter table public.push_subscriptions enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles
for select to authenticated using (auth.uid() = id);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

drop policy if exists "Users manage own lessons" on public.lessons;
create policy "Users manage own lessons" on public.lessons
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own completions" on public.course_completions;
create policy "Users manage own completions" on public.course_completions
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own reminder preferences" on public.reminder_preferences;
create policy "Users manage own reminder preferences" on public.reminder_preferences
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage own push subscriptions" on public.push_subscriptions;
create policy "Users manage own push subscriptions" on public.push_subscriptions
for all to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.lessons to authenticated;
grant select, insert, update, delete on public.course_completions to authenticated;
grant select, insert, update, delete on public.reminder_preferences to authenticated;
grant select, insert, update, delete on public.push_subscriptions to authenticated;
