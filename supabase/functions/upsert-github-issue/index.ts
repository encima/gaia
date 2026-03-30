import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

type GitHubIssue = {
  id: number;
  title: string;
  body: string | null;
  state: string;
  html_url: string;
  created_at: string;
  closed_at: string | null;
  updated_at: string;
  user?: {
    login?: string;
  } | null;
  repository_url?: string;
  [key: string]: unknown;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

const supabase = createClient(supabaseUrl, serviceRoleKey);

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function deriveRepositoryName(issue: GitHubIssue, explicitRepository?: string | null) {
  if (explicitRepository) {
    return explicitRepository;
  }

  if (!issue.repository_url) {
    return null;
  }

  const match = issue.repository_url.match(/repos\/([^/]+\/[^/]+)$/);
  return match?.[1] ?? null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  try {
    const payload = await req.json();
    const issue = payload?.issue as GitHubIssue | undefined;
    const repository = typeof payload?.repository === "string" ? payload.repository : null;

    if (!issue || typeof issue.id !== "number" || typeof issue.title !== "string") {
      return jsonResponse({ error: "Missing or invalid issue payload" }, 400);
    }

    const resolvedRepository = deriveRepositoryName(issue, repository);

    const { error } = await supabase
      .from("issues")
      .upsert(
        {
          id: issue.id,
          title: issue.title,
          body: typeof issue.body === "string" ? issue.body : null,
          state: issue.state,
          author: issue.user?.login ?? null,
          repository: resolvedRepository,
          url: issue.html_url,
          opened_at: issue.created_at,
          closed_at: issue.closed_at,
          updated_at: issue.updated_at,
          meta: issue,
        },
        { onConflict: "id" },
      );

    if (error) {
      console.error("Failed to upsert issue", error, { issueId: issue.id });
      return jsonResponse({ error: error.message, issueId: issue.id }, 500);
    }

    return jsonResponse({ success: true, issueId: issue.id, repository: resolvedRepository });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    console.error("Unhandled upsert-github-issue error", error);
    return jsonResponse({ error: message }, 500);
  }
});