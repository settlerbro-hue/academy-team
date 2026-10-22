-- Academy shared backend. Run as database owner in Supabase SQL Editor.
begin;
create schema if not exists academy_private;
revoke all on schema academy_private from public, anon, authenticated;
create table if not exists public.academy_profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 full_name text not null default '', restaurant_id text check(restaurant_id in ('minsk','pushkino','khimki','mytishchi')),
 department text check(department in ('Зал','Бар','Кухня','Арт','Кальян','Руководитель')),
 position text, role text not null default 'employee' check(role in ('employee','manager','admin')),
 status text not null default 'pending' check(status in ('pending','active','suspended')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.academy_content (
 id text primary key, kind text not null check(kind in ('course','lesson','material','menu','test')),
 title text not null, course_id text, payload jsonb not null default '{}', published boolean not null default true,
 restaurant_id text, department text, updated_at timestamptz not null default now()
);
create table if not exists academy_private.test_keys (
 test_id text primary key references public.academy_content(id) on delete cascade, keys jsonb not null
);
create table if not exists public.academy_attempts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references public.academy_profiles(id),
 test_id text not null references public.academy_content(id), started_at timestamptz not null default now(),
 submitted_at timestamptz, score integer, total integer, passed boolean, needs_review boolean not null default false,
 answers jsonb, snapshot jsonb not null, key_snapshot jsonb not null,
 reviewed_by uuid references public.academy_profiles(id), reviewed_at timestamptz, feedback text
);
-- Secrets live outside the exposed table, even column-level APIs must not reveal keys.
create table if not exists academy_private.attempt_keys (
 attempt_id uuid primary key references public.academy_attempts(id) on delete cascade, keys jsonb not null
);
alter table public.academy_attempts drop column if exists key_snapshot;
create table if not exists public.academy_progress (
 user_id uuid not null references public.academy_profiles(id), course_id text not null references public.academy_content(id),
 lesson_id text not null, completed_at timestamptz not null default now(), primary key(user_id,course_id,lesson_id)
);
create table if not exists public.academy_menu_marks (
 user_id uuid not null references public.academy_profiles(id), item_id text not null references public.academy_content(id),
 status text not null check(status in ('not_started','repeat','learned')), updated_at timestamptz not null default now(),
 primary key(user_id,item_id)
);
create table if not exists academy_private.audit_log (
 id bigint generated always as identity primary key, actor_id uuid, action text not null, target text, details jsonb,
 created_at timestamptz not null default now()
);
create or replace function academy_private.is_active() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles where id=auth.uid() and status='active')
$$;
create or replace function academy_private.can_manage(p_user_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a join public.academy_profiles b on b.id=p_user_id
 where a.id=auth.uid() and a.status='active' and (a.role='admin' or (a.role='manager' and a.restaurant_id=b.restaurant_id and a.department=b.department and b.role='employee')))
$$;
create or replace function academy_private.can_edit(p_restaurant text,p_department text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_profiles a where a.id=auth.uid() and a.status='active' and
 (a.role='admin' or (a.role='manager' and p_restaurant=a.restaurant_id and p_department=a.department)))
$$;
create or replace function academy_private.can_read_content(p_id text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)))
$$;
grant usage on schema academy_private to authenticated;
revoke all on function academy_private.is_active(),academy_private.can_manage(uuid),academy_private.can_edit(text,text),academy_private.can_read_content(text) from public,anon;
grant execute on function academy_private.is_active(),academy_private.can_manage(uuid),academy_private.can_edit(text,text),academy_private.can_read_content(text) to authenticated;
alter table public.academy_profiles enable row level security;
alter table public.academy_content enable row level security;
alter table public.academy_attempts enable row level security;
alter table public.academy_progress enable row level security;
alter table public.academy_menu_marks enable row level security;
drop policy if exists profiles_read on public.academy_profiles;
create policy profiles_read on public.academy_profiles for select to authenticated using(id=auth.uid() or academy_private.can_manage(id));
drop policy if exists content_read on public.academy_content;
create policy content_read on public.academy_content for select to authenticated using(academy_private.can_read_content(id));
drop policy if exists attempts_read on public.academy_attempts;
create policy attempts_read on public.academy_attempts for select to authenticated using((user_id=auth.uid() and academy_private.is_active()) or academy_private.can_manage(user_id));
drop policy if exists progress_read on public.academy_progress;
create policy progress_read on public.academy_progress for select to authenticated using((user_id=auth.uid() and academy_private.is_active()) or academy_private.can_manage(user_id));
drop policy if exists progress_insert on public.academy_progress;
create policy progress_insert on public.academy_progress for insert to authenticated with check(user_id=auth.uid() and academy_private.can_read_content(course_id));
drop policy if exists progress_update on public.academy_progress;
create policy progress_update on public.academy_progress for update to authenticated using(user_id=auth.uid() and academy_private.can_read_content(course_id)) with check(user_id=auth.uid() and academy_private.can_read_content(course_id));
drop policy if exists marks_read on public.academy_menu_marks;
create policy marks_read on public.academy_menu_marks for select to authenticated using((user_id=auth.uid() and academy_private.is_active()) or academy_private.can_manage(user_id));
revoke all on public.academy_profiles,public.academy_content,public.academy_attempts,public.academy_progress,public.academy_menu_marks from anon,authenticated;
grant select on public.academy_profiles,public.academy_content,public.academy_attempts,public.academy_progress,public.academy_menu_marks to authenticated;
grant insert,update on public.academy_progress to authenticated;
-- Completion is validated by RPC, never arbitrary client-supplied lesson identifiers.
revoke insert,update on public.academy_progress from authenticated;

