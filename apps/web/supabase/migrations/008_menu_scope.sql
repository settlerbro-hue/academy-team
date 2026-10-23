-- Restaurant-specific menu progress. Existing personal marks are retained.
begin;
update public.academy_content set payload=payload||jsonb_build_object('brand','rvb','menuSection','bar')
where kind='menu' and id like 'rvb-%' and (not payload ? 'brand' or not payload ? 'menuSection');
do $$ begin
 if not exists(select 1 from pg_constraint where conname='academy_menu_scope_valid' and conrelid='public.academy_content'::regclass) then
 alter table public.academy_content add constraint academy_menu_scope_valid check(kind<>'menu' or coalesce(
 payload->>'brand' in ('rvb','90') and payload->>'menuSection' in ('bar','kitchen') and
 (restaurant_id is null or payload->>'brand'=case when restaurant_id='minsk' then 'rvb'
 when restaurant_id in ('pushkino','khimki','mytishchi') then '90' else '' end),false));
 end if;
end $$;

create or replace function public.academy_ranking() returns jsonb
language sql stable security definer set search_path='' as $$
 with actor as (
 select * from public.academy_profiles where id=auth.uid() and status='active'
 ), visible as (
 select p.* from public.academy_profiles p cross join actor a where p.status='active' and
 (a.role='admin' or (a.role='manager' and p.restaurant_id=a.restaurant_id and p.department=a.department)
 or (a.role='employee' and p.restaurant_id=a.restaurant_id))
 ), best as (
 select a.user_id,a.test_id,max(a.score::numeric/nullif(a.total,0)) filter(where not a.needs_review) as fraction,
 bool_or(a.passed) as passed from public.academy_attempts a join visible p on p.id=a.user_id
 where a.submitted_at is not null and (coalesce((a.snapshot->>'timeLimitSeconds')::integer,0)=0
 or a.submitted_at<=a.started_at+make_interval(secs=>(a.snapshot->>'timeLimitSeconds')::integer+10))
 group by a.user_id,a.test_id
 ), scores as (
 select user_id,round(avg(fraction)*100,1) as average_score,count(*) as tests_attempted,count(*) filter(where passed) as tests_passed
 from best group by user_id
 ), lessons as (
 select p.user_id,count(*) as lessons_completed from public.academy_progress p join visible v on v.id=p.user_id group by p.user_id
 ), marks as (
 select p.id as user_id,count(c.id) as menu_total,count(m.item_id) filter(where m.status='learned') as menu_learned,
 count(m.item_id) filter(where m.status='repeat') as menu_repeat
 from visible p left join public.academy_content c on c.kind='menu' and c.published and (c.department is null or c.department=p.department) and c.payload->>'menuSection' in ('bar','kitchen') and
 (c.restaurant_id=p.restaurant_id or (c.restaurant_id is null and c.payload->>'brand'=case
 when p.restaurant_id='minsk' then 'rvb' when p.restaurant_id in ('pushkino','khimki','mytishchi') then '90' else '' end))
 left join public.academy_menu_marks m on m.user_id=p.id and m.item_id=c.id group by p.id
 )
 select coalesce(jsonb_agg(jsonb_build_object('user_id',p.id,'full_name',p.full_name,'restaurant_id',p.restaurant_id,
 'department',p.department,'position',p.position,'average_score',s.average_score,
 'tests_attempted',coalesce(s.tests_attempted,0),'tests_passed',coalesce(s.tests_passed,0),
 'lessons_completed',coalesce(l.lessons_completed,0),'menu_total',coalesce(m.menu_total,0),'menu_learned',coalesce(m.menu_learned,0),'menu_repeat',coalesce(m.menu_repeat,0))
 order by s.average_score desc nulls last,coalesce(s.tests_passed,0) desc,p.full_name),'[]'::jsonb)
 from visible p left join scores s on s.user_id=p.id left join lessons l on l.user_id=p.id left join marks m on m.user_id=p.id
$$;
revoke all on function public.academy_ranking() from public,anon;
grant execute on function public.academy_ranking() to authenticated;


-- Existing invoker rights and RLS continue to define the manager's visible team.
create or replace function public.academy_manager_dashboard() returns jsonb language sql stable security invoker set search_path='' as $$
select jsonb_build_object(
 'profiles',(select coalesce(jsonb_agg(p),'[]') from public.academy_profiles p),
 'attempts',(select coalesce(jsonb_agg(a),'[]') from public.academy_attempts a),
 'progress',(select coalesce(jsonb_agg(p),'[]') from public.academy_progress p),
 'menu_marks',(select coalesce(jsonb_agg(m),'[]') from public.academy_menu_marks m),
 'menu_stats',(select coalesce(jsonb_agg(x),'[]') from (
 select p.id as user_id,count(c.id) as total,count(m.item_id) filter(where m.status='learned') as learned,
 count(m.item_id) filter(where m.status='repeat') as repeat,
 count(c.id)-count(m.item_id) filter(where m.status in ('learned','repeat')) as not_started
 from public.academy_profiles p left join public.academy_content c on c.kind='menu' and c.published and (c.department is null or c.department=p.department) and c.payload->>'menuSection' in ('bar','kitchen') and
 (c.restaurant_id=p.restaurant_id or (c.restaurant_id is null and c.payload->>'brand'=case
 when p.restaurant_id='minsk' then 'rvb' when p.restaurant_id in ('pushkino','khimki','mytishchi') then '90' else '' end))
 left join public.academy_menu_marks m on m.user_id=p.id and m.item_id=c.id group by p.id
 ) x))
$$;
revoke all on function public.academy_manager_dashboard() from public,anon;
grant execute on function public.academy_manager_dashboard() to authenticated;
commit;
