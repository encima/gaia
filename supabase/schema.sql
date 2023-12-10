
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "vector" WITH SCHEMA "public";

CREATE OR REPLACE FUNCTION "public"."match_issue_comments"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) RETURNS TABLE("id" bigint, "issue_id" character varying, "title" "text", "content" "text", "url" "text", "issue_comment" "text", "similarity" double precision)
    LANGUAGE "sql" STABLE
    AS $$
  select
    issue_comment_embeds.id as id,
    issue_comment_embeds.issue_id as issue_id,
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

ALTER FUNCTION "public"."match_issue_comments"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."match_issues"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) RETURNS TABLE("id" bigint, "issue_id" character varying, "title" "text", "content" "text", "url" "text", "similarity" double precision)
    LANGUAGE "sql" STABLE
    AS $$
  select
    issue_embeds.id,
    issue_embeds.issue_id,
    issues.title as title,
    issues.body as content,
    issues.url as url,
    1 - (issue_embeds.embedding <=> query_embedding) as similarity
  from issue_embeds
  JOIN issues ON issues.id = issue_embeds.issue_id
  where issue_embeds.embedding <=> query_embedding < 1 - match_threshold
  order by issue_embeds.embedding <=> query_embedding
  limit match_count;
$$;

ALTER FUNCTION "public"."match_issues"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."discussion_comment_embeds" (
    "id" integer NOT NULL,
    "comment_id" character varying,
    "discussion_id" character varying,
    "embedding" "public"."vector"(768)
);

ALTER TABLE "public"."discussion_comment_embeds" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."discussion_comment_embeds_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE "public"."discussion_comment_embeds_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."discussion_comment_embeds_id_seq" OWNED BY "public"."discussion_comment_embeds"."id";

CREATE TABLE IF NOT EXISTS "public"."discussion_comments" (
    "id" character varying NOT NULL,
    "repository" character varying(255),
    "discussion_id" character varying,
    "author" "text",
    "body" "text",
    "created_at" timestamp without time zone,
    "meta" "jsonb"
);

ALTER TABLE "public"."discussion_comments" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."discussion_embeds" (
    "id" integer NOT NULL,
    "discussion_id" character varying,
    "embedding" "public"."vector"(768)
);

ALTER TABLE "public"."discussion_embeds" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."discussion_embeds_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE "public"."discussion_embeds_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."discussion_embeds_id_seq" OWNED BY "public"."discussion_embeds"."id";

CREATE TABLE IF NOT EXISTS "public"."discussions" (
    "id" character varying NOT NULL,
    "repository" character varying(255),
    "discussion_number" integer,
    "title" "text",
    "author" "text",
    "body" "text",
    "created_at" timestamp without time zone,
    "url" "text",
    "meta" "jsonb"
);

ALTER TABLE "public"."discussions" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."issue_comment_embeds" (
    "id" integer NOT NULL,
    "comment_id" character varying,
    "issue_id" character varying,
    "embedding" "public"."vector"(768)
);

ALTER TABLE "public"."issue_comment_embeds" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."issue_comment_embeds_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE "public"."issue_comment_embeds_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."issue_comment_embeds_id_seq" OWNED BY "public"."issue_comment_embeds"."id";

CREATE TABLE IF NOT EXISTS "public"."issue_comments" (
    "id" character varying NOT NULL,
    "repository" character varying(255),
    "issue_id" character varying,
    "author" "text",
    "body" "text",
    "created_at" timestamp without time zone,
    "meta" "jsonb"
);

ALTER TABLE "public"."issue_comments" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."issue_embeds" (
    "id" integer NOT NULL,
    "issue_id" character varying,
    "embedding" "public"."vector"(768)
);

ALTER TABLE "public"."issue_embeds" OWNER TO "postgres";

CREATE SEQUENCE IF NOT EXISTS "public"."issue_embeds_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE "public"."issue_embeds_id_seq" OWNER TO "postgres";

ALTER SEQUENCE "public"."issue_embeds_id_seq" OWNED BY "public"."issue_embeds"."id";

CREATE TABLE IF NOT EXISTS "public"."issues" (
    "id" character varying NOT NULL,
    "issue_number" integer,
    "repository" "text",
    "title" "text",
    "author" "text",
    "body" "text",
    "created_at" timestamp without time zone,
    "closed_at" timestamp without time zone,
    "url" "text",
    "state" "text",
    "meta" "jsonb"
);

ALTER TABLE "public"."issues" OWNER TO "postgres";

ALTER TABLE ONLY "public"."discussion_comment_embeds" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."discussion_comment_embeds_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."discussion_embeds" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."discussion_embeds_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."issue_comment_embeds" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."issue_comment_embeds_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."issue_embeds" ALTER COLUMN "id" SET DEFAULT "nextval"('"public"."issue_embeds_id_seq"'::"regclass");

ALTER TABLE ONLY "public"."discussion_comment_embeds"
    ADD CONSTRAINT "discussion_comment_embeds_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."discussion_comments"
    ADD CONSTRAINT "discussion_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."discussion_embeds"
    ADD CONSTRAINT "discussion_embeds_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."discussions"
    ADD CONSTRAINT "discussions_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."issue_comment_embeds"
    ADD CONSTRAINT "issue_comment_embeds_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."issue_comments"
    ADD CONSTRAINT "issue_comments_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."issue_embeds"
    ADD CONSTRAINT "issue_embeds_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."issues"
    ADD CONSTRAINT "issues_pkey" PRIMARY KEY ("id");