create or replace function public.academy_enroll(p_full_name text,p_restaurant_id text,p_department text,p_position text)
returns public.academy_profiles language plpgsql security definer set search_path='' as $$
declare r public.academy_profiles;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_full_name is null or length(trim(p_full_name))<2 or length(p_full_name)>150 then raise exception 'Invalid name'; end if;
 if p_restaurant_id is null or p_restaurant_id not in ('minsk','pushkino','khimki','mytishchi') or p_department is null or p_position is null then raise exception 'Complete your team profile'; end if;
 if not ((p_department='Зал' and p_position in ('Официант','Администратор','Хостес')) or
 (p_department='Бар' and p_position in ('Старший бармен','Барбэк','Бармен')) or
 (p_department='Кухня' and p_position='Сотрудник кухни') or (p_department='Арт' and p_position='Сотрудник арт') or
 (p_department='Кальян' and p_position='Сотрудник кальянного подразделения') or (p_department='Руководитель' and p_position='Руководитель')) then raise exception 'Invalid position'; end if;
 insert into public.academy_profiles(id,full_name,restaurant_id,department,position) values(auth.uid(),trim(p_full_name),p_restaurant_id,p_department,p_position)
 on conflict(id) do update set full_name=excluded.full_name,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position,updated_at=now()
 where academy_profiles.status='pending' and academy_profiles.role='employee' returning * into r;
 if r.id is null then select * into r from public.academy_profiles where id=auth.uid(); end if;
 return r;
end $$;

create or replace function public.academy_complete_lesson(p_course_id text,p_lesson_id text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not academy_private.can_read_content(p_course_id) then raise exception 'Forbidden'; end if;
 if not exists(select 1 from public.academy_content c,
 lateral jsonb_array_elements(coalesce(c.payload->'lessons','[]'::jsonb)) with ordinality l(item,idx)
 where c.id=p_course_id and c.kind='course' and coalesce(l.item->>'id',(l.idx-1)::text)=p_lesson_id)
 then raise exception 'Lesson does not belong to course'; end if;
 insert into public.academy_progress(user_id,course_id,lesson_id) values(auth.uid(),p_course_id,p_lesson_id)
 on conflict(user_id,course_id,lesson_id) do nothing;
end $$;

create or replace function public.academy_manage_member(p_user_id uuid,p_status text,p_role text default 'employee')
returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if not academy_private.can_manage(p_user_id) or p_user_id=auth.uid() then raise exception 'Forbidden'; end if;
 if actor.role<>'admin' and p_role<>'employee' then raise exception 'Only admin can assign roles'; end if;
 update public.academy_profiles set status=p_status,role=p_role,updated_at=now() where id=p_user_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'member',p_user_id::text,jsonb_build_object('status',p_status,'role',p_role));
end $$;

create or replace function public.academy_set_mark(p_item_id text,p_status text,p_user_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare target uuid:=coalesce(p_user_id,auth.uid());
begin
 if not academy_private.is_active() or not (target=auth.uid() or academy_private.can_manage(target)) then raise exception 'Forbidden'; end if;
 if target=auth.uid() and not academy_private.can_read_content(p_item_id) then raise exception 'Content unavailable'; end if;
 if not exists(select 1 from public.academy_content where id=p_item_id and kind='menu') then raise exception 'Invalid menu item'; end if;
 insert into public.academy_menu_marks(user_id,item_id,status) values(target,p_item_id,p_status)
 on conflict(user_id,item_id) do update set status=excluded.status,updated_at=now();
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'menu_mark',target::text,jsonb_build_object('item_id',p_item_id,'status',p_status));
end $$;

