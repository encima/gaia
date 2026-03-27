CREATE OR REPLACE TRIGGER "comment_embedding_trigger" BEFORE INSERT OR UPDATE ON "public"."issue_comments" FOR EACH ROW EXECUTE FUNCTION "public"."gen_embedding_trigger"();

delete from issue_comments;