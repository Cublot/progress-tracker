# Course Streak

A learning streak tracker built with HTML, CSS, JavaScript, Supabase, and Vercel.

## Stack

- Static frontend hosted on Vercel
- Supabase Auth + PostgreSQL for accounts and learning history
- Resend for email reminders
- Web Push API + service worker for browser and installed-PWA notifications
- Vercel Schedules for scheduled reminder checks

## Database setup

1. Run `supabase/schema.sql` in the Supabase SQL Editor (already completed for the current project).
2. Run `supabase/reminders.sql` in the Supabase SQL Editor. This is a separate migration for delivery tracking and the secure reminder-claim function.
3. In Supabase Auth → URL Configuration, keep the Vercel production URL as the Site URL and allow the production redirect URL.

The schema uses Row Level Security. User records are scoped to the authenticated owner. Never expose the Supabase service-role key in browser JavaScript.

## Reminder behavior

The initial reminder schedule is 4 PM, 6 PM, 8 PM, and 10 PM in each user's detected IANA timezone. The schedule is fixed for the first release; user-customizable times can be added later.

- The master reminder switch pauses all automated channels.
- Email reminders are opt-in per account.
- Push notifications are opt-in per device/browser.
- A reminder is not sent after a lesson is saved for that user's local calendar date.
- A unique delivery record per user/date/hour/channel prevents duplicate sends if schedule invocations overlap.
- The scheduled worker checks every 15 minutes. The SQL claim function only claims the first 15 minutes of each target hour.

## Vercel environment variables

Configure these in Vercel Project → Settings → Environment Variables. Add them to Production and Preview only as needed, then redeploy.

| Name | Purpose |
|---|---|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Private server-only Supabase service-role key |
| `RESEND_API_KEY` | Private Resend API key |
| `REMINDER_FROM_EMAIL` | Verified Resend sender, e.g. `Course Streak <reminders@yourdomain.com>` |
| `APP_URL` | Production app URL |
| `VAPID_PUBLIC_KEY` | Public Web Push VAPID key |
| `VAPID_PRIVATE_KEY` | Private Web Push VAPID key |
| `VAPID_SUBJECT` | Contact URI, e.g. `mailto:you@yourdomain.com` |

Generate a VAPID key pair locally with:

```bash
npx web-push generate-vapid-keys
```

Store the public and private keys in Vercel. The private key must never be included in frontend code or committed to GitHub. The public key is served to the browser by `/api/push/public-key`.

For email delivery, verify the sender domain with Resend and use the exact verified sender address in `REMINDER_FROM_EMAIL`.

## Vercel Schedules

The project uses Vercel Schedules (the newer scheduling feature) to invoke a private function every 15 minutes. The worker evaluates each user's local time in the database, so the schedule itself runs in UTC.

The Schedules feature is currently in public beta. Ensure it is enabled for the Vercel team before deploying. The Hobby allowance currently includes 5,000 schedule runs/month; a 15-minute schedule uses about 2,880 runs/month. Provider/function usage and email delivery limits still apply.

## iPhone and mobile push

- Android and supported desktop browsers can subscribe to Web Push on HTTPS.
- On iPhone/iPad, the user must add the website to the Home Screen and open the installed web app before enabling push. This is an Apple platform requirement.
- Browser notification permission is per device and can be revoked by the user.
- Push delivery is not a replacement for email; users can enable either channel independently.

## Capacity and launch notes

The database structure is designed for multiple accounts and 2,000 users is a reasonable initial target for this workload, subject to the selected Supabase project's compute, database connection, and usage limits. Notification providers have their own throughput and daily quotas; load-test reminder batches and upgrade provider plans before a public launch at that volume.

The reminder worker currently processes claimed jobs in one invocation. Before a large public launch, add a durable queue/batched sender and provider rate-limit handling so a peak reminder window cannot exceed function duration or email-provider quotas.

## Development status

Implemented in the development branch:
- Supabase account registration, login, and lesson persistence
- Per-user reminder preferences
- Reminder delivery log and atomic claim function
- Scheduled email and Web Push delivery worker
- Push subscription UI and service worker

Still requires external setup and live verification:
- Run `supabase/reminders.sql`
- Configure the Vercel environment variables above
- Verify the sender domain and Resend API key
- Generate VAPID keys and configure Vercel
- Enable Vercel Schedules for the team
- Test email and push on real devices and verify schedule execution logs