create or replace function public.academy_start_test(p_test_id text) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.academy_content; a uuid; k jsonb;
begin
 if not academy_private.can_read_content(p_test_id) then raise exception 'Forbidden'; end if;
 select * into c from public.academy_content where id=p_test_id and kind='test';
 select keys into k from academy_private.test_keys where test_id=p_test_id;
 if c.id is null or k is null then raise exception 'Test unavailable'; end if;
 -- A fresh immutable snapshot keeps editing from changing a running attempt.
 insert into public.academy_attempts(user_id,test_id,snapshot) values(auth.uid(),p_test_id,c.payload) returning id into a;
 insert into academy_private.attempt_keys(attempt_id,keys) values(a,k);
 return jsonb_build_object('attempt_id',a,'title',c.title,'questions',c.payload->'questions','time_limit_seconds',c.payload->'timeLimitSeconds','started_at',now());
end $$;

create or replace function public.academy_submit_test(p_attempt_id uuid,p_answers jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.academy_attempts; k jsonb; q jsonb; expected jsonb; supplied jsonb; points integer:=0; n integer:=0; review boolean:=false; ok boolean; deadline integer;
begin
 if not academy_private.is_active() then raise exception 'Forbidden'; end if;
 select * into a from public.academy_attempts where id=p_attempt_id and user_id=auth.uid() for update;
 if a.id is null then raise exception 'Attempt unavailable'; end if;
 if a.submitted_at is not null then return jsonb_build_object('score',a.score,'total',a.total,'passed',a.passed,'needs_review',a.needs_review); end if;
 if jsonb_typeof(p_answers)<>'object' or octet_length(p_answers::text)>100000 then raise exception 'Invalid answers'; end if;
 select keys into k from academy_private.attempt_keys where attempt_id=a.id;
 for q in select value from jsonb_array_elements(a.snapshot->'questions') loop
 n:=n+1; expected:=k->(q->>'id'); supplied:=p_answers->(q->>'id');
 if q->>'type'='text' or expected is null then review:=true;
 elsif jsonb_typeof(supplied)='array' then
 select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into supplied from (select distinct value from jsonb_array_elements(supplied)) s;
 select coalesce(jsonb_agg(value order by value), '[]'::jsonb) into expected from (select distinct value from jsonb_array_elements(expected)) e;
 if supplied=expected then points:=points+1; end if;
 end if;
 end loop;
 deadline:=coalesce((a.snapshot->>'timeLimitSeconds')::integer,0);
 ok:=not review and points>=coalesce((a.snapshot->>'passCount')::integer,n);
 if deadline>0 and now()>a.started_at+make_interval(secs=>deadline+10) then ok:=false; end if;
 update public.academy_attempts set submitted_at=now(),score=points,total=n,passed=ok,needs_review=review,answers=p_answers where id=a.id;
 return jsonb_build_object('score',points,'total',n,'passed',ok,'needs_review',review);
end $$;

create or replace function public.academy_save_content(p_document jsonb,p_keys jsonb default null) returns void language plpgsql security definer set search_path='' as $$
declare old public.academy_content; rid text:=p_document->>'restaurant_id'; dep text:=p_document->>'department';
begin
 if not academy_private.can_edit(rid,dep) then raise exception 'Forbidden'; end if;
 select * into old from public.academy_content where id=p_document->>'id';
 if old.id is not null and not academy_private.can_edit(old.restaurant_id,old.department) then raise exception 'Forbidden'; end if;
 -- Keys must never enter the exposed payload, including nested fields.
 if jsonb_path_exists(p_document->'payload','$.**.correct') or jsonb_path_exists(p_document->'payload','$.**.key_snapshot') then raise exception 'Keep answer keys private'; end if;
 insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department)
 values(p_document->>'id',p_document->>'kind',p_document->>'title',p_document->>'course_id',p_document->'payload',coalesce((p_document->>'published')::boolean,true),rid,dep)
 on conflict(id) do update set title=excluded.title,payload=excluded.payload,published=excluded.published,restaurant_id=excluded.restaurant_id,department=excluded.department,updated_at=now();
 if p_keys is not null then
 if p_document->>'kind'<>'test' or jsonb_typeof(p_keys)<>'object' then raise exception 'Invalid test keys'; end if;
 insert into academy_private.test_keys(test_id,keys) values(p_document->>'id',p_keys) on conflict(test_id) do update set keys=excluded.keys;
 end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'content_save',p_document->>'id');