CREATE INDEX "issue_comment_embeds_embedding_idx" ON "public"."issue_comment_embeds" USING "ivfflat" ("embedding" "public"."vector_cosine_ops") WITH ("lists"='468');

CREATE INDEX "issue_embeds_embedding_idx" ON "public"."issue_embeds" USING "ivfflat" ("embedding" "public"."vector_cosine_ops") WITH ("lists"='247');

ALTER TABLE ONLY "public"."discussion_comment_embeds"
    ADD CONSTRAINT "discussion_comment_embeds_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."discussion_comments"("id");

ALTER TABLE ONLY "public"."discussion_comment_embeds"
    ADD CONSTRAINT "discussion_comment_embeds_discussion_id_fkey" FOREIGN KEY ("discussion_id") REFERENCES "public"."discussions"("id");

ALTER TABLE ONLY "public"."discussion_comments"
    ADD CONSTRAINT "discussion_comments_discussion_id_fkey" FOREIGN KEY ("discussion_id") REFERENCES "public"."discussions"("id");

ALTER TABLE ONLY "public"."discussion_embeds"
    ADD CONSTRAINT "discussion_embeds_discussion_id_fkey" FOREIGN KEY ("discussion_id") REFERENCES "public"."discussions"("id");

ALTER TABLE ONLY "public"."issue_comment_embeds"
    ADD CONSTRAINT "issue_comment_embeds_comment_id_fkey" FOREIGN KEY ("comment_id") REFERENCES "public"."issue_comments"("id");

ALTER TABLE ONLY "public"."issue_comment_embeds"
    ADD CONSTRAINT "issue_comment_embeds_issue_id_fkey" FOREIGN KEY ("issue_id") REFERENCES "public"."issues"("id");

ALTER TABLE ONLY "public"."issue_comments"
    ADD CONSTRAINT "issue_comments_issue_id_fkey" FOREIGN KEY ("issue_id") REFERENCES "public"."issues"("id");

ALTER TABLE ONLY "public"."issue_embeds"
    ADD CONSTRAINT "issue_embeds_issue_id_fkey" FOREIGN KEY ("issue_id") REFERENCES "public"."issues"("id");

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_in"("cstring", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_out"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_recv"("internal", "oid", integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_send"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_typmod_in"("cstring"[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(real[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(double precision[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(integer[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."array_to_vector"(numeric[], integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_to_float4"("public"."vector", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector"("public"."vector", integer, boolean) TO "service_role";

GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cosine_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."hnswhandler"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."inner_product"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "postgres";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "anon";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "authenticated";
GRANT ALL ON FUNCTION "public"."ivfflathandler"("internal") TO "service_role";

GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l1_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."l2_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."match_issue_comments"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."match_issue_comments"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_issue_comments"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."match_issues"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."match_issues"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."match_issues"("query_embedding" "public"."vector", "match_threshold" double precision, "match_count" integer) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_accum"(double precision[], "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_add"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_avg"(double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_cmp"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "anon";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_combine"(double precision[], double precision[]) TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_dims"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_eq"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ge"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_gt"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_l2_squared_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_le"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_lt"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_mul"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_ne"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_negative_inner_product"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_norm"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_spherical_distance"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."vector_sub"("public"."vector", "public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."avg"("public"."vector") TO "service_role";

GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "postgres";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "anon";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "authenticated";
GRANT ALL ON FUNCTION "public"."sum"("public"."vector") TO "service_role";

GRANT ALL ON TABLE "public"."discussion_comment_embeds" TO "anon";
GRANT ALL ON TABLE "public"."discussion_comment_embeds" TO "authenticated";
GRANT ALL ON TABLE "public"."discussion_comment_embeds" TO "service_role";

GRANT ALL ON SEQUENCE "public"."discussion_comment_embeds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."discussion_comment_embeds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."discussion_comment_embeds_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."discussion_comments" TO "anon";
GRANT ALL ON TABLE "public"."discussion_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."discussion_comments" TO "service_role";

GRANT ALL ON TABLE "public"."discussion_embeds" TO "anon";
GRANT ALL ON TABLE "public"."discussion_embeds" TO "authenticated";
GRANT ALL ON TABLE "public"."discussion_embeds" TO "service_role";

GRANT ALL ON SEQUENCE "public"."discussion_embeds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."discussion_embeds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."discussion_embeds_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."discussions" TO "anon";
GRANT ALL ON TABLE "public"."discussions" TO "authenticated";
GRANT ALL ON TABLE "public"."discussions" TO "service_role";

GRANT ALL ON TABLE "public"."issue_comment_embeds" TO "anon";
GRANT ALL ON TABLE "public"."issue_comment_embeds" TO "authenticated";
GRANT ALL ON TABLE "public"."issue_comment_embeds" TO "service_role";

GRANT ALL ON SEQUENCE "public"."issue_comment_embeds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."issue_comment_embeds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."issue_comment_embeds_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."issue_comments" TO "anon";
GRANT ALL ON TABLE "public"."issue_comments" TO "authenticated";
GRANT ALL ON TABLE "public"."issue_comments" TO "service_role";

GRANT ALL ON TABLE "public"."issue_embeds" TO "anon";
GRANT ALL ON TABLE "public"."issue_embeds" TO "authenticated";
GRANT ALL ON TABLE "public"."issue_embeds" TO "service_role";

GRANT ALL ON SEQUENCE "public"."issue_embeds_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."issue_embeds_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."issue_embeds_id_seq" TO "service_role";

GRANT ALL ON TABLE "public"."issues" TO "anon";
GRANT ALL ON TABLE "public"."issues" TO "authenticated";
GRANT ALL ON TABLE "public"."issues" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
