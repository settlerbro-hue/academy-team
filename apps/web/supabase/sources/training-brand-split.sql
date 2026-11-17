-- Apply after the site can resolve trainingSourceId on old learning links.
begin;

create temporary table brand_courses (id text primary key, minsk_id text unique) on commit drop;
insert into brand_courses values
 ('additional-service-hospitality','rvb--additional-service-hospitality'),
 ('guru-25724','rvb--guru-25724'),
 ('guru-25811','rvb--guru-25811'),
 ('guru-36651','rvb--guru-36651'),
 ('guru-42932','rvb--guru-42932'),
 ('guru-43403','rvb--guru-43403'),
 ('guru-44033','rvb--guru-44033'),
 ('guru-44607','rvb--guru-44607'),
 ('guru-51132','rvb--guru-51132'),
 ('hostess-standards','rvb--hostess-standards'),
 ('waiter-internship','rvb--waiter-internship'),
 ('waiter-standards','rvb--waiter-standards'),
 ('welcome-90','rvb--welcome-90');

create temporary table brand_minsk_variants (
 content_id text, lesson_id text, payload jsonb, keys jsonb, primary key (content_id,lesson_id)
) on commit drop;
do $copy$
begin
 if to_regclass('academy_private.minsk_waiter_variants') is not null then
   execute 'insert into brand_minsk_variants select content_id,lesson_id,payload,keys from academy_private.minsk_waiter_variants';
 end if;
end $copy$;

create temporary table brand_tests on commit drop as
select t.id,t.course_id,b.minsk_id as minsk_course,
  case when scope.minsk then case when scope.ninety then 'rvb--'||t.id else t.id end end as minsk_id,
  scope.ninety
from public.academy_content t
join brand_courses b on b.id=t.course_id
cross join lateral (
 select (t.restaurant_id is null or t.restaurant_id='minsk')
  and (not t.payload ? 'requiredRestaurantIds' or t.payload->'requiredRestaurantIds' ? 'minsk') as minsk,
  (t.restaurant_id is null or t.restaurant_id in ('pushkino','khimki','mytishchi'))
  and (not t.payload ? 'requiredRestaurantIds' or t.payload->'requiredRestaurantIds' ?| array['pushkino','khimki','mytishchi']) as ninety
) scope
where t.kind='test';

create function pg_temp.brand_training_steps(doc jsonb, known jsonb, mapping jsonb)
returns jsonb language plpgsql as $steps$
declare field text; rewritten jsonb;
begin
 foreach field in array array['sequence','outline','completionTestIds'] loop
   if jsonb_typeof(doc->field) is distinct from 'array' then continue; end if;
   select coalesce(jsonb_agg(
      case when not (known ? x.id) then x.value
           when field='completionTestIds' then mapping->x.id
           else jsonb_set(x.value,'{id}',mapping->x.id) end order by x.n
    ) filter (where not (known ? x.id) or mapping ? x.id), '[]'::jsonb)
   into rewritten
   from (
    select v.value,v.n,case when field='completionTestIds' then v.value#>>'{}'
      when v.value->>'type'='test' then v.value->>'id' end as test_id
    from jsonb_array_elements(doc->field) with ordinality v(value,n)
   ) as raw
   cross join lateral (select raw.value,raw.n,coalesce(raw.test_id,'') as id) x;
   doc:=jsonb_set(doc,array[field],rewritten);
 end loop;
 return doc;
end
$steps$;

create temporary table brand_album on commit drop as
select c.updated_at as original_updated_at,d.updated_at as draft_updated_at,live.value as original_lesson,draft.value as draft_lesson
from public.academy_content c join academy_private.course_drafts d on d.course_id=c.id and d.base_updated_at=c.updated_at
cross join lateral jsonb_array_elements(c.payload->'lessons') live
cross join lateral jsonb_array_elements(d.document->'payload'->'lessons') draft
where c.id='welcome-90' and live.value->>'id'='123016' and draft.value->>'id'='123016';

do $guards$
begin
 if (select count(*) from public.academy_content c join brand_courses b on c.id=b.id where c.kind='course' and c.published and c.restaurant_id is null) <> 13
 or exists(select 1 from public.academy_content c join brand_courses b on c.id=b.minsk_id)
 or exists(select 1 from brand_tests t join public.academy_content c on t.minsk_id=c.id and t.id<>t.minsk_id)
 or exists(select 1 from brand_tests where not ninety and minsk_id is null) then
  raise exception 'Training records changed: review split inputs';
 end if;
 if exists(select 1 from academy_private.course_drafts d join brand_courses b on b.id=d.course_id where b.id<>'welcome-90') then
  raise exception 'A shared course has a draft: preserve or reconcile it before splitting';
 end if;
 if (select count(*) from brand_album)<>1
 or exists(select 1 from brand_album where jsonb_array_length(original_lesson->'blocks')<>12 or jsonb_array_length(draft_lesson->'blocks')<>26)
 or exists(
  select 1 from brand_album a
  cross join lateral jsonb_array_elements(a.draft_lesson->'blocks') with ordinality b(value,n)
  left join public.academy_course_media m on ('course-media:'||m.id)=b.value->>'src'
  where (b.n<=12 and b.value is distinct from a.original_lesson->'blocks'->(b.n::integer-1))
  or (b.n>12 and (m.course_id is distinct from 'welcome-90' or m.status is distinct from 'ready'
     or m.filename is distinct from format('minsk-%s.jpg',lpad((b.n-12)::text,2,'0'))))
 ) then raise exception 'Album draft does not contain the 11 original and 14 new cards in source order'; end if;
 if exists(select 1 from brand_tests b join public.academy_content c on c.id=b.id
      left join academy_private.test_keys k on k.test_id=b.id where c.published and k.test_id is null) then
  raise exception 'Published test without a key';
 end if;
