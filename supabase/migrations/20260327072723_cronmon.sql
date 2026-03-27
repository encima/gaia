CREATE SCHEMA IF NOT EXISTS "cronmon";

ALTER SCHEMA "cronmon" OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "cronmon"."check_history" (
    "snapshot_id" bigint NOT NULL,
    "check_name" "text" NOT NULL,
    "sampled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "result_data" "jsonb"
);


ALTER TABLE "cronmon"."check_history" OWNER TO "postgres";


ALTER TABLE "cronmon"."check_history" ALTER COLUMN "snapshot_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "cronmon"."check_history_snapshot_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "cronmon"."connection_activity_history" (
    "snapshot_id" bigint NOT NULL,
    "sampled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "total_backends" integer NOT NULL,
    "active_backends" integer NOT NULL,
    "idle_backends" integer NOT NULL,
    "waiting_backends" integer NOT NULL,
    "app_connections" "jsonb" NOT NULL,
    "backend_user_counts" "jsonb" NOT NULL
);


ALTER TABLE "cronmon"."connection_activity_history" OWNER TO "postgres";


ALTER TABLE "cronmon"."connection_activity_history" ALTER COLUMN "snapshot_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "cronmon"."connection_activity_history_snapshot_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "cronmon"."wal_size_history" (
    "snapshot_id" bigint NOT NULL,
    "sampled_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "wal_size_bytes" bigint NOT NULL,
    "wal_size_pretty" "text" NOT NULL,
    "wal_file_count" integer NOT NULL,
    "growth_bytes" bigint,
    "growth_pretty" "text",
    "growth_rate_mb_per_hour" numeric(10,2)
);


ALTER TABLE "cronmon"."wal_size_history" OWNER TO "postgres";


ALTER TABLE "cronmon"."wal_size_history" ALTER COLUMN "snapshot_id" ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME "cronmon"."wal_size_history_snapshot_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE OR REPLACE FUNCTION "cronmon"."capture_bloat"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'bloat', jsonb_agg(row_to_json(bloat_data)::jsonb)
    from (
        WITH constants AS (
          SELECT current_setting('block_size')::numeric AS bs, 23 AS hdr, 4 AS ma
        ), bloat_info AS (
          SELECT
            ma,bs,schemaname,tablename,
            (datawidth+(hdr+ma-(case when hdr%ma=0 THEN ma ELSE hdr%ma END)))::numeric AS datahdr,
            (maxfracsum*(nullhdr+ma-(case when nullhdr%ma=0 THEN ma ELSE nullhdr%ma END))) AS nullhdr2
          FROM (
            SELECT
              schemaname, tablename, hdr, ma, bs,
              SUM((1-null_frac)*avg_width) AS datawidth,
              MAX(null_frac) AS maxfracsum,
              hdr+(
                SELECT 1+count(*)/8
                FROM pg_stats s2
                WHERE null_frac<>0 AND s2.schemaname = s.schemaname AND s2.tablename = s.tablename
              ) AS nullhdr
            FROM pg_stats s, constants
            GROUP BY 1,2,3,4,5
          ) AS foo
        ), table_bloat AS (
          SELECT
            schemaname, tablename, cc.relpages, bs,
            CEIL((cc.reltuples*((datahdr+ma-
              (CASE WHEN datahdr%ma=0 THEN ma ELSE datahdr%ma END))+nullhdr2+4))/(bs-20::float)) AS otta
          FROM bloat_info
          JOIN pg_class cc ON cc.relname = bloat_info.tablename
          JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = bloat_info.schemaname
          WHERE NOT nn.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ), index_bloat AS (
          SELECT
            schemaname, tablename, bs,
            COALESCE(c2.relname,'?') AS iname, COALESCE(c2.reltuples,0) AS ituples, COALESCE(c2.relpages,0) AS ipages,
            COALESCE(CEIL((c2.reltuples*(datahdr-12))/(bs-20::float)),0) AS iotta
          FROM bloat_info
          JOIN pg_class cc ON cc.relname = bloat_info.tablename
          JOIN pg_namespace nn ON cc.relnamespace = nn.oid AND nn.nspname = bloat_info.schemaname
          JOIN pg_index i ON indrelid = cc.oid
          JOIN pg_class c2 ON c2.oid = i.indexrelid
          WHERE NOT nn.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ), bloat_summary AS (
          SELECT
            'table' as type,
            FORMAT('%I.%I', schemaname, tablename) AS name,
            ROUND(CASE WHEN otta=0 THEN 0.0 ELSE table_bloat.relpages/otta::numeric END,1) AS bloat,
            CASE WHEN relpages < otta THEN 0 ELSE (bs*(table_bloat.relpages-otta)::bigint)::bigint END AS raw_waste
          FROM table_bloat
            UNION
          SELECT
            'index' as type,
            FORMAT('%I.%I::%I', schemaname, tablename, iname) AS name,
            ROUND(CASE WHEN iotta=0 OR ipages=0 THEN 0.0 ELSE ipages/iotta::numeric END,1) AS bloat,
          CASE WHEN ipages < iotta THEN 0 ELSE (bs*(ipages-iotta))::bigint END AS raw_waste
          FROM index_bloat
        )
        SELECT type, name, bloat, pg_size_pretty(raw_waste) as waste
        FROM bloat_summary
        ORDER BY raw_waste DESC, bloat DESC
        LIMIT 100
    ) bloat_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_bloat"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_blocking"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'blocking', jsonb_agg(row_to_json(blocking_data)::jsonb)
    from (
        SELECT
          bl.pid AS blocked_pid,
          ka.query AS blocking_statement,
          age(now(), ka.query_start)::text AS blocking_duration,
          kl.pid AS blocking_pid,
          a.query AS blocked_statement,
          age(now(), a.query_start)::text AS blocked_duration
        FROM pg_catalog.pg_locks bl
        JOIN pg_catalog.pg_stat_activity a
          ON bl.pid = a.pid
        JOIN pg_catalog.pg_locks kl
        JOIN pg_catalog.pg_stat_activity ka
          ON kl.pid = ka.pid
          ON bl.transactionid = kl.transactionid AND bl.pid != kl.pid
        WHERE NOT bl.granted
    ) blocking_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_blocking"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_calls"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'calls', jsonb_agg(row_to_json(calls_data)::jsonb)
    from (
        SELECT
          query,
          (interval '1 millisecond' * total_exec_time)::text AS total_exec_time,
          to_char((total_exec_time/sum(total_exec_time) OVER()) * 100, 'FM90D0') || '%'  AS prop_exec_time,
          to_char(calls, 'FM999G999G990') AS ncalls,
          (
            interval '1 millisecond' * (
              COALESCE(
                (to_jsonb(s) ->> 'shared_blk_read_time')::double precision,
                (to_jsonb(s) ->> 'blk_read_time')::double precision,
                0
              )
              +
              COALESCE(
                (to_jsonb(s) ->> 'shared_blk_write_time')::double precision,
                (to_jsonb(s) ->> 'blk_write_time')::double precision,
                0
              )
            )
          )::text AS sync_io_time
        FROM extensions.pg_stat_statements s
        ORDER BY calls DESC
        LIMIT 10
    ) calls_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_calls"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_connection_activity"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.connection_activity_history (
        total_backends,
        active_backends,
        idle_backends,
        waiting_backends,
        app_connections,
        backend_user_counts
    )
    select
        total_backends,
        active_backends,
        idle_backends,
        waiting_backends,
        app_connections,
        backend_user_counts
    from (
        select
            count(*) as total_backends,
            count(*) filter (where state = 'active') as active_backends,
            count(*) filter (where state = 'idle') as idle_backends,
            count(*) filter (where wait_event_type is not null) as waiting_backends,
            (
                select coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'application_name', coalesce(app.application_name, '<unknown>'),
                            'connections', app.connections
                        )
                        order by coalesce(app.application_name, '<unknown>')
                    ),
                    '[]'::jsonb
                )
                from (
                    select application_name, count(*) as connections
                    from pg_catalog.pg_stat_activity
                    group by application_name
                ) app
            ) as app_connections,
            (
                select coalesce(
                    jsonb_agg(
                        jsonb_build_object(
                            'usename', usr.usename,
                            'connections', usr.connections
                        )
                        order by usr.usename
                    ),
                    '[]'::jsonb
                )
                from (
                    select usename, count(*) as connections
                    from pg_catalog.pg_stat_activity
                    group by usename
                ) usr
            ) as backend_user_counts
        from pg_catalog.pg_stat_activity
    ) snapshot;
