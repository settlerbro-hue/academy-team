begin;
insert into auth.users(id,email) values
('00000000-0000-4000-8000-000000000021','rank-a@example.invalid'),
('00000000-0000-4000-8000-000000000022','rank-b@example.invalid'),
('00000000-0000-4000-8000-000000000023','rank-c@example.invalid');
insert into public.academy_profiles(id,full_name,restaurant_id,department,role,status) values
('00000000-0000-4000-8000-000000000021','Rank A','minsk','Зал','employee','active'),
('00000000-0000-4000-8000-000000000022','Rank B','khimki','Зал','employee','active'),
('00000000-0000-4000-8000-000000000023','Rank C','minsk','Бар','employee','active');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
do $$ declare r jsonb; begin
 r:=public.academy_ranking();
 if not r @> '[{"full_name":"Rank A"}]' or not r @> '[{"full_name":"Rank C"}]' or r @> '[{"full_name":"Rank B"}]' then raise exception 'FAIL employee ranking scope'; end if;
 if jsonb_path_exists(r,'$.**.answers') or jsonb_path_exists(r,'$.**.snapshot') or jsonb_path_exists(r,'$.**.email') then raise exception 'FAIL ranking exposes private fields'; end if;
end $$;
reset role;
update public.academy_profiles set role='manager' where id='00000000-0000-4000-8000-000000000021';
set local role authenticated;
do $$ declare r jsonb; begin
 r:=public.academy_ranking();
 if not r @> '[{"full_name":"Rank A"}]' or r @> '[{"full_name":"Rank C"}]' or r @> '[{"full_name":"Rank B"}]' then raise exception 'FAIL manager ranking scope'; end if;
end $$;
reset role;
update public.academy_profiles set status='pending' where id='00000000-0000-4000-8000-000000000021';
set local role authenticated;
do $$ begin if public.academy_ranking()<>'[]'::jsonb then raise exception 'FAIL inactive ranking access'; end if; end $$;
reset role;
select 'PASS ranking restaurant/manager scope, inactive denial, sanitized fields' as ranking_result;
rollback;
