import { createClient } from 'npm:@supabase/supabase-js@2';
import { authenticatedClient, cors, json } from '../_shared/client.ts';
Deno.serve(async (request) => {
 if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
 if (request.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);
 try {
  const caller = await authenticatedClient(request);
  const { data: { user } } = await caller.auth.getUser();
  if (!user) return json({ error: 'UNAUTHORIZED' }, 401);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
  // Keep anonymous match participants so other learners' history stays consistent.
  const { error: cleanup } = await admin.rpc('anonymize_account', { user_id: user.id });
  if (cleanup) return json({ error: 'CLEANUP_FAILED' }, 500);
  const { error } = await admin.auth.admin.deleteUser(user.id);
  if (error) return json({ error: 'AUTH_DELETE_FAILED_RETRY' }, 500);
  return json({ deleted: true });
 } catch { return json({ error: 'UNAUTHORIZED' }, 401); }
});