end $$;

create or replace function public.academy_review_attempt(p_attempt_id uuid,p_manual_score integer,p_feedback text default '')
returns void language plpgsql security definer set search_path='' as $$
declare a public.academy_attempts; manual_count integer; k jsonb;
begin
 select * into a from public.academy_attempts where id=p_attempt_id for update;
 if a.id is null or not academy_private.can_manage(a.user_id) then raise exception 'Forbidden'; end if;
 if a.submitted_at is null or not a.needs_review then raise exception 'Not awaiting review'; end if;
 select keys into k from academy_private.attempt_keys where attempt_id=a.id;
 select count(*) into manual_count from jsonb_array_elements(a.snapshot->'questions') q where q->>'type'='text' or k->(q->>'id') is null;
 if p_manual_score<0 or p_manual_score>manual_count or p_manual_score is null then raise exception 'Invalid manual score'; end if;
 update public.academy_attempts set score=score+p_manual_score,needs_review=false,
 passed=(score+p_manual_score>=coalesce((snapshot->>'passCount')::integer,total)) and
 (coalesce((snapshot->>'timeLimitSeconds')::integer,0)=0 or submitted_at<=started_at+make_interval(secs=>(snapshot->>'timeLimitSeconds')::integer+10)),
 reviewed_by=auth.uid(),reviewed_at=now(),feedback=left(p_feedback,5000) where id=p_attempt_id;
 insert into academy_private.audit_log(actor_id,action,target,details) values(auth.uid(),'review_attempt',p_attempt_id::text,jsonb_build_object('manual_score',p_manual_score));
end $$;

create or replace function public.academy_manager_dashboard() returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if not exists(select 1 from public.academy_profiles where id=auth.uid() and status='active' and role in ('manager','admin')) then raise exception 'Forbidden'; end if;
 return jsonb_build_object('profiles',(select coalesce(jsonb_agg(p),'[]') from public.academy_profiles p),
 'attempts',(select coalesce(jsonb_agg(a),'[]') from public.academy_attempts a),
 'progress',(select coalesce(jsonb_agg(p),'[]') from public.academy_progress p),
 'menu_marks',(select coalesce(jsonb_agg(m),'[]') from public.academy_menu_marks m));
end $$;
-- Never inherit default PUBLIC function execution for mutation/definer endpoints.
revoke all on function public.academy_enroll(text,text,text,text),public.academy_manage_member(uuid,text,text),public.academy_set_mark(text,text,uuid),public.academy_start_test(text),public.academy_submit_test(uuid,jsonb),public.academy_save_content(jsonb,jsonb),public.academy_manager_dashboard() from public,anon;
grant execute on function public.academy_enroll(text,text,text,text),public.academy_manage_member(uuid,text,text),public.academy_set_mark(text,text,uuid),public.academy_start_test(text),public.academy_submit_test(uuid,jsonb),public.academy_save_content(jsonb,jsonb),public.academy_manager_dashboard() to authenticated;
revoke all on function public.academy_review_attempt(uuid,integer,text) from public,anon;
grant execute on function public.academy_review_attempt(uuid,integer,text) to authenticated;
revoke all on function public.academy_complete_lesson(text,text) from public,anon;
grant execute on function public.academy_complete_lesson(text,text) to authenticated;
revoke all on all tables in schema academy_private from public,anon,authenticated;
insert into storage.buckets(id,name,public) values('academy-assets','academy-assets',false)
on conflict(id) do update set public=false;
drop policy if exists academy_assets_read on storage.objects;
create policy academy_assets_read on storage.objects for select to authenticated
using(bucket_id='academy-assets' and academy_private.is_active());
drop policy if exists academy_assets_insert on storage.objects;
create policy academy_assets_insert on storage.objects for insert to authenticated
with check(bucket_id='academy-assets' and academy_private.can_edit(null,null));
drop policy if exists academy_assets_update on storage.objects;
create policy academy_assets_update on storage.objects for update to authenticated
using(bucket_id='academy-assets' and academy_private.can_edit(null,null))
with check(bucket_id='academy-assets' and academy_private.can_edit(null,null));
commit;
