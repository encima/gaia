
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_connection_activity') THEN
    PERFORM cron.schedule('cronmon_connection_activity', '*/5 * * * *', 'SELECT cronmon.capture_connection_activity();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_blocking') THEN
    PERFORM cron.schedule('cronmon_blocking', '*/5 * * * *', 'SELECT cronmon.capture_blocking();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_locks') THEN
    PERFORM cron.schedule('cronmon_locks', '*/5 * * * *', 'SELECT cronmon.capture_locks();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_long_running_queries') THEN
    PERFORM cron.schedule('cronmon_long_running_queries', '*/5 * * * *', 'SELECT cronmon.capture_long_running_queries();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_calls') THEN
    PERFORM cron.schedule('cronmon_calls', '*/15 * * * *', 'SELECT cronmon.capture_calls();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_outliers') THEN
    PERFORM cron.schedule('cronmon_outliers', '*/15 * * * *', 'SELECT cronmon.capture_outliers();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_db_stats') THEN
    PERFORM cron.schedule('cronmon_db_stats', '*/15 * * * *', 'SELECT cronmon.capture_db_stats();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_role_stats') THEN
    PERFORM cron.schedule('cronmon_role_stats', '*/15 * * * *', 'SELECT cronmon.capture_role_stats();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_bloat') THEN
    PERFORM cron.schedule('cronmon_bloat', '0 * * * *', 'SELECT cronmon.capture_bloat();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_index_stats') THEN
    PERFORM cron.schedule('cronmon_index_stats', '5 * * * *', 'SELECT cronmon.capture_index_stats();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_table_stats') THEN
    PERFORM cron.schedule('cronmon_table_stats', '10 * * * *', 'SELECT cronmon.capture_table_stats();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_traffic_profile') THEN
    PERFORM cron.schedule('cronmon_traffic_profile', '15 * * * *', 'SELECT cronmon.capture_traffic_profile();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_unused_indexes') THEN
    PERFORM cron.schedule('cronmon_unused_indexes', '20 * * * *', 'SELECT cronmon.capture_unused_indexes();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_vacuum_stats') THEN
    PERFORM cron.schedule('cronmon_vacuum_stats', '25 * * * *', 'SELECT cronmon.capture_vacuum_stats();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_replication_slots') THEN
    PERFORM cron.schedule('cronmon_replication_slots', '30 * * * *', 'SELECT cronmon.capture_replication_slots();');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cronmon_wal_size') THEN
    PERFORM cron.schedule('cronmon_wal_size', '0 * * * *', 'SELECT cronmon.capture_wal_size();');
  END IF;
END;
$$;