end;
$$;


ALTER FUNCTION "cronmon"."capture_connection_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_db_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    db_name text;
begin
    db_name := current_database();

    insert into cronmon.check_history (check_name, result_data)
    select 'db_stats', to_jsonb(db_stats_data)
    from (
        WITH total_objects AS (
          SELECT c.relkind, pg_size_pretty(SUM(pg_relation_size(c.oid))) AS size
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind IN ('i', 'r', 't') AND NOT n.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
          GROUP BY c.relkind
        ), cache_hit AS (
          SELECT
            'i' AS relkind,
            ROUND(SUM(idx_blks_hit)::numeric / nullif(SUM(idx_blks_hit + idx_blks_read), 0), 2) AS ratio
          FROM pg_statio_user_indexes
          WHERE NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
            UNION
          SELECT
            't' AS relkind,
            ROUND(
              (
                SUM(
                  COALESCE(
                    (to_jsonb(s) ->> 'rel_blks_hit')::bigint,
                    (to_jsonb(s) ->> 'heap_blks_hit')::bigint,
                    0
                  )
                )::numeric
                /
                nullif(
                  SUM(
                    COALESCE(
                      (to_jsonb(s) ->> 'rel_blks_hit')::bigint,
                      (to_jsonb(s) ->> 'heap_blks_hit')::bigint,
                      0
                    )
                    +
                    COALESCE(
                      (to_jsonb(s) ->> 'rel_blks_read')::bigint,
                      (to_jsonb(s) ->> 'heap_blks_read')::bigint,
                      0
                    )
                  ),
                  0
                )
              ),
              2
            ) AS ratio
          FROM pg_statio_user_tables s
          WHERE NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        )
        SELECT
          pg_size_pretty(pg_database_size(db_name)) AS database_size,
          COALESCE((SELECT size FROM total_objects WHERE relkind = 'i'), '0 bytes') AS total_index_size,
          COALESCE((SELECT size FROM total_objects WHERE relkind = 'r'), '0 bytes') AS total_table_size,
          COALESCE((SELECT size FROM total_objects WHERE relkind = 't'), '0 bytes') AS total_toast_size,
          COALESCE((SELECT (now() - stats_reset)::text FROM extensions.pg_stat_statements_info), 'N/A') AS time_since_stats_reset,
          (SELECT COALESCE(ratio::text, 'N/A') FROM cache_hit WHERE relkind = 'i') AS index_hit_rate,
          (SELECT COALESCE(ratio::text, 'N/A') FROM cache_hit WHERE relkind = 't') AS table_hit_rate,
          COALESCE((SELECT pg_size_pretty(SUM(size)) FROM pg_ls_waldir()), '0 bytes') AS wal_size
    ) db_stats_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_db_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_index_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'index_stats', jsonb_agg(row_to_json(index_data)::jsonb)
    from (
        WITH idx_sizes AS (
          SELECT
            i.indexrelid AS oid,
            FORMAT('%I.%I', n.nspname, c.relname) AS name,
            pg_relation_size(i.indexrelid) AS index_size_bytes
          FROM pg_stat_user_indexes ui
          JOIN pg_index i ON ui.indexrelid = i.indexrelid
          JOIN pg_class c ON ui.indexrelid = c.oid
          JOIN pg_namespace n ON c.relnamespace = n.oid
          WHERE NOT n.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ),
        idx_usage AS (
          SELECT
            indexrelid AS oid,
            idx_scan::bigint AS idx_scans
          FROM pg_stat_user_indexes ui
          WHERE NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ),
        seq_usage AS (
          SELECT
            relid AS oid,
            seq_scan::bigint AS seq_scans
          FROM pg_stat_user_tables
          WHERE NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ),
        usage_pct AS (
          SELECT
            u.oid,
            CASE
              WHEN u.idx_scans IS NULL OR u.idx_scans = 0 THEN 0
              WHEN s.seq_scans IS NULL THEN 100
              ELSE ROUND(100.0 * u.idx_scans / (s.seq_scans + u.idx_scans), 1)
            END AS percent_used
          FROM idx_usage u
          LEFT JOIN seq_usage s ON s.oid = u.oid
        )
        SELECT
          s.name,
          pg_size_pretty(s.index_size_bytes) AS size,
          COALESCE(up.percent_used, 0)::text || '%' AS percent_used,
          COALESCE(u.idx_scans, 0) AS index_scans,
          COALESCE(sq.seq_scans, 0) AS seq_scans,
          CASE WHEN COALESCE(u.idx_scans, 0) = 0 THEN true ELSE false END AS unused
        FROM idx_sizes s
        LEFT JOIN idx_usage u ON u.oid = s.oid
        LEFT JOIN seq_usage sq ON sq.oid = s.oid
        LEFT JOIN usage_pct up ON up.oid = s.oid
        ORDER BY s.index_size_bytes DESC
        LIMIT 100
    ) index_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_index_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_locks"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'locks', jsonb_agg(row_to_json(locks_data)::jsonb)
    from (
        SELECT
          pg_stat_activity.pid,
          COALESCE(pg_class.relname, 'null') AS relname,
          COALESCE(pg_locks.transactionid::text, 'null') AS transactionid,
          pg_locks.granted,
          pg_stat_activity.query AS stmt,
          age(now(), pg_stat_activity.query_start)::text AS age
        FROM pg_stat_activity, pg_locks LEFT OUTER JOIN pg_class ON (pg_locks.relation = pg_class.oid)
        WHERE pg_stat_activity.query <> '<insufficient privilege>'
        AND pg_locks.pid = pg_stat_activity.pid
        AND pg_locks.mode = 'ExclusiveLock'
        ORDER BY query_start
    ) locks_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_locks"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_long_running_queries"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'long_running_queries', jsonb_agg(row_to_json(query_data)::jsonb)
    from (
        SELECT
          pid,
          age(now(), pg_stat_activity.query_start)::text AS duration,
          query AS query
        FROM
          pg_stat_activity
        WHERE
          pg_stat_activity.query <> ''::text
          AND state <> 'idle'
          AND age(now(), pg_stat_activity.query_start) > interval '5 minutes'
        ORDER BY
          age(now(), pg_stat_activity.query_start) DESC
    ) query_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_long_running_queries"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_outliers"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'outliers', jsonb_agg(row_to_json(outlier_data)::jsonb)
    from (
        SELECT
          (interval '1 millisecond' * total_exec_time)::text AS total_exec_time,
          to_char((total_exec_time/sum(total_exec_time) OVER()) * 100, 'FM90D0') || '%'  AS prop_exec_time,
          to_char(calls, 'FM999G999G999G990') AS ncalls,
          (
            interval '1 millisecond' * (
              COALESCE(
                (to_jsonb(s) ->> 'shared_blk_read_time')::double precision,
                (to_jsonb(s) ->> 'blk_read_time')::double precision,
                0
              )
              +
              COALESCE(
                (to_jsonb(s) ->> 'shared_blk_write_time')::double precision,
                (to_jsonb(s) ->> 'blk_write_time')::double precision,
                0
              )
            )
          )::text AS sync_io_time,
          query
        FROM extensions.pg_stat_statements s WHERE userid = (SELECT usesysid FROM pg_user WHERE usename = current_user LIMIT 1)
        ORDER BY total_exec_time DESC
        LIMIT 10
    ) outlier_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_outliers"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_replication_slots"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'replication_slots', jsonb_agg(row_to_json(slot_data)::jsonb)
    from (
        SELECT
          s.slot_name,
          s.active,
          COALESCE(r.state, 'N/A') as state,
          CASE WHEN r.client_addr IS NULL
            THEN 'N/A'
            ELSE r.client_addr::text
          END replication_client_address,
          GREATEST(0, ROUND((redo_lsn-restart_lsn)/1024/1024/1024, 2)) as replication_lag_gb
        FROM pg_control_checkpoint(), pg_replication_slots s
        LEFT JOIN pg_stat_replication r ON (r.pid = s.active_pid)
    ) slot_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_replication_slots"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_role_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'role_stats', jsonb_agg(row_to_json(role_data)::jsonb)
    from (
        SELECT
          rolname as role_name,
          (
            SELECT
              count(*)
            FROM
              pg_stat_activity
            WHERE
              pg_roles.rolname = pg_stat_activity.usename
          ) AS active_connections,
          CASE WHEN rolconnlimit = -1
            THEN current_setting('max_connections')::int8
            ELSE rolconnlimit
          END AS connection_limit,
          array_to_string(rolconfig, ',', '*') as custom_config
        FROM
          pg_roles
        ORDER BY 1 DESC
    ) role_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_role_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_table_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'table_stats', jsonb_agg(row_to_json(table_data)::jsonb)
    from (
        SELECT
          ts.name,
          pg_size_pretty(ts.table_size_bytes) AS table_size,
          pg_size_pretty(ts.index_size_bytes) AS index_size,
          pg_size_pretty(ts.total_size_bytes) AS total_size,
          COALESCE(rc.estimated_row_count, 0) AS estimated_row_count,
          COALESCE(rc.seq_scans, 0) AS seq_scans
        FROM (
          SELECT
            FORMAT('%I.%I', n.nspname, c.relname) AS name,
            pg_table_size(c.oid) AS table_size_bytes,
            pg_indexes_size(c.oid) AS index_size_bytes,
            pg_total_relation_size(c.oid) AS total_size_bytes
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE NOT n.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
            AND c.relkind = 'r'
        ) ts
        LEFT JOIN (
          SELECT
            FORMAT('%I.%I', schemaname, relname) AS name,
            n_live_tup AS estimated_row_count,
            seq_scan AS seq_scans
          FROM pg_stat_user_tables
          WHERE NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ) rc ON rc.name = ts.name
        ORDER BY ts.total_size_bytes DESC
        LIMIT 100
    ) table_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_table_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_traffic_profile"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'traffic_profile', jsonb_agg(row_to_json(traffic_data)::jsonb)
    from (
        WITH
        ratio_target AS (SELECT 5 AS ratio),
        table_list AS (SELECT
         s.schemaname,
         s.relname AS table_name,
         si.heap_blks_read + si.idx_blks_read AS blocks_read,
        s.n_tup_ins + s.n_tup_upd + s.n_tup_del AS write_tuples,
        relpages * (s.n_tup_ins + s.n_tup_upd + s.n_tup_del ) / (case when reltuples = 0 then 1 else reltuples end) as blocks_write
        FROM
         pg_stat_user_tables AS s
        JOIN pg_statio_user_tables AS si ON s.relid = si.relid
        JOIN pg_class c ON c.oid = s.relid
        WHERE
        (s.n_tup_ins + s.n_tup_upd + s.n_tup_del) > 0
        AND
         (si.heap_blks_read + si.idx_blks_read) > 0
         )
        SELECT
          schemaname,
          table_name,
          blocks_read,
          write_tuples,
          blocks_write,
          CASE
            WHEN blocks_read = 0 and blocks_write = 0 THEN
              'No Activity'
            WHEN blocks_write * ratio > blocks_read THEN
              CASE
                WHEN blocks_read = 0 THEN 'Write-Only'
                ELSE
                  ROUND(blocks_write :: numeric / blocks_read :: numeric, 1)::text || ':1 (Write-Heavy)'
              END
            WHEN blocks_read > blocks_write * ratio THEN
              CASE
                WHEN blocks_write = 0 THEN 'Read-Only'
                ELSE
                  '1:' || ROUND(blocks_read::numeric / blocks_write :: numeric, 1)::text || ' (Read-Heavy)'
              END
            ELSE
              '1:1 (Balanced)'
          END AS activity_ratio
        FROM table_list, ratio_target
        ORDER BY
         (blocks_read + blocks_write) DESC
        LIMIT 100
    ) traffic_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_traffic_profile"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_unused_indexes"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'unused_indexes', jsonb_agg(row_to_json(unused_data)::jsonb)
    from (
        SELECT
          FORMAT('%I.%I', schemaname, relname) AS name,
          indexrelname AS index,
          pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
          idx_scan as index_scans
        FROM pg_stat_user_indexes ui
        JOIN pg_index i ON ui.indexrelid = i.indexrelid
        WHERE
          NOT indisunique AND idx_scan < 50 AND pg_relation_size(relid) > 5 * 8192
          AND NOT schemaname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ORDER BY
          pg_relation_size(i.indexrelid) / nullif(idx_scan, 0) DESC NULLS FIRST,
          pg_relation_size(i.indexrelid) DESC
        LIMIT 50
    ) unused_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_unused_indexes"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_vacuum_stats"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    insert into cronmon.check_history (check_name, result_data)
    select 'vacuum_stats', jsonb_agg(row_to_json(vacuum_data)::jsonb)
    from (
        WITH table_opts AS (
          SELECT
            pg_class.oid, relname, nspname, array_to_string(reloptions, '') AS relopts
          FROM
            pg_class INNER JOIN pg_namespace ns ON relnamespace = ns.oid
        ), vacuum_settings AS (
          SELECT
            oid, relname, nspname,
            CASE
              WHEN relopts LIKE '%autovacuum_vacuum_threshold%'
                THEN substring(relopts, '.*autovacuum_vacuum_threshold=([0-9.]+).*')::integer
                ELSE current_setting('autovacuum_vacuum_threshold')::integer
              END AS autovacuum_vacuum_threshold,
            CASE
              WHEN relopts LIKE '%autovacuum_vacuum_scale_factor%'
                THEN substring(relopts, '.*autovacuum_vacuum_scale_factor=([0-9.]+).*')::real
                ELSE current_setting('autovacuum_vacuum_scale_factor')::real
              END AS autovacuum_vacuum_scale_factor,
            CASE
              WHEN relopts LIKE '%autovacuum_analyze_threshold%'
                THEN substring(relopts, '.*autovacuum_analyze_threshold=([0-9.]+).*')::integer
                ELSE current_setting('autovacuum_analyze_threshold')::integer
              END AS autovacuum_analyze_threshold,
            CASE
              WHEN relopts LIKE '%autovacuum_analyze_scale_factor%'
                THEN substring(relopts, '.*autovacuum_analyze_scale_factor=([0-9.]+).*')::real
                ELSE current_setting('autovacuum_analyze_scale_factor')::real
              END AS autovacuum_analyze_scale_factor
          FROM
            table_opts
        )
        SELECT
          FORMAT('%I.%I', vacuum_settings.nspname, vacuum_settings.relname) AS name,
          coalesce(to_char(psut.last_vacuum, 'YYYY-MM-DD HH24:MI'), '') AS last_vacuum,
          coalesce(to_char(psut.last_autovacuum, 'YYYY-MM-DD HH24:MI'), '') AS last_autovacuum,
          coalesce(to_char(psut.last_analyze, 'YYYY-MM-DD HH24:MI'), '') AS last_analyze,
          coalesce(to_char(psut.last_autoanalyze, 'YYYY-MM-DD HH24:MI'), '') AS last_autoanalyze,
          to_char(pg_class.reltuples, '9G999G999G999') AS rowcount,
          to_char(psut.n_dead_tup, '9G999G999G999') AS dead_rowcount,
          to_char(autovacuum_vacuum_threshold
               + (autovacuum_vacuum_scale_factor::numeric * pg_class.reltuples), '9G999G999G999') AS autovacuum_threshold,
          CASE
            WHEN autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor::numeric * pg_class.reltuples) < psut.n_dead_tup
            THEN 'yes'
            ELSE 'no'
          END AS expect_autovacuum,
          to_char(autovacuum_analyze_threshold
               + (autovacuum_analyze_scale_factor::numeric * pg_class.reltuples), '9G999G999G999') AS autoanalyze_threshold,
          CASE
            WHEN autovacuum_analyze_threshold + (autovacuum_analyze_scale_factor::numeric * pg_class.reltuples) < psut.n_dead_tup
            THEN 'yes'
            ELSE 'no'
          END AS expect_autoanalyze
        FROM
          pg_stat_user_tables psut INNER JOIN pg_class ON psut.relid = pg_class.oid
        INNER JOIN vacuum_settings ON pg_class.oid = vacuum_settings.oid
        WHERE NOT vacuum_settings.nspname LIKE ANY(ARRAY['pg_%', 'information_schema'])
        ORDER BY
          case
            when pg_class.reltuples = -1 then 1
            else 0
          end,
          1
        LIMIT 100
    ) vacuum_data;
