CREATE OR REPLACE FUNCTION gen_embedding_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
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

CREATE TRIGGER issue_embedding_trigger
BEFORE INSERT OR UPDATE ON issues
FOR EACH ROW
EXECUTE FUNCTION gen_embedding_trigger();

CREATE TRIGGER comment_embedding_trigger
AFTER INSERT OR UPDATE ON issue_comments
FOR EACH ROW
EXECUTE FUNCTION gen_embedding_trigger();
