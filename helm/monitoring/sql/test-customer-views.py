"""Exercise the SQL on session-local tables, never real product rows."""
from pathlib import Path
import psycopg

def test_views(conn):
    source=Path('helm/monitoring/sql/customer-views.sql').read_text()
    test_sql=source.replace('public.','pg_temp.').replace('obs.','pg_temp.')
    test_sql=test_sql[:test_sql.index('GRANT SELECT')].replace('BEGIN;','')
    with conn.cursor() as c:
        c.execute('''
          CREATE TEMP TABLE org(id uuid,name text,created_at timestamptz,deleted_at timestamptz,is_partner bool,account_stage text);
          CREATE TEMP TABLE workspace(id uuid,name text,org_id uuid,deleted_at timestamptz);
          CREATE TEMP TABLE project(id uuid,name text,workspace_id uuid,created_at timestamptz,deleted_at timestamptz,is_sample bool);
          CREATE TEMP TABLE conversation(id uuid,project_id uuid,created_at timestamptz,deleted_at timestamptz,source text,duration real);
          CREATE TEMP TABLE project_chat(id uuid,project_id uuid,deleted_at timestamptz);
          CREATE TEMP TABLE project_chat_message(project_chat_id uuid,date_created timestamptz,message_from text);
          CREATE TEMP TABLE project_report(project_id uuid,date_created timestamptz,deleted_at timestamptz,status text,kind text);
          CREATE TEMP TABLE conversation_chunk(conversation_id uuid,created_at timestamptz,timestamp timestamptz);
          CREATE TEMP TABLE platform_presence(kind text,key text,scope text,seen_at timestamptz,expires_at timestamptz);
        ''')
        ident=lambda n:f'00000000-0000-0000-0000-{n:012d}'
        for n,name in ((1,'Real organisation'),(2,'owner@example.test')):
            c.execute("INSERT INTO pg_temp.org VALUES(%s,%s,now()-interval '300d',NULL,false,NULL)",(ident(n),name))
        c.execute("INSERT INTO pg_temp.workspace VALUES(%s,'Workspace',%s,NULL)",(ident(10),ident(1)))
        for n,sample,workspace in ((20,False,10),(21,True,10),(22,False,999)):
            c.execute("INSERT INTO pg_temp.project VALUES(%s,'Project',%s,now(),NULL,%s)",(ident(n),ident(workspace),sample))
        for n,p,src,age,duration in ((30,20,'PORTAL_AUDIO','0d',60),(31,20,'CLONE','0d',600),
                                    (32,21,'PORTAL_AUDIO','0d',600),(33,22,'PORTAL_AUDIO','0d',600),
                                    (34,20,'PORTAL_AUDIO','250d',120)):
            c.execute("INSERT INTO pg_temp.conversation VALUES(%s,%s,now()-%s::interval,NULL,%s,%s)",(ident(n),ident(p),age,src,duration))
        c.execute("INSERT INTO pg_temp.project_chat VALUES(%s,%s,NULL)",(ident(40),ident(20)))
        for who in ('user','assistant'):
            c.execute("INSERT INTO pg_temp.project_chat_message VALUES(%s,now(),%s)",(ident(40),who))
        for status in ('published','archived','error','cancelled'):
            c.execute("INSERT INTO pg_temp.project_report VALUES(%s,now(),NULL,%s,'report')",(ident(20),status))
        for cid in (30,31,32):
            c.execute("INSERT INTO pg_temp.conversation_chunk VALUES(%s,now(),now())",(ident(cid),))
        # A fresh arrival with an old device timestamp is not live recording.
        c.execute("INSERT INTO pg_temp.conversation_chunk VALUES(%s,now(),now()-interval '1h')",(ident(34),))
        c.execute("INSERT INTO pg_temp.platform_presence VALUES('visitor','v',%s,now(),now()+interval '45s')",(ident(20),))
        c.execute("INSERT INTO pg_temp.platform_presence VALUES('visitor','old',%s,now()-interval '1h',now()-interval '1h')",(ident(20),))
        c.execute("INSERT INTO pg_temp.platform_presence VALUES('rec_conv','old-index',%s,now(),now()+interval '1d')",(ident(20),))
        c.execute(test_sql)
        c.execute('SELECT conversations,recordings,audio_minutes,chat_messages,reports,report_errors FROM pg_temp.customer_daily_usage')
        assert c.fetchall()==[(1,1,1.0,1,2,1)], 'samples, clones, orphan attribution or assistant messages counted'
        c.execute('SELECT audio_conversations,onboarding_sessions,chats_15m,reports_15m FROM pg_temp.customer_live')
        assert c.fetchall()==[(1,1,1,2)], 'stale audio or long-lived indexes counted as live'
        c.execute("SELECT org_name FROM pg_temp.customer_organisations WHERE org_id=%s",(ident(2),))
        assert c.fetchone()[0]=='[email withheld]'
        c.execute("SELECT first_use_at<now()-interval '200d' FROM pg_temp.customer_first_use")
        assert c.fetchone()[0] is True, 'returning organisations misclassified as new'
        c.execute('SELECT eligible_conversations_200d,attributed_conversations_200d,unattributed_conversations_200d FROM pg_temp.customer_attribution_coverage')
        assert c.fetchone()==(2,1,1), 'attribution gaps hidden'
        print('PASS: samples/clones excluded, fresh-signal guards, user-only chat, report outcomes, email masking, first retained use and attribution coverage')
    conn.rollback()