end;
$$;


ALTER FUNCTION "cronmon"."capture_vacuum_stats"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."capture_wal_size"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    current_wal_size bigint;
    current_wal_count integer;
    previous_wal_size bigint;
    previous_sampled_at timestamptz;
    wal_growth bigint;
    time_diff_hours numeric;
    growth_rate numeric;
begin
    -- Get current WAL size and file count
    select
        COALESCE(SUM(size), 0),
        COUNT(*)
    into current_wal_size, current_wal_count
    from pg_ls_waldir();

    -- Get the most recent WAL measurement
    select wal_size_bytes, sampled_at
    into previous_wal_size, previous_sampled_at
    from cronmon.wal_size_history
    order by sampled_at desc
    limit 1;

    -- Calculate growth and rate if we have a previous measurement
    if previous_wal_size is not null then
        wal_growth := current_wal_size - previous_wal_size;
        time_diff_hours := extract(epoch from (now() - previous_sampled_at)) / 3600.0;

        -- Calculate MB per hour growth rate
        if time_diff_hours > 0 then
            growth_rate := (wal_growth / 1024.0 / 1024.0) / time_diff_hours;
        else
            growth_rate := 0;
        end if;
    else
        wal_growth := null;
        growth_rate := null;
    end if;

    -- Insert the current measurement
    insert into cronmon.wal_size_history (
        wal_size_bytes,
        wal_size_pretty,
        wal_file_count,
        growth_bytes,
        growth_pretty,
        growth_rate_mb_per_hour
    )
    values (
        current_wal_size,
        pg_size_pretty(current_wal_size),
        current_wal_count,
        wal_growth,
        case when wal_growth is not null then pg_size_pretty(abs(wal_growth)) else null end,
        growth_rate
    );
