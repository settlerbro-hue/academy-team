-- Approval shortcut uses the existing employee approval authority; no role changes.
begin;
CREATE OR REPLACE FUNCTION public.academy_notifications(p_limit integer DEFAULT 30, p_unread boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.academy_profiles;r jsonb;
begin
 select * into p from public.academy_profiles where id=auth.uid();if p.id is null then raise exception 'Войдите в аккаунт.';end if;
 perform academy_private.refresh_notices(p);
 select jsonb_build_object('as_of',clock_timestamp(),'unread',(select count(*) from academy_private.notifications n where n.read_at is null and academy_private.notice_visible(n,p)),
 'total',(select count(*) from academy_private.notifications n where academy_private.notice_visible(n,p) and (not p_unread or n.read_at is null)),
 'items',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc) from
 (select n.id,n.category,n.title,n.body,n.route,n.created_at,n.read_at,
 (select jsonb_build_object('status',m.status,'can_approve',p.status='active' and m.status='pending' and m.role='employee' and m.id<>p.id and academy_private.can_manage(m.id),'restaurant_id',m.restaurant_id,'department',m.department,'position',m.position,'position_caption',m.position_caption) from public.academy_profiles m where m.id=n.subject_id and n.scope='team' and n.category='team' and n.event_key='enrollment:'||m.id::text and academy_private.can_manage(m.id)) as enrollment,
 coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.title,'kind',c.kind) order by c.title) from public.academy_content c where c.id=any(n.content_ids) and academy_private.notice_content_for(p,c)),'[]'::jsonb) as targets
 from academy_private.notifications n where academy_private.notice_visible(n,p) and (not p_unread or n.read_at is null) order by n.created_at desc,n.id desc limit greatest(1,least(coalesce(p_limit,30),200))) x),'[]'::jsonb)) into r;return r;
