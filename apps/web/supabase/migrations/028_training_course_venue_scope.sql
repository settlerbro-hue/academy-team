-- Required-course venue scope; existing read and edit rights are unchanged.
begin;
update public.academy_content set payload=payload||jsonb_build_object('requiredRestaurantIds',jsonb_build_array('pushkino','khimki','mytishchi')) where id='guru-50011' and kind='course';
create or replace function academy_private.general_training_status(p_user uuid,p_restaurant text,p_department text,p_position text)
returns jsonb language sql stable security definer set search_path='' as $$
with required_courses as (
 select c.* from public.academy_content c where c.kind='course' and c.published
 and (c.restaurant_id is null or c.restaurant_id=p_restaurant) and (c.department is null or c.department=p_department)
 and (not c.payload ? 'audiencePositions' or c.payload->'audiencePositions' ? p_position)
 and (not c.payload ? 'requiredRestaurantIds' or c.payload->'requiredRestaurantIds' ? p_restaurant)
 and coalesce(c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') in ('start','attestation')
), required_tests as (
 select t.* from public.academy_content t where t.kind='test' and t.published
 and (t.restaurant_id is null or t.restaurant_id=p_restaurant) and (t.department is null or t.department=p_department)
 and (not t.payload ? 'audiencePositions' or t.payload->'audiencePositions' ? p_position)
 and (exists(select 1 from required_courses c where c.id=t.course_id) or
 (t.course_id is null and coalesce(t.payload->>'priority','attestation') in ('start','attestation')))
), test_status as (
 select t.id,t.title,t.course_id,exists(select 1 from public.academy_attempts a where a.user_id=p_user and a.test_id=t.id and a.submitted_at is not null and a.passed and not a.needs_review and a.total>0 and
 (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10))) as passed from required_tests t
), course_status as (
 select c.id,c.title,coalesce(c.payload->'audiencePriorities'->>p_position,c.payload->>'priority','additional') as priority,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end)) as total,
 (select count(*) from jsonb_array_elements(case when jsonb_typeof(c.payload->'lessons')='array' then c.payload->'lessons' else '[]'::jsonb end) with ordinality l(value,n) where exists(select 1 from public.academy_progress p where p.user_id=p_user and p.course_id=c.id and p.lesson_id=coalesce(l.value->>'id',(l.n-1)::text))) as done,
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
$$;
commit;
