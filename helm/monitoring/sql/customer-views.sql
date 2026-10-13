-- Customer-level production observability. No transcripts, emails, prompts or tokens.
-- Apply as the migration/observability owner, never as grafana_obs.
-- These are read-only views over existing rows; no product rows are changed.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';

CREATE OR REPLACE VIEW obs.customer_organisations AS
SELECT o.id::text AS org_id,
       regexp_replace(o.name, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[email withheld]', 'g') AS org_name, o.created_at,
       o.is_partner, coalesce(o.account_stage, 'unclassified') AS account_stage,
       (SELECT count(*)::int FROM public.workspace w
        WHERE w.org_id=o.id AND w.deleted_at IS NULL) AS workspaces
FROM public.org o WHERE o.deleted_at IS NULL;

CREATE OR REPLACE VIEW obs.customer_projects AS
SELECT o.id::text AS org_id,
       regexp_replace(o.name, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[email withheld]', 'g') AS org_name,
       w.id::text AS workspace_id,
       regexp_replace(w.name, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[email withheld]', 'g') AS workspace_name,
       p.id::text AS project_id,
       regexp_replace(p.name, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[email withheld]', 'g') AS project_name,
       p.created_at AS project_created_at
FROM public.project p
JOIN public.workspace w ON w.id=p.workspace_id AND w.deleted_at IS NULL
JOIN public.org o ON o.id=w.org_id AND o.deleted_at IS NULL
WHERE p.deleted_at IS NULL AND NOT p.is_sample;

-- One row per product action, bounded to 200 days. An action is not a person.
-- Conversation durations belong to their start date; they can grow as audio arrives.
CREATE OR REPLACE VIEW obs.customer_activity AS
SELECT c.created_at AS occurred_at, d.org_id, d.project_id,
       'conversation'::text AS action, c.source::text AS detail,
       coalesce(c.duration, 0)::double precision / 60 AS audio_minutes
FROM public.conversation c JOIN obs.customer_projects d ON d.project_id=c.project_id::text
WHERE c.created_at>=now()-interval '200 days' AND c.deleted_at IS NULL AND c.source IS DISTINCT FROM 'CLONE'
UNION ALL
SELECT m.date_created, d.org_id, d.project_id, 'chat', 'user message', 0::double precision
FROM public.project_chat_message m
JOIN public.project_chat pc ON pc.id=m.project_chat_id AND pc.deleted_at IS NULL
JOIN obs.customer_projects d ON d.project_id=pc.project_id::text
WHERE m.date_created>=now()-interval '200 days' AND m.message_from='user'
UNION ALL
SELECT r.date_created, d.org_id, d.project_id,
       CASE WHEN r.status='error' THEN 'report_error' ELSE 'report' END,
       r.kind::text, 0::double precision
FROM public.project_report r JOIN obs.customer_projects d ON d.project_id=r.project_id::text
WHERE r.date_created>=now()-interval '200 days' AND r.deleted_at IS NULL
  AND r.status IN ('published','archived','error')
UNION ALL
SELECT d.project_created_at, d.org_id, d.project_id, 'project', 'created', 0::double precision
FROM obs.customer_projects d WHERE d.project_created_at>=now()-interval '200 days';

CREATE OR REPLACE VIEW obs.customer_daily_usage AS
SELECT (occurred_at AT TIME ZONE 'Europe/Amsterdam')::date AS day, org_id,
       count(*) FILTER (WHERE action='conversation')::int AS conversations,
       count(*) FILTER (WHERE action='conversation' AND detail IN ('PORTAL_AUDIO','GO_IOS'))::int AS recordings,
       count(*) FILTER (WHERE action='conversation' AND detail='DASHBOARD_UPLOAD')::int AS uploads,
       sum(audio_minutes) AS audio_minutes,
       count(*) FILTER (WHERE action='chat')::int AS chat_messages,
       count(*) FILTER (WHERE action='report')::int AS reports,
       count(*) FILTER (WHERE action='report_error')::int AS report_errors,
       count(*) FILTER (WHERE action='project')::int AS projects_created,
       count(DISTINCT project_id)::int AS active_projects
FROM obs.customer_activity GROUP BY 1,2;

-- First retained server-side use, not first pageview or a claim about payment.
CREATE OR REPLACE VIEW obs.customer_first_use AS
SELECT org_id, min(first_input_at) AS first_input_at, min(first_analysis_at) AS first_analysis_at,
       least(min(first_input_at),min(first_analysis_at)) AS first_use_at
FROM (
  SELECT d.org_id, min(c.created_at) AS first_input_at, NULL::timestamptz AS first_analysis_at
  FROM public.conversation c JOIN obs.customer_projects d ON d.project_id=c.project_id::text
  WHERE c.deleted_at IS NULL AND c.source IS DISTINCT FROM 'CLONE' GROUP BY d.org_id
  UNION ALL
  SELECT d.org_id, NULL::timestamptz, min(m.date_created)
  FROM public.project_chat_message m
  JOIN public.project_chat pc ON pc.id=m.project_chat_id AND pc.deleted_at IS NULL
  JOIN obs.customer_projects d ON d.project_id=pc.project_id::text
  WHERE m.message_from='user' GROUP BY d.org_id
  UNION ALL
  SELECT d.org_id, NULL::timestamptz, min(r.date_created)
  FROM public.project_report r JOIN obs.customer_projects d ON d.project_id=r.project_id::text
  WHERE r.deleted_at IS NULL AND r.status IN ('published','archived') GROUP BY d.org_id
) x GROUP BY org_id;

CREATE OR REPLACE VIEW obs.customer_attribution_coverage AS
SELECT now() AS checked_at, count(*)::int AS eligible_conversations_200d,
       count(d.project_id)::int AS attributed_conversations_200d,
       count(*) FILTER (WHERE d.project_id IS NULL)::int AS unattributed_conversations_200d
FROM public.conversation c
LEFT JOIN public.project p ON p.id=c.project_id
LEFT JOIN public.workspace w ON w.id=p.workspace_id
LEFT JOIN public.org o ON o.id=w.org_id
LEFT JOIN obs.customer_projects d ON d.project_id=c.project_id::text
WHERE c.created_at>=now()-interval '200 days' AND c.deleted_at IS NULL
  AND c.source IS DISTINCT FROM 'CLONE' AND NOT coalesce(p.is_sample,false)
  AND p.deleted_at IS NULL AND w.deleted_at IS NULL AND o.deleted_at IS NULL;

-- Fresh audio has both server arrival and client timestamp guards. Unfinished
-- conversations and long-lived recording-session indexes are NOT live activity.
CREATE OR REPLACE VIEW obs.customer_live AS
WITH audio AS (
  SELECT c.project_id::text AS project_id, count(DISTINCT c.id)::int AS audio_conversations,
         max(k.created_at) AS last_audio_at
  FROM public.conversation_chunk k JOIN public.conversation c ON c.id=k.conversation_id
  WHERE k.created_at>now()-interval '3 minutes'
    AND k."timestamp">now()-interval '3 minutes' AND k."timestamp"<now()+interval '10 minutes'
    AND c.deleted_at IS NULL AND c.source IN ('PORTAL_AUDIO','GO_IOS')
  GROUP BY 1
), visitors AS (
  SELECT scope AS project_id, count(*)::int AS onboarding_sessions, max(seen_at) AS seen_at
  FROM public.platform_presence WHERE kind='visitor' AND expires_at>now()
    AND seen_at>now()-interval '90 seconds' GROUP BY scope
), actions AS (
  SELECT project_id, count(*) FILTER (WHERE action='chat')::int AS chats_15m,
         count(*) FILTER (WHERE action='report')::int AS reports_15m,
         max(occurred_at) AS last_action_at
  FROM obs.customer_activity WHERE occurred_at>now()-interval '15 minutes' GROUP BY project_id
)
SELECT d.*, coalesce(a.audio_conversations,0) AS audio_conversations,
       coalesce(v.onboarding_sessions,0) AS onboarding_sessions,
       coalesce(x.chats_15m,0) AS chats_15m, coalesce(x.reports_15m,0) AS reports_15m,
       a.last_audio_at, greatest(a.last_audio_at,v.seen_at,x.last_action_at) AS last_signal_at
FROM obs.customer_projects d LEFT JOIN audio a USING(project_id)
LEFT JOIN visitors v USING(project_id) LEFT JOIN actions x USING(project_id)
WHERE a.project_id IS NOT NULL OR v.project_id IS NOT NULL OR x.project_id IS NOT NULL;

GRANT SELECT ON obs.customer_organisations, obs.customer_projects, obs.customer_activity,
                obs.customer_daily_usage, obs.customer_live, obs.customer_first_use,
                obs.customer_attribution_coverage TO grafana_obs;
COMMIT;
