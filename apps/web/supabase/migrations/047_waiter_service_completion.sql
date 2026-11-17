begin;
do $guard$ begin if md5(btrim(replace(pg_get_functiondef('academy_private.general_training_status(uuid,text,text,text)'::regprocedure),chr(13),''),chr(32)||chr(10)||chr(9)))<>'6988806f7f43a6ee2562486482589ade' then raise exception 'Training status definition changed since review';end if;end $guard$;
-- Preserve the complete previous definition for rollback.
insert into academy_private.audit_log(action,target,details)
values('waiter_service_merge_function_before','academy_private.general_training_status',jsonb_build_object('definition',pg_get_functiondef('academy_private.general_training_status(uuid,text,text,text)'::regprocedure)));
create or replace function academy_private.course_assignment_payload(p jsonb,p_position text,p_level text)
returns jsonb language sql immutable set search_path='' as $assignment$
 select case when p ? 'referenceCompletion' and (p_position<>'Официант' or p_level='certified') then
 p||jsonb_build_object('completionLessonIds',p->'referenceCompletion'->'lessonIds','completionTestIds',p->'referenceCompletion'->'testIds','_referenceTrack',true)
 else p end
$assignment$;
create or replace function academy_private.training_test_passed(p_user uuid,p_test text)
returns boolean language sql stable security definer set search_path='' as $credit$
 with allowed as (select c.payload->'completionCredits' as groups from public.academy_content c where c.id=p_test and c.kind='test'),
 passed as (select distinct a.test_id from public.academy_attempts a where a.user_id=p_user and a.submitted_at is not null and a.passed and not a.needs_review and a.total>0 and
 (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10)))
 select exists(select 1 from passed where test_id=p_test) or exists(
 select 1 from allowed,jsonb_array_elements(coalesce(groups,'[]'::jsonb)) g(value)
 where jsonb_array_length(g.value)>0 and not exists(select 1 from jsonb_array_elements_text(g.value) old(id) where not exists(select 1 from passed where test_id=old.id)))
$credit$;
create or replace function academy_private.training_lesson_done(p_user uuid,p_course text,p_lesson text,p jsonb)
returns boolean language sql stable security definer set search_path='' as $lesson$
 select exists(select 1 from public.academy_progress where user_id=p_user and course_id=p_course and lesson_id=p_lesson) or exists(
 select 1 from jsonb_array_elements(coalesce(p->'legacyLessonCredits'->p_lesson,'[]'::jsonb)) g(value)
 where jsonb_array_length(g.value)>0 and not exists(select 1 from jsonb_array_elements_text(g.value) old(id) where not exists(
 select 1 from public.academy_progress where user_id=p_user and course_id=p->>'legacyLessonCourseId' and lesson_id=old.id)))
$lesson$;
revoke all on function academy_private.course_assignment_payload(jsonb,text,text),academy_private.training_test_passed(uuid,text),academy_private.training_lesson_done(uuid,text,text,jsonb) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION academy_private.general_training_status(p_user uuid, p_restaurant text, p_department text, p_position text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with required_courses as (
 select c.id,c.title,academy_private.course_assignment_payload(c.payload,p_position,(select p.training_level from public.academy_profiles p where p.id=p_user)) as payload from public.academy_content c where c.kind='course' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p_restaurant) and (c.department is null or c.department=p_department)
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p_position)
 and (not c.payload ? 'requiredRestaurantIds' or c.payload->'requiredRestaurantIds' ? p_restaurant)
 and coalesce(c.payload->'venueAudiencePriorities'->p_restaurant->>p_position,c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') in ('start','attestation')
), required_tests as (
 select t.* from public.academy_content t where t.kind='test' and t.published
 and (t.restaurant_id is null or t.restaurant_id=p_restaurant) and (t.department is null or t.department=p_department)
 and (not t.payload ? 'audiencePositions' or t.payload->'audiencePositions' ? p_position)
 and (not t.payload ? 'requiredRestaurantIds' or t.payload->'requiredRestaurantIds' ? p_restaurant)
 and (exists(select 1 from required_courses c where c.id=t.course_id and (not c.payload ? 'completionTestIds' or c.payload->'completionTestIds' ? t.id)) or
 (t.course_id is null and coalesce(t.payload->>'priority','attestation') in ('start','attestation')))
), test_status as (
 select t.id,t.title,t.course_id,academy_private.training_test_passed(p_user,t.id) as passed from required_tests t
), course_status as (
 select c.id,c.title,coalesce(c.payload->'venueAudiencePriorities'->p_restaurant->>p_position,c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') as priority,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,n) where (not c.payload ? 'completionLessonIds' or c.payload->'completionLessonIds' ? coalesce(l.value->>'id',(l.n-1)::text))) as total,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,n) where (not c.payload ? 'completionLessonIds' or c.payload->'completionLessonIds' ? coalesce(l.value->>'id',(l.n-1)::text)) and academy_private.training_lesson_done(p_user,c.id,coalesce(l.value->>'id',(l.n-1)::text),c.payload)) as done,
 (select count(*) from test_status t where t.course_id=c.id) as tests_total,
 (select count(*) from test_status t where t.course_id=c.id and t.passed) as tests_passed
 from required_courses c
), completed_courses as (
 select c.*,((total>0 or tests_total>0) and done=total and tests_total=tests_passed) as complete from course_status c
)
select jsonb_build_object('passed',((select count(*) from completed_courses)+(select count(*) from test_status)>0 and not exists(select 1 from completed_courses where not complete) and not exists(select 1 from test_status where not passed)),
 'courses_total',(select count(*) from completed_courses),'courses_completed',(select count(*) from completed_courses where complete),
 'tests_total',(select count(*) from test_status),'tests_passed',(select count(*) from test_status where passed),
 'courses',coalesce((select jsonb_agg(to_jsonb(c) order by case c.priority when 'start' then 0 else 1 end,c.title) from completed_courses c),'[]'::jsonb),
 'tests',coalesce((select jsonb_agg(to_jsonb(t) order by t.title) from test_status t),'[]'::jsonb))
$function$;
commit;
