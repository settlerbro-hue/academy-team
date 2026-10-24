begin;
create temporary table qa_position_alias(position text,department text,role text) on commit drop;
create trigger qa_alias before insert or update on qa_position_alias for each row execute function academy_private.normalize_position_record();
insert into qa_position_alias values('Руководитель','Руководитель','employee');
create temporary table qa_position_content(payload jsonb) on commit drop;
create trigger qa_content_alias before insert or update on qa_position_content for each row execute function academy_private.normalize_position_content();
insert into qa_position_content values('{"audiencePositions":["Руководитель","Бармен","Управляющий"],"audiencePriorities":{"Руководитель":"start","Управляющий":"additional","Бармен":"attestation"}}');
do $$ begin
 if not exists(select 1 from qa_position_alias where position='Управляющий' and department='Руководитель' and role='employee') then raise exception 'Position normalization changed scope or role';end if;
 if not exists(select 1 from qa_position_content where payload->'audiencePositions'='["Управляющий","Бармен"]'::jsonb and payload#>>'{audiencePriorities,Управляющий}'='start' and payload#>>'{audiencePriorities,Бармен}'='attestation' and not payload->'audiencePriorities' ? 'Руководитель') then raise exception 'Audience canonicalization failed';end if;
end $$;
rollback;
select 'Position alias checks passed; roles and departments unchanged' result;
