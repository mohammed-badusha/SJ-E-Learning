import { createClient } from 'npm:@supabase/supabase-js@2';
export const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' };
export function json(body: unknown, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } }); }
export async function authenticatedClient(request: Request) {
 const authorization = request.headers.get('Authorization');
 if (!authorization?.startsWith('Bearer ')) throw new Error('UNAUTHORIZED');
 const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
 const { data, error } = await client.auth.getUser();
 if (error || !data.user) throw new Error('UNAUTHORIZED');
 return client;
}
