import { createClient } from 'npm:@supabase/supabase-js@2';
Deno.serve(async (request) => {
 const secret = Deno.env.get('MATCH_TICK_SECRET');
 if (!secret || request.method !== 'POST' || request.headers.get('Authorization') !== `Bearer ${secret}`) return new Response('Unauthorized', { status: 401 });
 const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
 const { error } = await client.rpc('run_match_tick');
 return new Response(JSON.stringify(error ? { error: 'TICK_FAILED' } : { ok: true }), { status: error ? 500 : 200, headers: { 'Content-Type': 'application/json' } });
});
