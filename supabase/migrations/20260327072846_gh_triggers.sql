CREATE OR REPLACE FUNCTION "public"."gen_embedding_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
DECLARE
    embedding "public"."vector"(384);
BEGIN
RAISE NOTICE 'gen embed for new row : %', NEW.body;
SELECT content::jsonb->'embedding' into embedding
  FROM http((
          'POST',
           'https://qfsrmwxxufryrczocwuj.supabase.co/functions/v1/gen_embed',
           NULL,
           'application/json',
           jsonb_build_object('input', NEW.body)
        )::http_request);
    NEW.embedding := embedding;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."gen_embedding_trigger"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."match_issues_with_embedding"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) RETURNS TABLE("id" bigint, "title" "text", "description" "text", "similarity" double precision)
    LANGUAGE "plpgsql"
    AS $$
begin
  return query
    select
      issues.id,
      issues.title,
      issues.body as description,
      (embedding <#> query_embedding) as similarity
    from issues
    where (embedding <#> query_embedding) <= match_threshold
    order by similarity asc
    limit match_count;
end;
$$;


ALTER FUNCTION "public"."match_issues_with_embedding"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";


CREATE OR REPLACE TRIGGER "comment_embedding_trigger" BEFORE INSERT OR UPDATE ON "public"."issue_comments" FOR EACH ROW EXECUTE FUNCTION "public"."gen_embedding_trigger"();



CREATE OR REPLACE TRIGGER "issue_embedding_trigger" BEFORE INSERT OR UPDATE ON "public"."issues" FOR EACH ROW EXECUTE FUNCTION "public"."gen_embedding_trigger"();



-- CREATE OR REPLACE TRIGGER "embedder" AFTER INSERT ON "public"."issues" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://qfsrmwxxufryrczocwuj.supabase.co/functions/v1/gen_embed', 'POST', '{"Content-type":"application/json"}', '{}', '5000');
