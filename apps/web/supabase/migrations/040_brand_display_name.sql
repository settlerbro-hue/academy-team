-- Run once as database owner AFTER the parent's new 90-е training import.
-- Does not replay seeds, change IDs/options order/keys or rewrite attempt snapshots.
begin;
create temporary table brand_rename_transaction_marker(n int) on commit drop;

create function pg_temp.brand_display_text(p_text text) returns text
language plpgsql immutable as $fn$
declare rest text:=p_text; result text:=''; found text[]; token text; at_pos int;
begin
 if p_text is null then return null;end if;
 -- Preserve actual URLs and all quoted HTML link/image attributes.
 for found in select regexp_matches(p_text,$rx$(https?://[^[:space:]<>"']+|(?:href|src|data-[[:alnum:]_-]*(?:src|url))[[:space:]]*=[[:space:]]*(?:"[^"]*"|'[^']*'))$rx$,'gi') loop
  token:=found[1];at_pos:=strpos(rest,token);
  result:=result||regexp_replace(left(rest,at_pos-1),'Руки[[:space:]]+Вверх!?[[:space:]]+Бар','Руки ВВерх! Бар','gi')||token;
  rest:=substr(rest,at_pos+length(token));
 end loop;
 return result||regexp_replace(rest,'Руки[[:space:]]+Вверх!?[[:space:]]+Бар','Руки ВВерх! Бар','gi');
end $fn$;

create function pg_temp.brand_display_json(p_value jsonb,p_key text default '') returns jsonb
language plpgsql immutable as $fn$
declare kind text:=jsonb_typeof(p_value);v text;result jsonb;
begin
 if p_value is null then return null;end if;
 if p_key ~ '^(id|.*_id|.*Id|.*Ids|brand|url|.*Url|href|src|.*Src|path|.*Path|.*_path|route|.*Route|storageKey|filename|fileName|mimeType|token|.*Token|key|.*Key)$' then return p_value;end if;
 if kind='string' then
  v:=p_value#>>'{}';
  if v ~* '^https?://' or p_key ~ '^(image|images|cover|coverImage|thumbnail|poster|asset|assets|file|files)$' then return p_value;end if;
  return to_jsonb(pg_temp.brand_display_text(v));
 elsif kind='array' then
  select coalesce(jsonb_agg(case when p_key ~ '^(image|images|cover|coverImage|thumbnail|poster|asset|assets|file|files)$' and jsonb_typeof(e.value)='string' then e.value else pg_temp.brand_display_json(e.value) end order by e.n),'[]'::jsonb) into result from jsonb_array_elements(p_value) with ordinality e(value,n);
  return result;
 elsif kind='object' then
  select coalesce(jsonb_object_agg(e.key,pg_temp.brand_display_json(e.value,e.key)),'{}'::jsonb) into result from jsonb_each(p_value) e;
  return result;
 end if;
 return p_value;
end $fn$;

-- Self-checks run inside this transaction before any live changes.
do $verify$
begin
 if pg_temp.brand_display_text('РУКИ ВВЕРХ БАР Минск')<>'Руки ВВерх! Бар Минск' then raise exception 'Brand text normalization failed';end if;
 if pg_temp.brand_display_text('Руки ВВерх! Бар')<>'Руки ВВерх! Бар' then raise exception 'Brand text is not idempotent';end if;
 if pg_temp.brand_display_json('{"id":"Руки Вверх Бар","url":"https://x/Руки Вверх Бар","image":"assets/Руки Вверх Бар.jpg","title":"Руки Вверх Бар","questions":[{"id":"q1","options":["Руки Вверх Бар","РВБ"]}]}'::jsonb)
 <> '{"id":"Руки Вверх Бар","url":"https://x/Руки Вверх Бар","image":"assets/Руки Вверх Бар.jpg","title":"Руки ВВерх! Бар","questions":[{"id":"q1","options":["Руки ВВерх! Бар","РВБ"]}]}'::jsonb then raise exception 'Brand JSON identity/order check failed';end if;
end $verify$;

-- Block concurrent writes only for this short metadata update. Readers stay open.
lock table public.academy_content in share row exclusive mode;
lock table academy_private.notifications in share row exclusive mode;
lock table academy_private.course_drafts in share row exclusive mode;
lock table public.academy_profiles in share row exclusive mode;
create temporary table brand_rename_profiles_identity on commit drop as select id,to_jsonb(p)-'updated_at' as document from public.academy_profiles p;
create temporary table brand_rename_notice_identity on commit drop as select id,to_jsonb(n)-'title'-'body' as document from academy_private.notifications n;

create temporary table brand_rename_content_before on commit drop as
select c.*,pg_temp.brand_display_text(c.title) as new_title,pg_temp.brand_display_json(c.payload) as new_payload
from public.academy_content c
where pg_temp.brand_display_text(c.title) is distinct from c.title or pg_temp.brand_display_json(c.payload) is distinct from c.payload;
insert into academy_private.audit_log(actor_id,action,target,details)
select auth.uid(),'brand_rename_20261103_before_content',id,jsonb_build_object('title',title,'payload',payload,'updated_at',updated_at)
from brand_rename_content_before;
update public.academy_content c set title=b.new_title,payload=b.new_payload,updated_at=clock_timestamp()
from brand_rename_content_before b where c.id=b.id;

-- Existing in-site notices are visible current text. Keep IDs, recipients,
-- event keys, routes, timestamps/read state, and do not emit new notices.
create temporary table brand_rename_notices_before on commit drop as
select n.*,pg_temp.brand_display_text(n.title) as new_title,pg_temp.brand_display_text(n.body) as new_body
from academy_private.notifications n
where pg_temp.brand_display_text(n.title) is distinct from n.title or pg_temp.brand_display_text(n.body) is distinct from n.body;
insert into academy_private.audit_log(actor_id,action,target,details)
select auth.uid(),'brand_rename_20261103_before_notice',id::text,jsonb_build_object('title',title,'body',body) from brand_rename_notices_before;
update academy_private.notifications n set title=b.new_title,body=b.new_body from brand_rename_notices_before b where n.id=b.id;

-- Retain every current course draft; only normalize display strings. Keep its
-- original base_updated_at: never silently bypass concurrent editor protection.
create temporary table brand_rename_drafts_before on commit drop as
select d.*,pg_temp.brand_display_json(d.document) as new_document from academy_private.course_drafts d
where pg_temp.brand_display_json(d.document) is distinct from d.document;
insert into academy_private.audit_log(actor_id,action,target,details)
select auth.uid(),'brand_rename_20261103_before_draft',course_id,to_jsonb(b)-'new_document' from brand_rename_drafts_before b;
update academy_private.course_drafts d set document=b.new_document,updated_at=clock_timestamp() from brand_rename_drafts_before b where d.course_id=b.course_id;

-- Patch the CURRENT notification function definition, not an older migration.
-- CREATE OR REPLACE preserves its owner and grants; the returned definition also
-- preserves SECURITY DEFINER, volatility and SET search_path. Unexpected matches
-- abort the whole transaction for explicit review by the parent.
do $functions$
declare r record;new_definition text;
begin
 for r in select p.oid,n.nspname,p.proname,pg_get_functiondef(p.oid) as definition
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname in ('public','academy_private') and p.prokind='f'
 loop
  new_definition:=pg_temp.brand_display_text(r.definition);
  if new_definition is distinct from r.definition then
   if r.nspname<>'public' or r.proname<>'academy_announce_content' then raise exception 'Review additional brand-bearing function: %.%',r.nspname,r.proname;end if;
   insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'brand_rename_20261103_before_function',r.oid::regprocedure::text,jsonb_build_object('definition',r.definition));
   execute new_definition;
  end if;
 end loop;
end $functions$;

do $verify$
begin
 if exists(select 1 from brand_rename_content_before b join public.academy_content c using(id) where c.title is distinct from b.new_title or c.payload is distinct from b.new_payload or (to_jsonb(c)-'title'-'payload'-'updated_at') is distinct from (to_jsonb(b)-'title'-'payload'-'updated_at'-'new_title'-'new_payload')) then raise exception 'Content changed beyond display brand';end if;
 if exists(select 1 from brand_rename_drafts_before b join academy_private.course_drafts d using(course_id) where d.document is distinct from b.new_document) then raise exception 'Draft changed beyond display brand';end if;
 if exists(select 1 from brand_rename_profiles_identity b full join public.academy_profiles p using(id) where b.document is distinct from (to_jsonb(p)-'updated_at')) then raise exception 'Profile identity changed during display rename';end if;
 if exists(select 1 from brand_rename_notice_identity b full join academy_private.notifications n using(id) where b.document is distinct from (to_jsonb(n)-'title'-'body')) then raise exception 'Notification identity/read state changed during display rename';end if;
 if exists(select 1 from public.academy_content c where pg_temp.brand_display_text(c.title) is distinct from c.title or pg_temp.brand_display_json(c.payload) is distinct from c.payload) then raise exception 'Brand content normalization incomplete';end if;
 if exists(select 1 from academy_private.notifications n where pg_temp.brand_display_text(n.title) is distinct from n.title or pg_temp.brand_display_text(n.body) is distinct from n.body) then raise exception 'Brand notices normalization incomplete';end if;
 if exists(select 1 from academy_private.course_drafts d where pg_temp.brand_display_json(d.document) is distinct from d.document) then raise exception 'Brand draft normalization incomplete';end if;
end $verify$;
select (select count(*) from brand_rename_content_before) as content_updated,
       (select count(*) from brand_rename_notices_before) as notices_updated,
       (select count(*) from brand_rename_drafts_before) as drafts_updated;
drop function pg_temp.brand_display_json(jsonb,text);
drop function pg_temp.brand_display_text(text);
commit;
