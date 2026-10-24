begin;
create or replace function academy_private.canonical_position_payload(p jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb:=p; positions jsonb; old_priority text; current_priority text; merged text;
begin
 if jsonb_typeof(p->'audiencePositions')='array' then
 select jsonb_agg(position order by first_n) into positions from(select case when value='Руководитель' then 'Управляющий' else value end position,min(n) first_n from jsonb_array_elements_text(p->'audiencePositions') with ordinality a(value,n) group by 1) v;
 result:=jsonb_set(result,'{audiencePositions}',coalesce(positions,'[]'::jsonb));
 end if;
 if p->'audiencePriorities' ? 'Руководитель' then
 old_priority:=p#>>'{audiencePriorities,Руководитель}';current_priority:=p#>>'{audiencePriorities,Управляющий}';
 merged:=case when current_priority is null or coalesce(array_position(array['start','attestation','additional'],old_priority),99)<coalesce(array_position(array['start','attestation','additional'],current_priority),99) then old_priority else current_priority end;
 result:=jsonb_set(result,'{audiencePriorities}',((p->'audiencePriorities')-'Руководитель')||jsonb_build_object('Управляющий',merged));
 end if;
 return result;
end $$;
revoke all on function academy_private.canonical_position_payload(jsonb) from public,anon,authenticated;
create or replace function academy_private.normalize_position_record() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.position='Руководитель' then new.position:='Управляющий';end if;
 return new;
end $$;
revoke all on function academy_private.normalize_position_record() from public,anon,authenticated;
create trigger academy_profile_position_alias before insert or update of position on public.academy_profiles for each row execute function academy_private.normalize_position_record();
create trigger academy_request_position_alias before insert or update of position on public.academy_work_changes for each row execute function academy_private.normalize_position_record();
create or replace function academy_private.normalize_position_content() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.payload:=academy_private.canonical_position_payload(new.payload);return new;
end $$;
revoke all on function academy_private.normalize_position_content() from public,anon,authenticated;
create trigger academy_content_position_alias before insert or update of payload on public.academy_content for each row execute function academy_private.normalize_position_content();
create or replace function academy_private.normalize_position_draft() returns trigger language plpgsql security definer set search_path='' as $$
begin
 new.document:=jsonb_set(new.document,'{payload}',academy_private.canonical_position_payload(new.document->'payload'));return new;
end $$;
revoke all on function academy_private.normalize_position_draft() from public,anon,authenticated;
create trigger academy_draft_position_alias before insert or update of document on academy_private.course_drafts for each row execute function academy_private.normalize_position_draft();
insert into academy_private.audit_log(actor_id,action,target,details) select auth.uid(),'position_alias_before',id::text,jsonb_build_object('position',position,'department',department,'role',role) from public.academy_profiles where position='Руководитель';
update public.academy_profiles set position='Управляющий' where position='Руководитель';
update public.academy_work_changes set position='Управляющий' where position='Руководитель' and status='pending';
update public.academy_content set payload=academy_private.canonical_position_payload(payload),updated_at=clock_timestamp() where payload is distinct from academy_private.canonical_position_payload(payload);
update academy_private.course_drafts set document=jsonb_set(document,'{payload}',academy_private.canonical_position_payload(document->'payload')),updated_at=clock_timestamp() where document->'payload' is distinct from academy_private.canonical_position_payload(document->'payload');
commit;
select (select count(*) from public.academy_profiles where position='Руководитель') legacy_profiles,(select count(*) from public.academy_content where payload->'audiencePositions' ? 'Руководитель' or payload->'audiencePriorities' ? 'Руководитель') legacy_audiences;
