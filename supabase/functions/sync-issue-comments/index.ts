import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

type IssueRow = {
  id: number;
  repository: string | null;
  meta: {
    comments_url?: string;
    [key: string]: unknown;
  } | null;
};

type GitHubComment = {
  id: number;
  body: string | null;
  created_at: string;
  user?: {
    login?: string;
  } | null;
  [key: string]: unknown;
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const githubToken = Deno.env.get("GITHUB_TOKEN");

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
      : null;
    const issueLimit = Math.min(500, Math.max(1, Number(payload?.issue_limit) || 100));
    const commentsPerIssue = Math.min(100, Math.max(1, Number(payload?.comments_per_issue) || 100));
    const issueConcurrency = Math.min(10, Math.max(1, Number(payload?.issue_concurrency) || 5));

    let issueQuery = supabase
      .from("issues")
      .select("id, repository, meta")
      .order("updated_at", { ascending: false })
      .limit(issueLimit);

    if (repository) {
      issueQuery = issueQuery.eq("repository", repository);
    }

    const { data: issues, error: issuesError } = await issueQuery;

    if (issuesError) {
      console.error("Failed to query issues", issuesError);
      return jsonResponse({ error: issuesError.message }, 500);
    }

    const issueRows = (issues ?? []) as IssueRow[];
    const issuesWithCommentsUrl = issueRows.filter((issue) => typeof issue.meta?.comments_url === "string");

    const perIssueResults = await runWithConcurrency(issuesWithCommentsUrl, issueConcurrency, async (issue) => {
      const commentsUrl = new URL(issue.meta!.comments_url as string);
      commentsUrl.searchParams.set("per_page", String(commentsPerIssue));

      const commentsResponse = await fetch(commentsUrl, {
        headers: buildGitHubHeaders(),
      });

      if (!commentsResponse.ok) {
        const details = await commentsResponse.text();
        return {
          issue_id: issue.id,
          ok: false,
          fetched_comments: 0,
          inserted_comments: 0,
          error: `GitHub comments request failed (${commentsResponse.status})`,
          details,
        };
      }

      const comments = (await commentsResponse.json()) as GitHubComment[];

      if (comments.length === 0) {
        return {
          issue_id: issue.id,
          ok: true,
          fetched_comments: 0,
          inserted_comments: 0,
        };
      }

      const records = comments.map((comment) => ({
        id: comment.id,
        repository: issue.repository,
        issue_id: issue.id,
        author: comment.user?.login ?? null,
        body: comment.body,
        posted_at: comment.created_at,
        meta: comment,
      }));

      const { error: upsertError } = await supabase
        .from("issue_comments")
        .upsert(records, { onConflict: "id" });

      if (upsertError) {
        return {
          issue_id: issue.id,
          ok: false,
          fetched_comments: comments.length,
          inserted_comments: 0,
          error: upsertError.message,
        };
      }

      return {
        issue_id: issue.id,
        ok: true,
        fetched_comments: comments.length,
        inserted_comments: comments.length,
      };
    });

    const okResults = perIssueResults.filter((result) => result.ok);
    const failedResults = perIssueResults.filter((result) => !result.ok);

    return jsonResponse({
      repository,
      scanned_issue_count: issueRows.length,
      processed_issue_count: issuesWithCommentsUrl.length,
      skipped_issue_count: issueRows.length - issuesWithCommentsUrl.length,
      issue_success_count: okResults.length,
      issue_failure_count: failedResults.length,
      fetched_comment_count: perIssueResults.reduce((sum, item) => sum + item.fetched_comments, 0),
      inserted_comment_count: perIssueResults.reduce((sum, item) => sum + item.inserted_comments, 0),
      failures: failedResults,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    console.error("Unhandled sync-issue-comments error", error);
    return jsonResponse({ error: message }, 500);
  }
});