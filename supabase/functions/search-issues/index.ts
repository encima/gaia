import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
const model = new Supabase.ai.Session('gte-small');
const supabase = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders
    });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405
    });
  }
  const { query, match_threshold = 0.7, match_count = 5 } = await req.json();
  if (!query || typeof query !== "string") {
    return new Response("Missing or invalid 'query'", {
      status: 400
    });
  }
  const embedding = await model.run(query, {
    mean_pool: true,
    normalize: true
  });
  // Query embeddings.
  const { data: result, error } = await supabase.rpc('match_issues_with_embedding', {
    match_count: 5,
    match_threshold: 0.8,
    query_embedding: embedding
  });
  if (error) {
    return Response.json(error);
  }
  return Response.json({
    query,
    result
  });
});
