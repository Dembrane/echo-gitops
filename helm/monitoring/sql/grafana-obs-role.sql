-- The dashboard login for Grafana: one role per database, read-only, obs views only.
--
-- Run once per environment, after the echo release that creates the obs schema, with the
-- login that runs the migrations there: the default privileges below belong to the role
-- that runs this, and they cover every view a later migration adds, so this file never has
-- to run twice. Then put host:port, database, user and password in the monitoring secret
-- grafana-obs-db as OBS_<ENV>_DB_HOST, OBS_<ENV>_DB_NAME, OBS_<ENV>_DB_USER and
-- OBS_<ENV>_DB_PASSWORD.
--
-- Replace <password> before running. Never commit the password.

create role grafana_obs login password '<password>';
alter role grafana_obs set statement_timeout = '30s';
alter role grafana_obs set default_transaction_read_only = on;
alter role grafana_obs set search_path = obs;

grant usage on schema obs to grafana_obs;
grant select on all tables in schema obs to grafana_obs;
alter default privileges in schema obs grant select on tables to grafana_obs;

-- Nothing in public: the role has no grant there, and this closes the default door.
revoke all on schema public from grafana_obs;

-- Check, as grafana_obs: the first answers, the second is refused.
--   select * from obs.live_now;
--   select count(*) from public.conversation;
