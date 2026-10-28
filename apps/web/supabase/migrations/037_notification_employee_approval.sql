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
commit;
