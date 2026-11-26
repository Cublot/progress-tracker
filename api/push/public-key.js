export default function handler(req, res) {
  if (req.method !== 'GET') {
    res.setHeader('Allow', 'GET');
    return res.status(405).json({ error: 'Method not allowed' });
  }
  const key = process.env.VAPID_PUBLIC_KEY;
  if (!key) return res.status(503).json({ error: 'Push notifications are not configured yet.' });
  res.setHeader('Cache-Control', 'public, max-age=3600');
  return res.status(200).json({ publicKey: key });
}
