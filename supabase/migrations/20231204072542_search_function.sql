create or replace function match_issues (
  query_embedding vector(1536),
  match_threshold float,
  match_count int
)
returns table (
  id bigint,
  issue_id varchar, 
  content text,
  similarity float
)
language sql stable
as $$
  select
    issue_embeds.id,
    issue_embeds.issue_id,
    issues.body as content,
    1 - (issue_embeds.embedding <=> query_embedding) as similarity
  from issue_embeds
  JOIN issues ON issues.id = issue_embeds.issue_id
  where issue_embeds.embedding <=> query_embedding < 1 - match_threshold
  order by issue_embeds.embedding <=> query_embedding
  limit match_count;
$$;

create index on issue_embeds using ivfflat (embedding vector_cosine_ops)
with
  (lists = 247);
--   lists = 4 * sqrt(rows) where rows = 2816