end $guards$;

create temporary table brand_before_status on commit drop as
select p.id,p.training_level, academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position)
 - array['courses','tests'] as totals
from public.academy_profiles p where p.status='active' and p.restaurant_id in ('minsk','pushkino','khimki','mytishchi');
create temporary table brand_before_progress on commit drop as
select p.* from public.academy_progress p join brand_courses c on c.id=p.course_id
join public.academy_profiles u on u.id=p.user_id where u.restaurant_id='minsk';
create temporary table brand_before_attempts on commit drop as
select a.id,a.test_id,a.score,a.total,a.passed,a.needs_review
from public.academy_attempts a join brand_tests t on t.id=a.test_id
join public.academy_profiles u on u.id=a.user_id
where u.restaurant_id='minsk' and t.minsk_id is not null and t.minsk_id<>t.id;

insert into academy_private.audit_log(action,target,details)
select 'training_brand_split_before',c.id,jsonb_build_object('content',to_jsonb(c),'test_keys',k.keys)
from public.academy_content c left join academy_private.test_keys k on k.test_id=c.id
where c.id in (select id from brand_courses union select id from brand_tests)
or c.id in ('guru-52664','guru-53164') or c.course_id in ('guru-52664','guru-53164');

with course_source as (
 select b.*,c.title,c.payload,c.department,t.all_ids,t.minsk_ids,
  coalesce(a.draft_lesson->'blocks','[]') as welcome_draft
 from brand_courses b join public.academy_content c on c.id=b.id
 left join brand_album a on c.id='welcome-90'
 cross join lateral (
  select coalesce(jsonb_object_agg(x.id,x.id),'{}') all_ids,
    coalesce(jsonb_object_agg(x.id,x.minsk_id) filter(where x.minsk_id is not null),'{}') minsk_ids
  from brand_tests x where x.course_id=b.id
 ) t
), minsk_courses as (
 select s.*,
  case s.id when 'welcome-90' then 'Добро пожаловать в команду — Руки ВВерх! Бар Минск'
   when 'guru-42932' then 'Стажировка менеджера — Руки ВВерх! Бар Минск'
   else s.title end as minsk_title,
  coalesce((
   select jsonb_agg(
    case when s.id='welcome-90' and l.value->>'id'='123016' then
      (l.value - 'images') || jsonb_build_object('blocks',
        jsonb_build_array(jsonb_set(l.value->'blocks'->0,'{eyebrow}',to_jsonb('Руки ВВерх! Бар · Минск'::text),true))
        || (select jsonb_agg(b.value order by b.n)
              from jsonb_array_elements(s.welcome_draft) with ordinality b(value,n) where b.n>12))
     else coalesce(v.payload,l.value) end order by l.n)
   from jsonb_array_elements(coalesce(s.payload->'lessons','[]'::jsonb)) with ordinality l(value,n)
   left join brand_minsk_variants v on v.content_id=s.id and v.lesson_id=l.value->>'id'
  ),'[]') as lessons
 from course_source s
)
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload)
select minsk_id,'course',minsk_title,true,'minsk',department,
 pg_temp.brand_training_steps(payload,all_ids,minsk_ids)
  || jsonb_build_object('id',minsk_id,'title',minsk_title,'brand','rvb','trainingBrand','rvb','trainingSourceId',id,
      'restaurantIds',jsonb_build_array('minsk'),'requiredRestaurantIds',jsonb_build_array('minsk'),'lessons',lessons)
from minsk_courses;

insert into public.academy_content(id,kind,title,course_id,payload,published,restaurant_id,department)
select b.minsk_id,'test',t.title,b.minsk_course,
 coalesce(v.payload,t.payload) || jsonb_build_object('id',b.minsk_id,'brand','rvb','trainingBrand','rvb',
  'trainingSourceId',t.id,'restaurantIds',jsonb_build_array('minsk'),'requiredRestaurantIds',jsonb_build_array('minsk')),
 t.published,'minsk',t.department
from brand_tests b join public.academy_content t on t.id=b.id
left join brand_minsk_variants v on v.content_id=t.id and v.lesson_id=''
where b.minsk_id is not null and b.minsk_id<>b.id;

