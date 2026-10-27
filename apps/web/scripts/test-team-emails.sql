begin;
do $$
declare member record; result jsonb; denied boolean;
begin
 for member in select * from public.academy_profiles
 loop
  perform set_config('request.jwt.claim.sub',member.id::text,true);denied:=false;
  execute 'set local role authenticated';
  begin
   result:=public.academy_owner_team_emails();
  exception when insufficient_privilege then denied:=true;
  end;
  execute 'reset role';
  if member.role='admin' and member.status='active' then
   if denied or jsonb_array_length(result)<>(select count(*) from public.academy_profiles p join auth.users u on u.id=p.id) then raise exception 'Owner contacts missing';end if;
   if exists(select 1 from jsonb_array_elements(result) x where x-ARRAY['user_id','email']<>'{}'::jsonb) then raise exception 'Unexpected auth fields exposed';end if;
  elsif not denied then raise exception 'Email access leaked to unauthorized profile';
  end if;
 end loop;
 if has_function_privilege('anon','public.academy_owner_team_emails()','execute') then raise exception 'Anonymous access leaked';end if;
end $$;
rollback;
select 'PASS: owner contact list complete; other profiles and anonymous users denied; only id and email returned' result;
