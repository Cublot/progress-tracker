import { createClient } from '@supabase/supabase-js';
import { Resend } from 'resend';
import webpush from 'web-push';
import { handleSchedule } from '@vercel/schedules';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { autoRefreshToken: false, persistSession: false } }
);

function escapeHtml(value = '') {
  return String(value).replace(/[&<>"']/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  })[c]);
}

export const POST = handleSchedule(async (metadata) => {
  const required = ['SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY'];
  const missing = required.filter(k => !process.env[k]);
  if (missing.length) return res.status(500).json({ error: `Missing environment variables: ${missing.join(', ')}` });

  const { data: jobs, error } = await supabase.rpc('claim_due_reminders', { p_now: new Date().toISOString() });
  if (error) {
    console.error('Reminder claim failed:', error);
    return res.status(500).json({ error: 'Could not claim reminder jobs' });
  }

  const results = { claimed: jobs?.length || 0, emailSent: 0, pushSent: 0, skipped: 0, failed: 0 };
  const resend = process.env.RESEND_API_KEY ? new Resend(process.env.RESEND_API_KEY) : null;
  const pushReady = process.env.VAPID_PUBLIC_KEY && process.env.VAPID_PRIVATE_KEY && process.env.VAPID_SUBJECT;
  if (pushReady) {
    webpush.setVapidDetails(process.env.VAPID_SUBJECT, process.env.VAPID_PUBLIC_KEY, process.env.VAPID_PRIVATE_KEY);
  }

  for (const job of jobs || []) {
    const filter = {
      user_id: job.user_id,
      local_date: job.local_date,
      local_hour: job.local_hour,
      channel: job.channel
    };
    try {
      if (job.channel === 'email') {
        if (!resend || !process.env.REMINDER_FROM_EMAIL || !job.email) {
          await supabase.from('reminder_delivery_log').update({
            status: 'skipped', last_error: 'Email delivery is not configured.'
          }).match(filter);
          results.skipped++;
          continue;
        }
        const site = process.env.APP_URL || 'https://progress-tracker-navy-tau.vercel.app';
        const { error: sendError } = await resend.emails.send({
          from: process.env.REMINDER_FROM_EMAIL,
          to: [job.email],
          subject: 'Your learning streak is waiting',
          html: `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#18243a;line-height:1.6"><p style="font-weight:700;color:#2868ed">Course Streak</p><h1 style="font-size:26px">A little progress, every day.</h1><p>You haven't logged today's lesson yet. Take a moment to capture one useful thing you learned.</p><p><a href="${escapeHtml(site)}" style="display:inline-block;background:#2868ed;color:white;text-decoration:none;padding:12px 18px;border-radius:10px">Log today's lesson</a></p><p style="font-size:12px;color:#718096">You're receiving this because reminders are enabled in your Course Streak account.</p></div>`
        });
        if (sendError) throw new Error(sendError.message || 'Email provider error');
        await supabase.from('reminder_delivery_log').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }).match(filter);
        results.emailSent++;
      } else if (job.channel === 'push') {
        if (!pushReady) {
          await supabase.from('reminder_delivery_log').update({ status: 'skipped', last_error: 'Web Push is not configured.' }).match(filter);
          results.skipped++;
          continue;
        }
        const { data: subscriptions, error: subError } = await supabase
          .from('push_subscriptions').select('id,endpoint,p256dh,auth_key').eq('user_id', job.user_id);
        if (subError) throw subError;
        if (!subscriptions?.length) {
          await supabase.from('reminder_delivery_log').update({ status: 'skipped', last_error: 'No push subscription is registered.' }).match(filter);
          results.skipped++;
          continue;
        }
        const payload = JSON.stringify({
          title: 'Your learning streak is waiting',
          body: "You haven't logged today's lesson yet. Capture one useful takeaway.",
          url: process.env.APP_URL || 'https://progress-tracker-navy-tau.vercel.app'
        });
        let sent = 0;
        for (const sub of subscriptions) {
          try {
            await webpush.sendNotification({
              endpoint: sub.endpoint,
              keys: { p256dh: sub.p256dh, auth: sub.auth_key }
            }, payload);
            sent++;
          } catch (pushError) {
            if (pushError.statusCode === 404 || pushError.statusCode === 410) {
              await supabase.from('push_subscriptions').delete().eq('id', sub.id);
            } else {
              throw pushError;
            }
          }
        }
        if (!sent) {
          await supabase.from('reminder_delivery_log').update({ status: 'skipped', last_error: 'All push subscriptions were expired.' }).match(filter);
          results.skipped++;
        } else {
          await supabase.from('reminder_delivery_log').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null }).match(filter);
          results.pushSent++;
        }
      }
    } catch (sendError) {
      console.error('Reminder delivery failed:', job.user_id, job.channel, sendError);
      await supabase.from('reminder_delivery_log').update({
        status: 'failed',
        last_error: String(sendError.message || sendError).slice(0, 1000)
      }).match(filter);
      results.failed++;
    }
  }

  console.log('Course Streak reminder run:', JSON.stringify({ schedule: metadata.name, scheduledAt: metadata.scheduledAt, ...results }));
});
