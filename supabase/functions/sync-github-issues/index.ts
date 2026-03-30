import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

type GitHubIssue = {
  id: number;
  title: string;
  pull_request?: unknown;
  [key: string]: unknown;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const githubToken = Deno.env.get("GITHUB_TOKEN");
const defaultRepository = Deno.env.get("GITHUB_REPOSITORY") ?? "supabase/supabase";
const downstreamFunctionName = Deno.env.get("UPSERT_GITHUB_ISSUE_FUNCTION") ?? "upsert-github-issue";

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders,
  });
}

function buildGitHubHeaders() {
  const headers = new Headers({
    Accept: "application/vnd.github+json",
    "User-Agent": "gaia-supabase-edge-function",
    "X-GitHub-Api-Version": "2022-11-28",
  });

  if (githubToken) {
    headers.set("Authorization", `Bearer ${githubToken}`);
  }

  return headers;
}

async function runWithConcurrency<T, R>(items: T[], limit: number, worker: (item: T) => Promise<R>) {
  const results: R[] = [];

  for (let index = 0; index < items.length; index += limit) {
    const chunk = items.slice(index, index + limit);
    const chunkResults = await Promise.all(chunk.map((item) => worker(item)));
    results.push(...chunkResults);
  }

  return results;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const repository = typeof payload?.repository === "string" && payload.repository.length > 0
      ? payload.repository
      : defaultRepository;
    const state = typeof payload?.state === "string" && payload.state.length > 0 ? payload.state : "all";
    const sort = typeof payload?.sort === "string" && payload.sort.length > 0 ? payload.sort : "updated";
    const direction = typeof payload?.direction === "string" && payload.direction.length > 0
      ? payload.direction
      : "desc";
    const perPage = Math.min(100, Math.max(1, Number(payload?.per_page) || 100));
    const concurrency = Math.min(10, Math.max(1, Number(payload?.concurrency) || 5));

    const githubUrl = new URL(`https://api.github.com/repos/${repository}/issues`);
    githubUrl.searchParams.set("state", state);
    githubUrl.searchParams.set("sort", sort);
    githubUrl.searchParams.set("direction", direction);
    githubUrl.searchParams.set("per_page", String(perPage));

    const githubResponse = await fetch(githubUrl, {
      headers: buildGitHubHeaders(),
    });

    if (!githubResponse.ok) {
      const errorText = await githubResponse.text();
      return jsonResponse(
        {
          error: "GitHub API request failed",
          status: githubResponse.status,
          details: errorText,
        },
        githubResponse.status,
      );
    }

    const rawItems = await githubResponse.json() as GitHubIssue[];
    const issues = rawItems.filter((item) => !item.pull_request);
    const downstreamUrl = `${supabaseUrl}/functions/v1/${downstreamFunctionName}`;

    const results = await runWithConcurrency(issues, concurrency, async (issue) => {
      const response = await fetch(downstreamUrl, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ issue, repository }),
      });

      const body = await response.json().catch(() => null);

      return {
        issueId: issue.id,
        title: issue.title,
        ok: response.ok,
        status: response.status,
        body,
      };
    });

    const succeeded = results.filter((result) => result.ok);
    const failed = results.filter((result) => !result.ok);

    return jsonResponse({
      repository,
      fetched_count: rawItems.length,
      issue_count: issues.length,
      inserted_count: succeeded.length,
      failed_count: failed.length,
      failures: failed,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    console.error("Unhandled sync-github-issues error", error);
    return jsonResponse({ error: message }, 500);
  }
});