// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.
// Setup type definitions for built-in Supabase Runtime APIs
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const session = new Supabase.ai.Session("gte-small");
Deno.serve(async (req)=>{
  const { input } = await req.json();
  if (!input || typeof input !== "string") {
    return new Response(JSON.stringify({
      error: "Input must be a string"
    }), {
      status: 400,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
  try {
    const embedding = await session.run(input, {
      mean_pool: true,
      normalize: true
    });
    return new Response(JSON.stringify({
      embedding
    }), {
      headers: {
        "Content-Type": "application/json"
      }
    });
  } catch (error) {
    return new Response(JSON.stringify({
      error: error.message
    }), {
      status: 500,
      headers: {
        "Content-Type": "application/json"
      }
    });
  }
}); 