end;
$$;


ALTER FUNCTION "cronmon"."capture_wal_size"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."generate_report"("p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"(), "p_sections" "text"[] DEFAULT ARRAY['health'::"text", 'connections'::"text", 'performance'::"text", 'storage'::"text"]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    result jsonb;
    section text;
begin
    result := jsonb_build_object(
        'report_metadata', jsonb_build_object(
            'generated_at', now(),
            'period', jsonb_build_object(
                'start', p_start_time,
                'end', p_end_time
            ),
            'sections_included', to_jsonb(p_sections),
            'database', current_database(),
            'version', version()
        )
    );

    -- Add requested sections
    foreach section in array p_sections
    loop
        case section
            when 'health' then
                result := result || jsonb_build_object(
                    'health_summary', cronmon.report_health_summary(p_start_time, p_end_time)
                );
            when 'connections' then
                result := result || jsonb_build_object(
                    'connection_summary', cronmon.report_connection_summary(p_start_time, p_end_time)
                );
            when 'performance' then
                result := result || jsonb_build_object(
                    'performance_summary', cronmon.report_performance_summary(p_start_time, p_end_time)
                );
            when 'storage' then
                result := result || jsonb_build_object(
                    'storage_summary', cronmon.report_storage_summary(p_start_time, p_end_time)
                );
            else
                -- Unknown section, skip
                null;
        end case;
    end loop;

    return result;
end;
$$;


ALTER FUNCTION "cronmon"."generate_report"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_sections" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_check_history"("p_check_name" "text", "p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"(), "p_limit" integer DEFAULT 100) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    return (
        select jsonb_build_object(
            'check_name', p_check_name,
            'period', jsonb_build_object(
                'start', p_start_time,
                'end', p_end_time
            ),
            'snapshot_count', count(*),
            'snapshots', coalesce(
                jsonb_agg(
                    jsonb_build_object(
                        'snapshot_id', snapshot_id,
                        'sampled_at', sampled_at,
                        'result_data', result_data
                    )
                    order by sampled_at desc
                ),
                '[]'::jsonb
            )
        )
        from (
            select snapshot_id, sampled_at, result_data
            from cronmon.check_history
            where check_name = p_check_name
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit p_limit
        ) sub
    );
end;
$$;


ALTER FUNCTION "cronmon"."report_check_history"("p_check_name" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_connection_summary"("p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    result jsonb;
begin
    select jsonb_build_object(
        'period', jsonb_build_object(
            'start', p_start_time,
            'end', p_end_time
        ),
        'snapshot_count', count(*),
        'connection_stats', jsonb_build_object(
            'avg_total_backends', round(avg(total_backends), 1),
            'max_total_backends', max(total_backends),
            'min_total_backends', min(total_backends),
            'avg_active_backends', round(avg(active_backends), 1),
            'max_active_backends', max(active_backends),
            'avg_idle_backends', round(avg(idle_backends), 1),
            'avg_waiting_backends', round(avg(waiting_backends), 1),
            'max_waiting_backends', max(waiting_backends)
        ),
        'latest_snapshot', (
            select jsonb_build_object(
                'sampled_at', sampled_at,
                'total_backends', total_backends,
                'active_backends', active_backends,
                'idle_backends', idle_backends,
                'waiting_backends', waiting_backends,
                'app_connections', app_connections,
                'backend_user_counts', backend_user_counts
            )
            from cronmon.connection_activity_history
            where sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'top_applications', (
            select coalesce(jsonb_agg(app_stats order by total_connections desc), '[]'::jsonb)
            from (
                select
                    app->>'application_name' as application_name,
                    sum((app->>'connections')::int) as total_connections,
                    count(distinct snapshot_id) as snapshots_seen
                from cronmon.connection_activity_history h,
                     jsonb_array_elements(h.app_connections) as app
                where sampled_at between p_start_time and p_end_time
                group by app->>'application_name'
                order by sum((app->>'connections')::int) desc
                limit 10
            ) app_stats
        )
    ) into result
    from cronmon.connection_activity_history
    where sampled_at between p_start_time and p_end_time;

    return coalesce(result, jsonb_build_object(
        'period', jsonb_build_object('start', p_start_time, 'end', p_end_time),
        'snapshot_count', 0,
        'message', 'No data available for the specified time range'
    ));
end;
$$;


ALTER FUNCTION "cronmon"."report_connection_summary"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_data_availability"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
begin
    return jsonb_build_object(
        'generated_at', now(),
        'connection_activity_history', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'oldest_snapshot', min(sampled_at),
                'newest_snapshot', max(sampled_at),
                'data_range_hours', extract(epoch from (max(sampled_at) - min(sampled_at))) / 3600
            )
            from cronmon.connection_activity_history
        ),
        'wal_size_history', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'oldest_snapshot', min(sampled_at),
                'newest_snapshot', max(sampled_at),
                'data_range_hours', extract(epoch from (max(sampled_at) - min(sampled_at))) / 3600
            )
            from cronmon.wal_size_history
        ),
        'check_history', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'oldest_snapshot', min(sampled_at),
                'newest_snapshot', max(sampled_at),
                'data_range_hours', extract(epoch from (max(sampled_at) - min(sampled_at))) / 3600,
                'checks_by_type', (
                    select coalesce(
                        jsonb_object_agg(check_name, cnt),
                        '{}'::jsonb
                    )
                    from (
                        select check_name, count(*) as cnt
                        from cronmon.check_history
                        group by check_name
                        order by check_name
                    ) sub
                )
            )
            from cronmon.check_history
        )
    );
