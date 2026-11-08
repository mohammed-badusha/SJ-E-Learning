import { authenticatedClient, cors, json } from '../_shared/client.ts';
Deno.serve(async (request) => {
 if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
 if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
 try {
  const client = await authenticatedClient(request);
  // The caller's JWT reaches Postgres. No user ID supplied by the client is trusted.
  const { data, error } = await client.rpc('start_bot_match');
  if (error) return json({ error: error.message }, 409);
  return json(data);
 } catch { return json({ error: 'UNAUTHORIZED' }, 401); }
});
