const fs=require('fs'),path=require('path'),base=path.resolve(__dirname,'..');
// Rebuild only the SQL from the verified server snapshot.
const defs=JSON.parse(fs.readFileSync(path.join(base,'supabase/sources/position-functions-before-20261027.json'),'utf8'));
const sql=['-- Rename jobs and add the senior hookah job. Existing access roles and learning history are preserved.','begin;'];
for(const d of defs){let text=d.definition.replace(/\r\n/g,'\n').replaceAll("'Администратор'","'Администратор зала'").replaceAll("'Сотрудник кухни'","'Повар'");
 if(['valid_work','academy_enroll'].includes(d.name))text=text.replaceAll("p_position='Сотрудник кальянного подразделения'","p_position in ('Кальянный мастер','Старший кальянный мастер')");
 else text=text.replaceAll("'Сотрудник кальянного подразделения'","'Кальянный мастер','Старший кальянный мастер'");
 if(d.name==='valid_work')text=text.replace(",'Операционный директор'",'');
 if(d.name==='academy_set_course_audience')text=text.replace('not between 1 and 13','not between 1 and cardinality(allowed)');
 sql.push(text.trim()+';');
}
sql.push(`create or replace function pg_temp.rename_positions(v jsonb) returns jsonb language plpgsql as $$
declare result jsonb; e record; item jsonb; k text; target text;
begin
 if jsonb_typeof(v)='string' then return to_jsonb(case v#>>'{}' when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else v#>>'{}' end);end if;
 if jsonb_typeof(v)='array' then
  result:='[]';for item in select value from jsonb_array_elements(v) loop
   if item='"Сотрудник кальянного подразделения"'::jsonb then result:=result||jsonb_build_array('Кальянный мастер','Старший кальянный мастер');else result:=result||jsonb_build_array(pg_temp.rename_positions(item));end if;
  end loop;return result;
 end if;
 if jsonb_typeof(v)='object' then
  result:='{}';for e in select * from jsonb_each(v) loop
   if e.key='Сотрудник кальянного подразделения' then
    foreach target in array array['Кальянный мастер','Старший кальянный мастер'] loop if not v ? target then result:=result||jsonb_build_object(target,pg_temp.rename_positions(e.value));end if;end loop;
   else k:=case e.key when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' else e.key end;
    if k=e.key or not v ? k then result:=result||jsonb_build_object(k,pg_temp.rename_positions(e.value));end if;
   end if;
  end loop;return result;
 end if;return v;
end $$;
create temp table position_identity_before on commit drop as select id,role,status,operations_director,restaurant_id,department from public.academy_profiles;
create temp table position_old_content_versions on commit drop as select id,updated_at from public.academy_content;
update public.academy_profiles set position=case position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' end,updated_at=now() where position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения');
update public.academy_work_changes set position=case position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else position end,from_position=case from_position when 'Администратор' then 'Администратор зала' when 'Сотрудник кухни' then 'Повар' when 'Сотрудник кальянного подразделения' then 'Кальянный мастер' else from_position end where position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения') or from_position in ('Администратор','Сотрудник кухни','Сотрудник кальянного подразделения');
update public.academy_content set payload=pg_temp.rename_positions(payload),updated_at=now() where payload is distinct from pg_temp.rename_positions(payload);
update academy_private.course_drafts d set document=pg_temp.rename_positions(d.document),base_updated_at=case when d.base_updated_at=o.updated_at then c.updated_at else d.base_updated_at end from public.academy_content c join position_old_content_versions o on o.id=c.id where d.course_id=c.id;
do $verify$ begin if exists(select 1 from position_identity_before b join public.academy_profiles p using(id) where row(b.role,b.status,b.operations_director,b.restaurant_id,b.department) is distinct from row(p.role,p.status,p.operations_director,p.restaurant_id,p.department)) then raise exception 'Position rename changed access identity';end if;end $verify$;
commit;
select full_name,role,position,restaurant_id,department,operations_director from public.academy_profiles where status='active' and (role in ('admin','manager') or department='Руководитель') order by role,full_name;`);
fs.writeFileSync(path.join(base,'supabase/migrations/032_position_names.sql'),sql.join('\n')+'\n');
console.log({functions:defs.length,positionMigration:'032_position_names.sql'});