end;
$$;


ALTER FUNCTION "cronmon"."report_data_availability"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_health_summary"("p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    result jsonb;
    alerts jsonb := '[]'::jsonb;
    blocking_count int;
    long_query_count int;
    high_bloat_count int;
    unused_index_count int;
    max_waiting_backends int;
    replication_lag_gb numeric;
    tables_needing_vacuum int;
    latest_db_stats jsonb;
begin
    -- Check for blocking queries
    select count(*)
    into blocking_count
    from cronmon.check_history
    where check_name = 'blocking'
      and sampled_at between p_start_time and p_end_time
      and jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0;

    if blocking_count > 0 then
        alerts := alerts || jsonb_build_object(
            'severity', 'warning',
            'category', 'blocking',
            'message', format('%s snapshots detected blocking queries', blocking_count),
            'recommendation', 'Review blocking queries and consider optimizing long-running transactions'
        );
    end if;

    -- Check for long running queries
    select count(*)
    into long_query_count
    from cronmon.check_history
    where check_name = 'long_running_queries'
      and sampled_at between p_start_time and p_end_time
      and jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0;

    if long_query_count > 0 then
        alerts := alerts || jsonb_build_object(
            'severity', 'warning',
            'category', 'long_queries',
            'message', format('%s snapshots detected queries running longer than 5 minutes', long_query_count),
            'recommendation', 'Review query performance and add appropriate indexes or optimize queries'
        );
    end if;

    -- Check for high bloat
    select count(*)
    into high_bloat_count
    from cronmon.check_history h,
         jsonb_array_elements(h.result_data) as item
    where h.check_name = 'bloat'
      and h.sampled_at between p_start_time and p_end_time
      and (item->>'bloat')::numeric > 2.0
      and h.sampled_at = (
          select max(sampled_at)
          from cronmon.check_history
          where check_name = 'bloat'
            and sampled_at between p_start_time and p_end_time
      );

    if high_bloat_count > 0 then
        alerts := alerts || jsonb_build_object(
            'severity', 'info',
            'category', 'bloat',
            'message', format('%s tables/indexes have bloat ratio > 2.0', high_bloat_count),
            'recommendation', 'Consider running VACUUM FULL or pg_repack on heavily bloated tables'
        );
    end if;

    -- Check for unused indexes
    select coalesce(jsonb_array_length(result_data), 0)
    into unused_index_count
    from cronmon.check_history
    where check_name = 'unused_indexes'
      and sampled_at between p_start_time and p_end_time
    order by sampled_at desc
    limit 1;

    if unused_index_count > 10 then
        alerts := alerts || jsonb_build_object(
            'severity', 'info',
            'category', 'unused_indexes',
            'message', format('%s potentially unused indexes detected', unused_index_count),
            'recommendation', 'Review and consider dropping unused indexes to reduce write overhead and storage'
        );
    end if;

    -- Check for high waiting backends
    select max(waiting_backends)
    into max_waiting_backends
    from cronmon.connection_activity_history
    where sampled_at between p_start_time and p_end_time;

    if max_waiting_backends > 5 then
        alerts := alerts || jsonb_build_object(
            'severity', 'warning',
            'category', 'waiting_backends',
            'message', format('Peak of %s waiting backends detected', max_waiting_backends),
            'recommendation', 'Investigate lock contention and consider connection pooling'
        );
    end if;

    -- Check replication lag
    select max((item->>'replication_lag_gb')::numeric)
    into replication_lag_gb
    from cronmon.check_history h,
         jsonb_array_elements(h.result_data) as item
    where h.check_name = 'replication_slots'
      and h.sampled_at between p_start_time and p_end_time;

    if replication_lag_gb > 1 then
        alerts := alerts || jsonb_build_object(
            'severity', 'critical',
            'category', 'replication_lag',
            'message', format('Replication lag reached %.2f GB', replication_lag_gb),
            'recommendation', 'Check replica health and network connectivity; consider dropping inactive slots'
        );
    end if;

    -- Check for tables needing vacuum
    select count(*)
    into tables_needing_vacuum
    from cronmon.check_history h,
         jsonb_array_elements(h.result_data) as item
    where h.check_name = 'vacuum_stats'
      and h.sampled_at between p_start_time and p_end_time
      and item->>'expect_autovacuum' = 'yes'
      and h.sampled_at = (
          select max(sampled_at)
          from cronmon.check_history
          where check_name = 'vacuum_stats'
            and sampled_at between p_start_time and p_end_time
      );

    if tables_needing_vacuum > 0 then
        alerts := alerts || jsonb_build_object(
            'severity', 'info',
            'category', 'vacuum',
            'message', format('%s tables are waiting for autovacuum', tables_needing_vacuum),
            'recommendation', 'Autovacuum should handle these; if persistent, review autovacuum settings'
        );
    end if;

    -- Check cache hit rates
    select result_data
    into latest_db_stats
    from cronmon.check_history
    where check_name = 'db_stats'
      and sampled_at between p_start_time and p_end_time
    order by sampled_at desc
    limit 1;

    if latest_db_stats is not null then
        if (latest_db_stats->>'table_hit_rate')::numeric < 0.95
           or (latest_db_stats->>'index_hit_rate')::numeric < 0.95 then
            alerts := alerts || jsonb_build_object(
                'severity', 'warning',
                'category', 'cache_hit_rate',
                'message', format('Cache hit rates below 95%% (table: %s, index: %s)',
                    latest_db_stats->>'table_hit_rate',
                    latest_db_stats->>'index_hit_rate'),
                'recommendation', 'Consider increasing shared_buffers or investigating query patterns'
            );
        end if;
    end if;

    -- Build final result
    select jsonb_build_object(
        'period', jsonb_build_object(
            'start', p_start_time,
            'end', p_end_time
        ),
        'generated_at', now(),
        'overall_status', case
            when exists (select 1 from jsonb_array_elements(alerts) a where a->>'severity' = 'critical') then 'critical'
            when exists (select 1 from jsonb_array_elements(alerts) a where a->>'severity' = 'warning') then 'warning'
            when jsonb_array_length(alerts) > 0 then 'info'
            else 'healthy'
        end,
        'alert_count', jsonb_build_object(
            'critical', (select count(*) from jsonb_array_elements(alerts) a where a->>'severity' = 'critical'),
            'warning', (select count(*) from jsonb_array_elements(alerts) a where a->>'severity' = 'warning'),
            'info', (select count(*) from jsonb_array_elements(alerts) a where a->>'severity' = 'info')
        ),
        'alerts', alerts,
        'vacuum_stats', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'tables', result_data
            )
            from cronmon.check_history
            where check_name = 'vacuum_stats'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'replication_slots', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'slots', result_data
            )
            from cronmon.check_history
            where check_name = 'replication_slots'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'role_stats', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'roles', result_data
            )
            from cronmon.check_history
            where check_name = 'role_stats'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'traffic_profile', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'tables', result_data
            )
            from cronmon.check_history
            where check_name = 'traffic_profile'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        )
    ) into result;

    return result;
