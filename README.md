# Progress Tracker

A lightweight learning streak tracker. The current production UI is a static HTML/CSS/JavaScript app; backend integration is being developed on `feature/supabase-foundation`.

## Backend direction

- **Frontend hosting:** Vercel
- **Authentication and database:** Supabase Auth + PostgreSQL
- **Email delivery:** Resend (server-side only)
- **Browser/mobile push:** Web Push API + service worker
- **Scheduled reminders:** Vercel Cron calling a protected server endpoint

## Database setup

1. Create a Supabase project.
2. Open **SQL Editor** in the Supabase dashboard.
3. Run `supabase/schema.sql`.
4. In **Authentication → URL Configuration**, set the production site URL and allowed redirect URLs for your Vercel deployment and local development.
5. In **Project Settings → API**, copy the Project URL and publishable/anon key.

The schema creates:
- `profiles`: timezone and display name
- `lessons`: one lesson per user per local calendar date
- `course_completions`: monthly completion markers
- `reminder_preferences`: per-user reminder schedule and channel preferences
- `push_subscriptions`: browser/device push endpoints

Row Level Security is enabled. User-owned rows are restricted to the authenticated owner. Never put the Supabase service-role key in browser JavaScript.

## Vercel environment variables

The browser app will need:
- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

For a static frontend, Vercel environment variables are not automatically exposed to plain HTML. When the client integration is added, use a small public config module populated with the Supabase project URL and publishable/anon key. These values are designed to be public; database security must come from RLS.

Server-side functions will additionally need private environment variables:
- `SUPABASE_SERVICE_ROLE_KEY` (server only)
- `RESEND_API_KEY` (server only)
- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `CRON_SECRET`

Do not commit real credentials to GitHub.

## Reminder behavior

The intended schedule is 4 PM, 6 PM, 8 PM and 10 PM in each user's saved timezone, stopping once that user's lesson is recorded for the day. A server-side scheduled job is required for reminders when the browser is closed. Browser notifications require permission; iOS web push additionally requires an installed Home Screen web app on supported iOS versions.

## Streak rules

- A day counts when a non-empty lesson is saved for that user's local date.
- At most one lesson record exists per user per date; editing updates that day's note.
- A current streak counts consecutive logged calendar days, allowing the streak to remain current through today or yesterday.
- The browser must not be trusted to assign another user's ID; authenticated database policies enforce ownership.

## Development status

The Supabase schema is the first backend foundation. Authentication UI, Supabase client wiring, serverless reminder endpoints, service worker, email delivery, and end-to-end tests still need to be implemented and configured before launch.