insert into academy_private.test_keys(test_id,keys)
select b.minsk_id,coalesce(v.keys,k.keys)
from brand_tests b join academy_private.test_keys k on k.test_id=b.id
left join brand_minsk_variants v on v.content_id=b.id and v.lesson_id=''
where b.minsk_id is not null and b.minsk_id<>b.id;

update public.academy_content t
set course_id=b.minsk_course, restaurant_id='minsk', updated_at=clock_timestamp(),
 payload=t.payload || jsonb_build_object('brand','rvb','trainingBrand','rvb','requiredRestaurantIds',jsonb_build_array('minsk'))
from brand_tests b where t.id=b.id and b.minsk_id=b.id;

update public.academy_content t
set payload=t.payload || jsonb_build_object('brand','90','trainingBrand','90','requiredRestaurantIds',
   (select jsonb_agg(v) from unnest(array['pushkino','khimki','mytishchi']) v
    where (t.restaurant_id is null or t.restaurant_id=v)
      and (not t.payload ? 'requiredRestaurantIds' or t.payload->'requiredRestaurantIds' ? v))),
 updated_at=clock_timestamp()
from brand_tests b where t.id=b.id and b.ninety;

with course_90 as (
 select b.id,coalesce(jsonb_object_agg(t.id,t.id) filter(where t.id is not null),'{}') all_ids,
  coalesce(jsonb_object_agg(t.id,t.id) filter(where t.ninety),'{}') own_ids
 from brand_courses b left join brand_tests t on t.course_id=b.id group by b.id
)
update public.academy_content c
set title=case c.id when 'welcome-90' then 'Добро пожаловать в команду — «90-е»'
                    when 'guru-42932' then 'Стажировка менеджера — «90-е»' else c.title end,
 payload=pg_temp.brand_training_steps(c.payload,b.all_ids,b.own_ids)
   || jsonb_build_object('title',case c.id when 'welcome-90' then 'Добро пожаловать в команду — «90-е»'
                 when 'guru-42932' then 'Стажировка менеджера — «90-е»' else c.title end,
       'brand','90','trainingBrand','90','requiredRestaurantIds',jsonb_build_array('pushkino','khimki','mytishchi')),
 updated_at=clock_timestamp()
from course_90 b where c.id=b.id;

update public.academy_content c set payload=c.payload || jsonb_build_object('brand','90','trainingBrand','90',
 'requiredRestaurantIds',jsonb_build_array('pushkino','khimki','mytishchi')),updated_at=clock_timestamp()
where c.id in ('guru-52664','guru-53164') or c.course_id in ('guru-52664','guru-53164');

update public.academy_course_media m set course_id='rvb--welcome-90'
from brand_album a
cross join lateral jsonb_array_elements(a.draft_lesson->'blocks') with ordinality b(value,n)
where b.n>12 and 'course-media:'||m.id=b.value->>'src';

update public.academy_progress p set course_id=c.minsk_id
from brand_before_progress before join brand_courses c on c.id=before.course_id
where p.user_id=before.user_id and p.course_id=before.course_id and p.lesson_id=before.lesson_id;

update public.academy_attempts a set test_id=t.minsk_id
from brand_before_attempts before join brand_tests t on t.id=before.test_id where a.id=before.id;

do $verify$
declare changed text;
begin
 if exists(select 1 from brand_before_progress b join brand_courses c on c.id=b.course_id
    where not exists(select 1 from public.academy_progress p where p.user_id=b.user_id and p.course_id=c.minsk_id
      and p.lesson_id=b.lesson_id and p.completed_at=b.completed_at))
 or exists(select 1 from brand_before_attempts b join brand_tests t on t.id=b.test_id
    where not exists(select 1 from public.academy_attempts a where a.id=b.id and a.test_id=t.minsk_id
      and row(a.score,a.total,a.passed,a.needs_review) is not distinct from row(b.score,b.total,b.passed,b.needs_review))) then
   raise exception 'Training history changed';
 end if;
 select string_agg(p.restaurant_id||':'||coalesce(p.position,'?'),', ')
 into changed
 from brand_before_status b join public.academy_profiles p on p.id=b.id
 where b.training_level is distinct from p.training_level or b.totals is distinct from
  (academy_private.general_training_status(p.id,p.restaurant_id,p.department,p.position) - array['courses','tests']);
 if changed is not null then raise exception 'Attestation totals changed: %',changed; end if;
end
$verify$;

-- This draft was used only to upload the new version's images.
delete from academy_private.course_drafts d using brand_album a
where d.course_id='welcome-90' and d.updated_at=a.draft_updated_at;

select jsonb_build_object('split_courses',(select count(*) from brand_courses),
 'cloned_tests',(select count(*) from brand_tests where minsk_id is not null and minsk_id<>id),
 'minsk_only_tests',(select count(*) from brand_tests where minsk_id=id),
 'progress_rows',(select count(*) from brand_before_progress),
 'attempts',(select count(*) from brand_before_attempts),
 'profiles_checked',(select count(*) from brand_before_status)) as result;

commit;