end;
$$;


ALTER FUNCTION "cronmon"."report_health_summary"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_performance_summary"("p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    result jsonb;
begin
    select jsonb_build_object(
        'period', jsonb_build_object(
            'start', p_start_time,
            'end', p_end_time
        ),
        'blocking_events', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'snapshots_with_blocking', count(*) filter (where jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0),
                'latest_blocking', (
                    select result_data
                    from cronmon.check_history
                    where check_name = 'blocking'
                      and sampled_at between p_start_time and p_end_time
                      and jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0
                    order by sampled_at desc
                    limit 1
                )
            )
            from cronmon.check_history
            where check_name = 'blocking'
              and sampled_at between p_start_time and p_end_time
        ),
        'long_running_queries', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'snapshots_with_long_queries', count(*) filter (where jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0),
                'latest_long_queries', (
                    select result_data
                    from cronmon.check_history
                    where check_name = 'long_running_queries'
                      and sampled_at between p_start_time and p_end_time
                      and jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0
                    order by sampled_at desc
                    limit 1
                )
            )
            from cronmon.check_history
            where check_name = 'long_running_queries'
              and sampled_at between p_start_time and p_end_time
        ),
        'locks', (
            select jsonb_build_object(
                'total_snapshots', count(*),
                'snapshots_with_locks', count(*) filter (where jsonb_array_length(coalesce(result_data, '[]'::jsonb)) > 0),
                'latest_locks', (
                    select result_data
                    from cronmon.check_history
                    where check_name = 'locks'
                      and sampled_at between p_start_time and p_end_time
                    order by sampled_at desc
                    limit 1
                )
            )
            from cronmon.check_history
            where check_name = 'locks'
              and sampled_at between p_start_time and p_end_time
        ),
        'top_queries_by_calls', (
            select result_data
            from cronmon.check_history
            where check_name = 'calls'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'query_outliers', (
            select result_data
            from cronmon.check_history
            where check_name = 'outliers'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        )
    ) into result;

    return coalesce(result, jsonb_build_object(
        'period', jsonb_build_object('start', p_start_time, 'end', p_end_time),
        'message', 'No data available for the specified time range'
    ));
