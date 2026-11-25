-- Infrastructure only. Approved learning content and answer keys are applied from a private release package.
begin;
do $guard$ begin
if md5(btrim(replace(pg_get_functiondef('academy_private.can_read_content(text)'::regprocedure),chr(13),''),chr(32)||chr(10)||chr(9)))<>'540204634adbae924d415f66f6d03fa4' then raise exception 'Content access definition changed since review';end if;
if md5(btrim(replace(pg_get_functiondef('public.academy_test_mistakes(uuid)'::regprocedure),chr(13),''),chr(32)||chr(10)||chr(9)))<>'5ae9527996c07161525b3d9af58a39cc' then raise exception 'Test feedback definition changed since review';end if;
end $guard$;
insert into academy_private.audit_log(action,target,details) values('bar_foundations_functions_before','bar-foundations-20261125',jsonb_build_object('access',pg_get_functiondef('academy_private.can_read_content(text)'::regprocedure),'feedback',pg_get_functiondef('public.academy_test_mistakes(uuid)'::regprocedure)));
create table academy_private.test_review_notes(test_id text not null references public.academy_content(id),question_id text not null,question_text_hash text not null,explanation text not null,lesson_id text not null,primary key(test_id,question_id,question_text_hash));
revoke all on academy_private.test_review_notes from public,anon,authenticated;
create or replace function academy_private.foundation_audience_for(p public.academy_profiles,c public.academy_content)
returns boolean language sql stable set search_path='' as $audience$
 select c.payload->>'foundationCourse' is distinct from 'true'
 or p.role='admin' or p.operations_director or p.venue_director
 or (p.role='manager' and p.department in ('Бар','Зал'))
 or (p.department='Бар' and p.position='Бармен')
 or (p.department='Зал' and p.position='Официант')
$audience$;
revoke all on function academy_private.foundation_audience_for(public.academy_profiles,public.academy_content) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION academy_private.can_read_content(p_id text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select exists(select 1 from public.academy_content c join public.academy_profiles p on p.id=auth.uid()
 where c.id=p_id and p.status='active' and (coalesce(c.payload->>'trainingBrand','') = '' or p.role='admin' or p.operations_director or (c.payload->>'trainingBrand'='rvb' and p.restaurant_id='minsk') or (c.payload->>'trainingBrand'='90' and p.restaurant_id in ('pushkino','khimki','mytishchi'))) and (c.course_id is distinct from 'guru-50011' and c.id not in ('guru-50011','104648','104336','104939','105476','90-assortment-test-alcohol','90-assortment-test-wine','90-assortment-test-cocktails','guru-50012','104593','104760') or p.role='admin' or p.operations_director or p.restaurant_id in ('pushkino','khimki','mytishchi')) and academy_private.foundation_audience_for(p,c) and academy_private.library_audience_for(p,c) and case when p.venue_director then academy_private.venue_document(p,c,false) else case when c.id='rvb-bar-handbook'
 then academy_private.can_read_bar_handbook(p,c)
 else ((c.published and (c.restaurant_id is null or c.restaurant_id=p.restaurant_id) and (c.department is null or c.department=p.department))
 or p.role='admin' or p.operations_director or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.kind='menu' and academy_private.can_edit_menu_for(p,c))) end end)
$function$;
create or replace function public.academy_test_mistakes(p_attempt_id uuid)
returns jsonb language sql stable security definer set search_path='' as $review$
 select coalesce((
  select jsonb_agg(jsonb_build_object(
   'index',question.number-1,'selected',choices.supplied,
   'wrong',(select coalesce(jsonb_agg(value),'[]'::jsonb) from jsonb_array_elements(choices.supplied) where not choices.expected @> jsonb_build_array(value)),
   'incomplete',not(choices.supplied @> choices.expected))
   ||case when notes.test_id is not null then jsonb_build_object('correct',choices.expected,'explanation',notes.explanation,'lesson_id',notes.lesson_id) else '{}'::jsonb end order by question.number)
  from jsonb_array_elements(a.snapshot->'questions') with ordinality question(body,number)
  cross join lateral(select k.keys->(question.body->>'id') expected,case when jsonb_typeof(a.answers->(question.body->>'id'))='array' then a.answers->(question.body->>'id') else '[]'::jsonb end supplied) choices
  left join academy_private.test_review_notes notes on notes.test_id=a.test_id and notes.question_id=question.body->>'id' and notes.question_text_hash=md5(question.body->>'text')
  where question.body->>'type' is distinct from 'text' and jsonb_typeof(choices.expected)='array' and not(choices.supplied @> choices.expected and choices.expected @> choices.supplied)
 ),'[]'::jsonb)
 from public.academy_attempts a join academy_private.attempt_keys k on k.attempt_id=a.id
 where a.id=p_attempt_id and a.user_id = auth.uid() and a.submitted_at is not null and academy_private.is_active();
$review$;
revoke all on function public.academy_test_mistakes(uuid) from public,anon;
grant execute on function public.academy_test_mistakes(uuid) to authenticated;

commit;
