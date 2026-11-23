-- Reminder delivery infrastructure (run once in Supabase SQL Editor after schema.sql)
create table if not exists public.reminder_delivery_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  local_date date not null,
  local_hour smallint not null check (local_hour in (16,18,20,22)),
  channel text not null check (channel in ('email','push')),
  status text not null default 'processing' check (status in ('processing','sent','failed','skipped')),
  attempts integer not null default 1,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique (user_id, local_date, local_hour, channel)
);
create index if not exists reminder_delivery_log_user_date_idx
  on public.reminder_delivery_log(user_id, local_date desc);
alter table public.reminder_delivery_log enable row level security;
drop policy if exists "Users read own reminder delivery history" on public.reminder_delivery_log;
create policy "Users read own reminder delivery history" on public.reminder_delivery_log
for select to authenticated using (auth.uid() = user_id);
revoke all on public.reminder_delivery_log from anon, authenticated;
grant select on public.reminder_delivery_log to authenticated;

-- Only the server's service-role client may claim jobs. Each slot/channel is
-- inserted atomically, so overlapping cron invocations cannot double-send.
create or replace function public.claim_due_reminders(p_now timestamptz default now())
returns table (
  user_id uuid,
  email text,
  timezone text,
  local_date date,
  local_hour smallint,
  channel text
)
language sql
security definer
set search_path = ''
as $$
  with eligible as (
    select
      u.id as user_id,
      u.email::text as email,
      coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos') as timezone,
      (p_now at time zone coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos'))::date as local_date,
      extract(hour from (p_now at time zone coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos')))::smallint as local_hour,
      rp.email_enabled,
      rp.push_enabled
    from auth.users u
    join public.profiles p on p.id = u.id
    join public.reminder_preferences rp on rp.user_id = u.id
    where rp.enabled = true
      and (rp.email_enabled = true or rp.push_enabled = true)
      and extract(hour from (p_now at time zone coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos')))::integer in (16,18,20,22)
      and extract(minute from (p_now at time zone coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos')))::integer < 15
      and not exists (
        select 1 from public.lessons l
        where l.user_id = u.id
          and l.lesson_date = (p_now at time zone coalesce(nullif(rp.timezone,''), nullif(p.timezone,''), 'Africa/Lagos'))::date
      )
  ),
  channels as (
    select e.*, c.channel
    from eligible e
    cross join lateral (
      values ('email'::text, e.email_enabled), ('push'::text, e.push_enabled)
    ) as c(channel, enabled)
    where c.enabled = true
  ),
  claimed as (
    insert into public.reminder_delivery_log
      (user_id, local_date, local_hour, channel, status, attempts, updated_at)
    select user_id, local_date, local_hour, channel, 'processing', 1, now()
    from channels
    on conflict (user_id, local_date, local_hour, channel)
    do update set
      status = 'processing',
      attempts = public.reminder_delivery_log.attempts + 1,
      last_error = null,
      updated_at = now()
    where public.reminder_delivery_log.status = 'failed'
       or (public.reminder_delivery_log.status = 'processing'
           and public.reminder_delivery_log.updated_at < now() - interval '10 minutes')
    returning reminder_delivery_log.user_id, reminder_delivery_log.local_date,
              reminder_delivery_log.local_hour, reminder_delivery_log.channel
  )
  select c.user_id, c.email, c.timezone, c.local_date, c.local_hour, c.channel
  from channels c
  join claimed x using (user_id, local_date, local_hour, channel);
$$;
revoke all on function public.claim_due_reminders(timestamptz) from public, anon, authenticated;
grant execute on function public.claim_due_reminders(timestamptz) to service_role;
