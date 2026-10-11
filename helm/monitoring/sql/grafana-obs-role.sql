-- The dashboard login for Grafana: one role per database, read-only, obs views only.
-- Run once per environment with the owner login (prod: doadmin, staging: echo_owner),
-- then put the password in the monitoring secret grafana-obs-db as OBS_<ENV>_DB_PASSWORD.
-- The product's migrations grant this role the obs views whenever it exists, so new views
-- need no second step here.
--
-- Replace <password> before running. Never commit the password.

create role grafana_obs login password '<password>';
alter role grafana_obs set statement_timeout = '30s';
alter role grafana_obs set default_transaction_read_only = on;
alter role grafana_obs set search_path = obs;

-- Only when the obs schema already exists (the product release carrying it is out); the
-- migration does the same on every run.
grant usage on schema obs to grafana_obs;
grant select on all tables in schema obs to grafana_obs;

-- Nothing in public: the role has no grant there, and this closes the default door.
revoke all on schema public from grafana_obs;

-- Check, as grafana_obs: the first answers, the second is refused.
--   select * from obs.live_now;
--   select count(*) from public.conversation;
