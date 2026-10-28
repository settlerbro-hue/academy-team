do $$
declare uid uuid:=gen_random_uuid(); admin_id uuid:=gen_random_uuid(); owner_id uuid; req uuid; p public.academy_profiles; denied boolean;
begin
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 insert into auth.users(id,aud,role,email) values(uid,'authenticated','authenticated','qa-network-'||uid||'@example.invalid'),(admin_id,'authenticated','authenticated','qa-network-'||admin_id||'@example.invalid');
 insert into public.academy_profiles(id,full_name,status,role,restaurant_id,department,position) values(admin_id,'QA local Admin','active','manager','minsk','Бар','Старший бармен') on conflict(id) do update set status='active',role='manager',restaurant_id='minsk',department='Бар',position='Старший бармен';
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';
 p:=public.academy_enroll('QA network','network','Руководитель','Управляющий');
 if p.status<>'pending' or p.role<>'employee' or p.operations_director or p.venue_director or p.restaurant_id<>'network' then raise exception 'Network enrollment widened access';end if;
 denied:=false;begin perform public.academy_enroll('QA network','network','Бар','Бармен');exception when others then denied:=true;end;if not denied then raise exception 'Network bartender allowed';end if;
 execute 'reset role';
 update public.academy_profiles set status='active',restaurant_id='minsk',department='Бар',position='Бармен' where id=uid;
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';req:=public.academy_request_work_change('network','Руководитель','Управляющий');execute 'reset role';
 if (select restaurant_id<>'minsk' from public.academy_profiles where id=uid) then raise exception 'Request immediately changed venue';end if;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.academy_assign_work(uid,'network','Руководитель','Управляющий');exception when others then denied:=true;end;if not denied then raise exception 'Local Admin assigned network affiliation';end if;
 denied:=false;begin perform public.academy_review_work_change(req,true);exception when others then denied:=true;end;if not denied then raise exception 'Local Admin approved network request';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_review_work_change(req,true);execute 'reset role';
 select * into p from public.academy_profiles where id=uid;
 if p.restaurant_id<>'network' or p.department<>'Руководитель' or p.position<>'Управляющий' or p.role<>'employee' or p.operations_director or p.venue_director then raise exception 'Approval altered permissions';end if;
 perform set_config('request.jwt.claim.sub',uid::text,true);execute 'set local role authenticated';
 denied:=false;begin perform public.academy_save_content('{"id":"qa-network-denied","kind":"material","title":"QA denied","restaurant_id":"khimki","department":"Бар","payload":{}}',null);exception when others then denied:=true;end;if not denied then raise exception 'Affiliation granted global editing';end if;
 execute 'reset role';perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';perform public.academy_assign_work(uid,'minsk','Бар','Бармен');execute 'reset role';
 if (select restaurant_id<>'minsk' from public.academy_profiles where id=uid) then raise exception 'Return to a real venue failed';end if;
end $$;
rollback;
select 'PASS: network enrollment remains pending employee; only leadership allowed; request, local Admin denial, owner approval, unchanged roles and no global editing, return to venue. All fixtures rolled back.' result;