end;
$$;


ALTER FUNCTION "cronmon"."report_performance_summary"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "cronmon"."report_storage_summary"("p_start_time" timestamp with time zone DEFAULT ("now"() - '24:00:00'::interval), "p_end_time" timestamp with time zone DEFAULT "now"()) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'pg_catalog'
    AS $$
declare
    result jsonb;
begin
    select jsonb_build_object(
        'period', jsonb_build_object(
            'start', p_start_time,
            'end', p_end_time
        ),
        'database_stats', (
            select result_data
            from cronmon.check_history
            where check_name = 'db_stats'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'wal_metrics', (
            select jsonb_build_object(
                'snapshot_count', count(*),
                'latest', (
                    select jsonb_build_object(
                        'sampled_at', sampled_at,
                        'wal_size_pretty', wal_size_pretty,
                        'wal_file_count', wal_file_count,
                        'growth_pretty', growth_pretty,
                        'growth_rate_mb_per_hour', growth_rate_mb_per_hour
                    )
                    from cronmon.wal_size_history
                    where sampled_at between p_start_time and p_end_time
                    order by sampled_at desc
                    limit 1
                ),
                'total_growth_bytes', (
                    select sum(growth_bytes) filter (where growth_bytes > 0)
                    from cronmon.wal_size_history
                    where sampled_at between p_start_time and p_end_time
                ),
                'avg_growth_rate_mb_per_hour', (
                    select round(avg(growth_rate_mb_per_hour), 2)
                    from cronmon.wal_size_history
                    where sampled_at between p_start_time and p_end_time
                      and growth_rate_mb_per_hour is not null
                ),
                'max_growth_rate_mb_per_hour', (
                    select max(growth_rate_mb_per_hour)
                    from cronmon.wal_size_history
                    where sampled_at between p_start_time and p_end_time
                )
            )
            from cronmon.wal_size_history
            where sampled_at between p_start_time and p_end_time
        ),
        'bloat', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'top_bloated_objects', result_data
            )
            from cronmon.check_history
            where check_name = 'bloat'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'table_stats', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'top_tables', result_data
            )
            from cronmon.check_history
            where check_name = 'table_stats'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'index_stats', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'top_indexes', result_data
            )
            from cronmon.check_history
            where check_name = 'index_stats'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        ),
        'unused_indexes', (
            select jsonb_build_object(
                'latest_check', sampled_at,
                'unused_indexes', result_data
            )
            from cronmon.check_history
            where check_name = 'unused_indexes'
              and sampled_at between p_start_time and p_end_time
            order by sampled_at desc
            limit 1
        )
    ) into result;

    return coalesce(result, jsonb_build_object(
        'period', jsonb_build_object('start', p_start_time, 'end', p_end_time),
        'message', 'No data available for the specified time range'
    ));
end;
$$;


ALTER FUNCTION "cronmon"."report_storage_summary"("p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone) OWNER TO "postgres";


CREATE INDEX "check_history_check_name_idx" ON "cronmon"."check_history" USING "btree" ("check_name");



CREATE INDEX "check_history_check_name_sampled_at_idx" ON "cronmon"."check_history" USING "btree" ("check_name", "sampled_at" DESC);



CREATE INDEX "check_history_sampled_at_idx" ON "cronmon"."check_history" USING "btree" ("sampled_at");



CREATE INDEX "connection_activity_history_sampled_at_idx" ON "cronmon"."connection_activity_history" USING "btree" ("sampled_at");



CREATE INDEX "wal_size_history_sampled_at_idx" ON "cronmon"."wal_size_history" USING "btree" ("sampled_at");