end $function$;
create or replace function public.academy_approve_enrollment_notice(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; n academy_private.notifications; already_active boolean;
begin
 select * into actor from public.academy_profiles where id=auth.uid() and status='active';
 if actor.id is null then raise exception 'Доступ закрыт';end if;
 select * into n from academy_private.notifications where id=p_id and user_id=actor.id for update;
 if n.id is null or n.scope<>'team' or n.category<>'team' or n.event_key is distinct from 'enrollment:'||n.subject_id::text or not academy_private.notice_visible(n,actor) then raise exception 'Заявка недоступна';end if;
 select * into member from public.academy_profiles where id=n.subject_id for update;
 if member.id is null or member.id=actor.id or member.role<>'employee' or not academy_private.can_manage(member.id) then raise exception 'Нет права подтверждать этого сотрудника';end if;
 if member.status not in ('pending','active') then raise exception 'Заявка уже неактуальна. Обновите уведомления';end if;
 already_active:=member.status='active';
 if not already_active then perform public.academy_manage_member(member.id,'active','employee');end if;
 update academy_private.notifications set read_at=coalesce(read_at,clock_timestamp()) where id=n.id and user_id=actor.id;
 return jsonb_build_object('status','active','already_active',already_active);
end $$;
revoke all on function public.academy_approve_enrollment_notice(uuid) from public,anon;
grant execute on function public.academy_approve_enrollment_notice(uuid) to authenticated;

do $$
declare owner_id uuid; ops_id uuid; ids uuid[]:=array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid(),gen_random_uuid()]; uid uuid; n uuid; wrong uuid; result jsonb; item jsonb; denied boolean; expected boolean; actor uuid; rest text;
begin
 select id into owner_id from public.academy_profiles where role='admin' and status='active' limit 1;
 select id into ops_id from public.academy_profiles where operations_director and status='active';
 for i in 1..9 loop
  uid:=ids[i];insert into auth.users(id,aud,role,email) values(uid,'authenticated','authenticated','qa-notice-approval-'||uid||'@example.invalid');
  insert into public.academy_profiles(id,full_name,status,role,restaurant_id,department,position) values(uid,'QA approval '||i,case when i<=3 then 'active' else 'pending' end,case when i=1 then 'manager' else 'employee' end,case when i=3 then 'khimki' when i=6 then 'pushkino' when i=7 then 'khimki' when i=8 then 'mytishchi' when i=9 then 'network' else 'minsk' end,case when i in (3,9) then 'Руководитель' when i in (5,8) then 'Зал' when i=7 then 'Кухня' else 'Бар' end,case when i=3 then 'Управляющий' when i=9 then 'Управляющая компания' when i in (5,8) then 'Официант' when i=7 then 'Повар' else 'Бармен' end)
  on conflict(id) do update set full_name=excluded.full_name,status=excluded.status,role=excluded.role,restaurant_id=excluded.restaurant_id,department=excluded.department,position=excluded.position;
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);perform public.academy_set_venue_director(ids[3],true);
 -- Issue actual enrollment-shaped notices to the local Admin, ordinary employee,
 -- venue director, owner and operations director, including invisible foreign targets.
 foreach actor in array array[ids[1],ids[2],ids[3],owner_id,ops_id] loop
  for i in 4..9 loop perform academy_private.emit_notice(actor,'enrollment:'||ids[i],'team','Новая заявка сотрудника','QA','#/manager','team',ids[i]);end loop;
 end loop;
 -- Ordinary Admin sees only their own department, with server-supplied action details.
 select id into n from academy_private.notifications where user_id=ids[1] and event_key='enrollment:'||ids[4];
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);execute 'set local role authenticated';
 result:=public.academy_notifications(200,false);select value into item from jsonb_array_elements(result->'items') where value->>'id'=n::text;
 if item is null or item->'enrollment'->'can_approve' is distinct from 'true'::jsonb then raise exception 'Own pending action missing';end if;
 n:=(item->>'id')::uuid;result:=public.academy_approve_enrollment_notice(n);if result->>'status'<>'active' then raise exception 'Approval failed';end if;
 result:=public.academy_approve_enrollment_notice(n);if result->'already_active' is distinct from 'true'::jsonb then raise exception 'Replay not idempotent';end if;
 result:=public.academy_notifications(200,false);select value into item from jsonb_array_elements(result->'items') where value->>'id'=n::text;if item->'enrollment'->'can_approve' is distinct from 'false'::jsonb or item->>'read_at' is null then raise exception 'Accepted status/read marker wrong';end if;
 execute 'reset role';
 if (select status<>'active' or role<>'employee' or operations_director or venue_director from public.academy_profiles where id=ids[4]) then raise exception 'Approval changed role';end if;
 -- A known notice ID from another inbox is unusable, even for an owner.
 perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';denied:=false;begin perform public.academy_approve_enrollment_notice(n);exception when others then denied:=true;end;if not denied then raise exception 'Foreign inbox notice accepted';end if;execute 'reset role';
 foreach actor in array array[ids[1],ids[2]] loop
  select id into n from academy_private.notifications where user_id=actor and event_key='enrollment:'||ids[5];
  perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';denied:=false;begin perform public.academy_approve_enrollment_notice(n);exception when others then denied:=true;end;if not denied then raise exception 'Foreign department/employee approval allowed';end if;execute 'reset role';
 end loop;
 -- The 90-е venue director can approve all three venues but not RVB.
 for i in 5..8 loop
  select id into n from academy_private.notifications where user_id=ids[3] and event_key='enrollment:'||ids[i];expected:=i>=6;
  perform set_config('request.jwt.claim.sub',ids[3]::text,true);execute 'set local role authenticated';denied:=false;begin perform public.academy_approve_enrollment_notice(n);exception when others then denied:=true;end;if denied=expected then raise exception 'Venue director boundary %',i;end if;execute 'reset role';
 end loop;
 -- Owner approves own valid remaining application; operations handles network.
 foreach actor in array array[owner_id,ops_id] loop
  uid:=case when actor=owner_id then ids[5] else ids[9] end;select id into n from academy_private.notifications where user_id=actor and event_key='enrollment:'||uid;
  perform set_config('request.jwt.claim.sub',actor::text,true);execute 'set local role authenticated';perform public.academy_approve_enrollment_notice(n);execute 'reset role';
  if (select status<>'active' or role<>'employee' or operations_director or venue_director from public.academy_profiles where id=uid) then raise exception 'Global approver changed role';end if;
 end loop;
 -- Stale suspended users cannot be reactivated through an old enrollment notice.
 update public.academy_profiles set status='suspended' where id=ids[4];select id into n from academy_private.notifications where user_id=ids[1] and event_key='enrollment:'||ids[4];
 perform set_config('request.jwt.claim.sub',ids[1]::text,true);execute 'set local role authenticated';denied:=false;begin perform public.academy_approve_enrollment_notice(n);exception when others then denied:=true;end;if not denied then raise exception 'Stale notice reactivated suspended account';end if;execute 'reset role';
 -- A general team event cannot masquerade as an enrollment approval.
 perform academy_private.emit_notice(owner_id,'qa-non-enrollment','team','QA','QA','#/manager','team',ids[5]);select id into wrong from academy_private.notifications where user_id=owner_id and event_key='qa-non-enrollment';
 perform set_config('request.jwt.claim.sub',owner_id::text,true);execute 'set local role authenticated';denied:=false;begin perform public.academy_approve_enrollment_notice(wrong);exception when others then denied:=true;end;if not denied then raise exception 'Wrong event accepted';end if;execute 'reset role';
end $$;
rollback;
select 'PASS: local Admin approval, idempotent replay, read marker, own inbox only, foreign department and ordinary employee denied, all three 90-е venues and RVB boundary, owner and operations/network, roles preserved, suspended/wrong events denied. All fixtures rolled back.' result;
