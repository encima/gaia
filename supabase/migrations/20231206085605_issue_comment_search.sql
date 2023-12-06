create or replace function match_issue_comments (
  query_embedding vector(1536),
  match_threshold float,
  match_count int
)
returns table (
  id bigint,
  issue_id varchar, 
  repository text,
  title text,
  content text,
  url text,
  issue_comment text,
  similarity float
)
language sql stable
as $$
  select
    issue_comment_embeds.id as id,
    issue_comment_embeds.issue_id as issue_id,
    issues.repository as repository,
    issues.title as title,
    issues.body as content,
    issues.url as url,
    issue_comments.body as issue_comment,
    1 - (issue_comment_embeds.embedding <=> query_embedding) as similarity
  from issue_comment_embeds
  JOIN issues ON issues.id = issue_comment_embeds.issue_id
  JOIN issue_comments ON issue_comments.id = issue_comment_embeds.comment_id
  where issue_comment_embeds.embedding <=> query_embedding < 1 - match_threshold
  order by issue_comment_embeds.embedding <=> query_embedding
  limit match_count;
$$;

create index on issue_comment_embeds using ivfflat (embedding vector_cosine_ops)
with
  (lists = 468);
--   lists = 4 * sqrt(rows) where rows = 13701

