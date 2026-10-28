const fs=require('node:fs'),path=require('node:path'),root=path.join(__dirname,'..'),file=path.join(root,'secure-dist/portal.js');let src=fs.readFileSync(file,'utf8');
if(!src.includes('function companyCaptionField(')){
 const helpers=`function displayPosition(p){return p?.restaurant_id==='network'&&p.position_caption?p.position_caption:p?.position||'';}\nfunction companyCaptionField(p={},name='position_caption'){return '<label class="field company-caption-field" '+(p.restaurant_id==='network'?'':'hidden')+'>Ваша должность (подпись)<input type="text" name="'+name+'" maxlength="100" placeholder="Например, руководитель обучения" value="'+esc(p.position_caption||'')+'" '+(p.restaurant_id==='network'?'':'disabled')+'><small>Свободная подпись для профиля. Права доступа не меняет.</small></label>';}\n`;
 src=src.replace('function bindWorkScope(',helpers+'function bindWorkScope(');
 const old=src.split('\n').find(l=>l.startsWith('function bindWorkScope('));
 const fresh=old.replace("values=departments[d.value]||[]", "values=r.value==='network'?['Управляющая компания']:departments[d.value]||[]").replace("if(network)p.value='Управляющий';", "if(network)p.value='Управляющая компания';const caption=form.elements[positionName==='position'?'position_caption':'work_position_caption'];if(caption){caption.disabled=!network;caption.closest('label').hidden=!network;}");src=src.replace(old,fresh);
 src=src.replace("p.position||'','Выберите должность')+'</select></label>';}","p.position||'','Выберите должность')+'</select></label>'+companyCaptionField(p,'work_position_caption');}");
 src=src.replace('</option></select></label><button class="primary wide">Отправить заявку', '</option></select></label>${companyCaptionField()}<button class="primary wide">Отправить заявку');
 src=src.replace("p_position:form.position.value});await load();", "p_position:form.position.value});if(form.restaurant.value==='network')await rpc('academy_set_position_caption',{p_caption:form.position_caption.value,p_user_id:s.session.user.id});await load();");
 src=src.replace("if(f.dataset.mode==='assign')await rpc('academy_assign_work',{p_user_id:f.dataset.user,...args});else await rpc('academy_request_work_change',args);", "const assigned=f.dataset.mode==='assign',request=assigned?await rpc('academy_assign_work',{p_user_id:f.dataset.user,...args}):await rpc('academy_request_work_change',args);if(args.p_restaurant_id==='network')await rpc('academy_set_position_caption',{p_caption:data.get('work_position_caption'),p_user_id:assigned?f.dataset.user:null,p_request_id:assigned?null:request});");
 src=src.replace("p.full_name)}${field('Дата рождения'", "p.full_name)}${p.restaurant_id==='network'?companyCaptionField(p):''}${field('Дата рождения'");
 src=src.replace("await rpc('academy_update_profile',data);await load();", "await rpc('academy_update_profile',data);if(fd.has('position_caption'))await rpc('academy_set_position_caption',{p_caption:fd.get('position_caption'),p_user_id:form.dataset.user});await load();");
 src=src.replace("positionLabel=()=>s.profile?.position||", "positionLabel=()=>displayPosition(s.profile)||");
 for(const p of ['p','member','m']){src=src.replaceAll('esc('+p+".position||'')",'esc(displayPosition('+p+'))').replaceAll('esc('+p+'.position)', 'esc(displayPosition('+p+'))');}
 src=src.replace("esc(r.position)+'</p>","esc(r.restaurant_id==='network'&&r.position_caption?r.position_caption:r.position)+'</p>");
 fs.writeFileSync(file,src);
}
const base=fs.readFileSync(path.join(root,'supabase/migrations/035_network_work_selection.sql'),'utf8');
const get=n=>{const start=base.indexOf('CREATE OR REPLACE FUNCTION '+(n==='valid_work'?'academy_private.':'public.')+n+'(');if(start<0)throw Error(n);const end=base.indexOf('$function$;',base.indexOf('AS $function$',start)+14);return base.slice(start,end+12);};
let valid=get('valid_work').replace("p_restaurant='network' and p_department='Руководитель' and p_position='Управляющий'","p_restaurant='network' and p_department='Руководитель' and p_position='Управляющая компания'");
let assign=get('academy_assign_work').replace('position=p_position,updated_at','position=p_position,position_caption=case when p_restaurant_id=\'network\' then position_caption else null end,updated_at');
let review=get('academy_review_work_change').replace('position=request.position,updated_at',"position=request.position,position_caption=case when request.restaurant_id='network' then request.position_caption else null end,updated_at");
let enroll=get('academy_enroll').replace('position=excluded.position,updated_at',"position=excluded.position,position_caption=case when excluded.restaurant_id='network' then academy_profiles.position_caption else null end,updated_at");
const sql=`-- Canonical network job and a display-only personal caption. No role or permission grants.
begin;
alter table public.academy_profiles add column position_caption text;
alter table public.academy_work_changes add column position_caption text;
alter table public.academy_profiles drop constraint academy_network_work_identity;
alter table public.academy_work_changes drop constraint academy_network_request_identity;
update public.academy_profiles set position='Управляющая компания' where restaurant_id='network';
update public.academy_work_changes set position='Управляющая компания' where restaurant_id='network';
update public.academy_work_changes set from_position='Управляющая компания' where from_restaurant='network';
alter table public.academy_profiles add constraint academy_network_work_identity check(restaurant_id is distinct from 'network' or coalesce(department='Руководитель' and position='Управляющая компания',false));
alter table public.academy_work_changes add constraint academy_network_request_identity check(restaurant_id<>'network' or department='Руководитель' and position='Управляющая компания');
alter table public.academy_profiles add constraint academy_caption_value check(position_caption is null or (restaurant_id='network' and char_length(position_caption) between 1 and 100 and position_caption !~ '[[:cntrl:]]'));
alter table public.academy_work_changes add constraint academy_request_caption_value check(position_caption is null or (restaurant_id='network' and char_length(position_caption) between 1 and 100 and position_caption !~ '[[:cntrl:]]'));
${[valid,assign,review,enroll].join('\n')}
create or replace function public.academy_set_position_caption(p_caption text,p_user_id uuid default null,p_request_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare actor public.academy_profiles; member public.academy_profiles; r public.academy_work_changes; caption text:=nullif(trim(p_caption),'');target uuid:=coalesce(p_user_id,auth.uid());
begin
 if auth.uid() is null or (p_user_id is not null and p_request_id is not null) then raise exception 'Доступ закрыт';end if;
 if caption is not null and (char_length(caption)>100 or caption ~ '[[:cntrl:]]') then raise exception 'Подпись: одна строка, до 100 символов';end if;
 select * into actor from public.academy_profiles where id=auth.uid();
 if actor.id is null or actor.status not in ('active','pending') then raise exception 'Доступ закрыт';end if;
 if p_request_id is not null then
  select * into r from public.academy_work_changes where id=p_request_id for update;
  if r.id is null or r.status<>'pending' or r.restaurant_id<>'network' or actor.status<>'active' or not (r.user_id=actor.id or (actor.role='admin' or actor.operations_director) and academy_private.can_manage(r.user_id)) then raise exception 'Заявка недоступна';end if;
  update public.academy_work_changes set position_caption=caption where id=r.id;
 else
  select * into member from public.academy_profiles where id=target for update;
  if member.id is null or member.restaurant_id<>'network' or actor.status not in ('active','pending') or not (member.id=actor.id or actor.status='active' and academy_private.can_manage(member.id)) then raise exception 'Профиль недоступен';end if;
  update public.academy_profiles set position_caption=caption,updated_at=now() where id=member.id;
 end if;
 insert into academy_private.audit_log(actor_id,action,target) values(auth.uid(),'position_caption',coalesce(p_request_id,target)::text);
end $$;
revoke all on function public.academy_set_position_caption(text,uuid,uuid) from public,anon;
grant execute on function public.academy_set_position_caption(text,uuid,uuid) to authenticated;
commit;
`;
fs.writeFileSync(path.join(root,'supabase/migrations/036_company_position_caption.sql'),sql);console.log('Company position and personal caption prepared.');
