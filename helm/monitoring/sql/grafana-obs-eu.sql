-- The EU form of grafana-obs-role.sql. On Scaleway the login grafana_obs is made by Terraform
-- (scaleway/main.tf) with the readonly privilege, the only way Scaleway grants CONNECT. That
-- privilege also grants select on the public tables, so this revokes them and grants the obs
-- views only. Run as dembrane_admin, the migration login, which owns both schemas.
--
-- Scaleway does not let dembrane_admin alter a role it did not create, so the role settings of
-- grafana-obs-role.sql (read-only transactions, statement timeout) are not set here: the role
-- has no write grant anywhere, which keeps it read only.

revoke all on all tables in schema public from grafana_obs;
revoke all on schema public from grafana_obs;

grant usage on schema obs to grafana_obs;
grant select on all tables in schema obs to grafana_obs;
alter default privileges in schema obs grant select on tables to grafana_obs;

-- Check, as grafana_obs: the first answers, the second is refused.
--   select * from obs.live_now;
--   select count(*) from public.conversation;

-- EU support requests are read in the EU Grafana (dashboard eu-support): sam is sent only a
-- pointer to the row. The role reads these columns of that one table and nothing else in public.
grant usage on schema public to grafana_obs;
grant select (id, created_at, source, status, message, page_context, workspace_id, project_id)
  on public.support_request to grafana_obs;
