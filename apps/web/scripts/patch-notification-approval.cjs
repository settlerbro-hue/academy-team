const fs=require('node:fs'),path=require('node:path'),root=path.join(__dirname,'..'),file=path.join(root,'secure-dist/notifications.js');let src=fs.readFileSync(file,'utf8');
if(!src.includes('function enrollmentActions(')){
 src=src.replace('getProfile,openRoute,render})','getProfile,openRoute,render,onMemberApproved=async()=>{}})');
 src=src.replace("onlyUnread:false,error:'',loading:false", "onlyUnread:false,error:'',message:'',loading:false");
 const helper=`function enrollmentDetails(n){const e=n.enrollment;if(!e)return '';const venues={minsk:'Руки Вверх Бар Минск',pushkino:'90-е Пушкино',khimki:'90-е Химки',mytishchi:'90-е Мытищи',network:'МХП & РВБ'};return '<p class="notification-enrollment">'+[venues[e.restaurant_id],e.department,e.position_caption||e.position].filter(Boolean).map(esc).join(' · ')+'</p>';}\n function enrollmentActions(n){const e=n.enrollment;if(!e)return '';if(e.can_approve===true)return '<button class="primary" data-notification-approve="'+esc(n.id)+'" '+(state.loading?'disabled':'')+'>Одобрить сотрудника</button>';return e.status==='active'?'<span class="notification-approved">✓ Сотрудник одобрен</span>':'';}\n `;
 src=src.replace('function view(){',helper+'function view(){');
 src=src.replace("+'<div class=\"notification-list\">'", "+(state.message?'<p class=\"message\" role=\"status\">'+esc(state.message)+'</p>':'')+'<div class=\"notification-list\">'");
 src=src.replace("+(n.targets?.length>1?", "+enrollmentDetails(n)+(n.targets?.length>1?");
 src=src.replace("+'<div class=\"notification-actions\"><button", "+'<div class=\"notification-actions\">'+enrollmentActions(n)+'<button");
 src=src.replace('state.loading=true;try{await fn();',"state.loading=true;state.message='';try{await fn();");
 const handler=`root.querySelectorAll('[data-notification-approve]').forEach(b=>b.onclick=()=>{if(state.loading||!state.items.some(n=>n.id===b.dataset.notificationApprove&&n.enrollment?.can_approve===true))return;return action(async()=>{const owner=scope();b.disabled=true;b.textContent='Одобряем…';const result=await rpc('academy_approve_enrollment_notice',{p_id:b.dataset.notificationApprove});if(owner!==scope())return;state.message=result?.already_active?'Сотрудник уже одобрен.':'Доступ сотруднику открыт.';try{await onMemberApproved();}catch{/* Refresh the team on its next opening. Approval has already succeeded. */}});});\n `;
 src=src.replace("root.querySelector('#notification-refresh')",handler+"root.querySelector('#notification-refresh')");
 src=src.replace("error:'',onlyUnread:false", "error:'',message:'',loading:false,onlyUnread:false");
 fs.writeFileSync(file,src);
 const portalFile=path.join(root,'secure-dist/portal.js');let p=fs.readFileSync(portalFile,'utf8');p=p.replace('getProfile:()=>s.profile,render,openRoute:', 'getProfile:()=>s.profile,render,onMemberApproved:async()=>{s.team=null;await loadTeam();},openRoute:');fs.writeFileSync(portalFile,p);
 fs.appendFileSync(path.join(root,'secure-dist/notifications.css'),'\n.notification-enrollment{font-size:12px;color:#75695d;line-height:1.55;overflow-wrap:anywhere}.notification-approved{color:#248147;font-weight:700}.notification-actions [data-notification-approve]{white-space:normal;max-width:100%;min-height:42px}@media(max-width:380px){.notification-actions [data-notification-approve]{flex-basis:100%}}\n');
}
const snapshot=JSON.parse(fs.readFileSync(path.join(root,'supabase/sources/notification-approval-before-20261028.json'),'utf8'));
let inbox=snapshot.find(f=>f.name==='academy_notifications').definition.replace(/\r/g,'').trim();
const anchor='(select n.id,n.category,n.title,n.body,n.route,n.created_at,n.read_at,';
if(!inbox.includes(anchor))throw Error('Inbox anchor missing');
inbox=inbox.replace(anchor,anchor+`\n (select jsonb_build_object('status',m.status,'can_approve',p.status='active' and m.status='pending' and m.role='employee' and m.id<>p.id and academy_private.can_manage(m.id),'restaurant_id',m.restaurant_id,'department',m.department,'position',m.position,'position_caption',m.position_caption) from public.academy_profiles m where m.id=n.subject_id and n.scope='team' and n.category='team' and n.event_key='enrollment:'||m.id::text and academy_private.can_manage(m.id)) as enrollment,`);
const sql=`-- Approval shortcut uses the existing employee approval authority; no role changes.
begin;
${inbox};
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
`;
fs.writeFileSync(path.join(root,'supabase/migrations/037_notification_employee_approval.sql'),sql);console.log('Notification approval prepared with unchanged role authority.');
