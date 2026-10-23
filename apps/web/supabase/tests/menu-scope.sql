-- Supabase SQL Editor, postgres. Every fixture and profile change rolls back.
begin;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
select set_config('request.jwt.claims','{"sub":"4233956d-46bb-44c6-a266-759203b6648a","role":"authenticated"}',true);
select set_config('academy.qa_baseline',(select value::text from jsonb_array_elements(public.academy_ranking()) value where value->>'user_id'=auth.uid()::text),true);
insert into public.academy_content(id,kind,title,published,restaurant_id,department,payload) values
('qa-scope-rvb-bar','menu','QA RVB bar',true,null,null,'{"brand":"rvb","menuSection":"bar"}'),
('qa-scope-rvb-kitchen','menu','QA RVB kitchen',true,null,null,'{"brand":"rvb","menuSection":"kitchen"}'),
('qa-scope-90','menu','QA shared 90',true,null,null,'{"brand":"90","menuSection":"bar"}'),
('qa-scope-pushkino','menu','QA Pushkino',true,'pushkino',null,'{"brand":"90","menuSection":"kitchen"}'),
('qa-scope-khimki','menu','QA Khimki',true,'khimki',null,'{"brand":"90","menuSection":"bar"}'),
('qa-scope-minsk','menu','QA Minsk',true,'minsk',null,'{"brand":"rvb","menuSection":"bar"}'),
('qa-scope-draft','menu','QA draft',false,null,null,'{"brand":"rvb","menuSection":"bar"}');
insert into public.academy_menu_marks(user_id,item_id,status)
select auth.uid(),id,case when id='qa-scope-rvb-kitchen' then 'repeat' else 'learned' end
from public.academy_content where id like 'qa-scope-%';
set local role authenticated;
select public.academy_save_content('{"id":"qa-scope-created","kind":"menu","title":"QA kitchen draft","published":false,"restaurant_id":"minsk","department":"Бар","payload":{"brand":"rvb","menuSection":"kitchen","name":"QA kitchen draft"}}'::jsonb,null);
with r as (select value as j from jsonb_array_elements(public.academy_ranking()) value where value->>'user_id'=auth.uid()::text),
d as (select value as j from jsonb_array_elements(public.academy_manager_dashboard()->'menu_stats') value where value->>'user_id'=auth.uid()::text),
b as (select current_setting('academy.qa_baseline')::jsonb as j)
select 1/(case when (r.j->>'menu_learned')::int=(b.j->>'menu_learned')::int+2
and (r.j->>'menu_repeat')::int=(b.j->>'menu_repeat')::int+1 and (r.j->>'menu_total')::int=(b.j->>'menu_total')::int+3
and (d.j->>'learned')::int=(r.j->>'menu_learned')::int and (d.j->>'total')::int=(r.j->>'menu_total')::int
and not exists(select 1 from public.academy_content where id in ('qa-scope-pushkino','qa-scope-khimki')) then 1 else 0 end) as rvb_scope_assertion from r,d,b;
reset role;
-- Simulate a move to each 90-е branch. Marks stay in place but eligible totals change.
update public.academy_profiles set restaurant_id='pushkino' where id=auth.uid();
set local role authenticated;
select 1/(case when (value->>'menu_learned')::int=2 and (value->>'menu_total')::int=2 then 1 else 0 end) as branch_scope_assertion from jsonb_array_elements(public.academy_ranking()) value where value->>'user_id'=auth.uid()::text;
reset role;
update public.academy_profiles set restaurant_id='mytishchi' where id=auth.uid();
set local role authenticated;
select 1/(case when (value->>'menu_learned')::int=1 and (value->>'menu_total')::int=1 then 1 else 0 end) as branch_scope_assertion from jsonb_array_elements(public.academy_ranking()) value where value->>'user_id'=auth.uid()::text;
reset role;
rollback;
select 'PASS: own restaurant, shared brand, bar + kitchen, foreign marks excluded, ranking / manager agreement, RLS unchanged; fixtures rolled back' as result;
