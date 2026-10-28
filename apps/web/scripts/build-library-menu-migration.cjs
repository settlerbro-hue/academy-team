const fs=require('node:fs'),path=require('node:path');
const root=path.join(__dirname,'..'),source=JSON.parse(fs.readFileSync(path.join(root,'supabase/sources/library-menu-server-before-20261028.json'),'utf8'));
const helper=`create or replace function academy_private.library_audience_for(p public.academy_profiles,c public.academy_content)
returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(c.kind<>'material' or c.payload->'libraryAccess'->'enabled' is distinct from 'true'::jsonb
 or p.role='admin' or p.operations_director
 or (p.venue_director and academy_private.venue_document(p,c,false))
 or (p.role='manager' and c.restaurant_id=p.restaurant_id and c.department=p.department)
 or (c.payload->'libraryAccess'->'departments' ? p.department and c.payload->'libraryAccess'->'positions' ? p.position),false)
$$;
create or replace function academy_private.validate_library_access(c public.academy_content)
returns void language plpgsql set search_path='' as $$
declare a jsonb:=c.payload->'libraryAccess'; d text; j text;
begin
 if c.kind<>'material' or a is null then return;end if;
 if jsonb_typeof(a) is distinct from 'object' or jsonb_typeof(a->'enabled') is distinct from 'boolean' then raise exception 'Некорректная настройка доступа';end if;
 if a->'enabled'='false'::jsonb then return;end if;
 if jsonb_typeof(a->'departments') is distinct from 'array' or jsonb_typeof(a->'positions') is distinct from 'array' then raise exception 'Выберите подразделения и должности';end if;
 if jsonb_array_length(a->'departments') not between 1 and 6 or jsonb_array_length(a->'positions') not between 1 and 13 then raise exception 'Выберите подразделения и должности';end if;
 if (select count(distinct value) from jsonb_array_elements(a->'departments'))<>jsonb_array_length(a->'departments') or (select count(distinct value) from jsonb_array_elements(a->'positions'))<>jsonb_array_length(a->'positions') then raise exception 'Повторяющиеся значения доступа';end if;
 for d in select jsonb_array_elements_text(a->'departments') loop
  if d not in ('Зал','Бар','Кухня','Арт','Кальян','Руководитель') or (c.department is not null and c.department<>d) then raise exception 'Подразделение вне области материала';end if;
 end loop;
 for j in select jsonb_array_elements_text(a->'positions') loop
  if j not in ('Официант','Администратор зала','Хостес','Старший бармен','Барбэк','Бармен','Бар-менеджер','Повар','Шеф-повар','Сотрудник арт','Кальянный мастер','Старший кальянный мастер','Управляющий')
   or not exists(select 1 from jsonb_array_elements_text(a->'departments') x where academy_private.valid_work('minsk',x,j)) then raise exception 'Должность вне выбранных подразделений';end if;
 end loop;
end $$;
create or replace function academy_private.validate_menu_news(p jsonb)
returns void language plpgsql set search_path='' as $$
declare until_at timestamptz;
begin
 if not p ? 'isNewItem' then return;end if;
 if jsonb_typeof(p->'isNewItem') is distinct from 'boolean' then raise exception 'Некорректная отметка новинки';end if;
 if p->'isNewItem'='false'::jsonb then return;end if;
 begin until_at:=(p->>'newBadgeUntil')::timestamptz;exception when others then raise exception 'Укажите дату окончания новинки';end;
 if until_at is null or not isfinite(until_at) or until_at<=clock_timestamp() then raise exception 'Дата окончания новинки должна быть в будущем';end if;
end $$;
revoke all on function academy_private.library_audience_for(public.academy_profiles,public.academy_content) from public,anon,authenticated;
revoke all on function academy_private.validate_library_access(public.academy_content) from public,anon,authenticated;
revoke all on function academy_private.validate_menu_news(jsonb) from public,anon,authenticated;
`;
const get=n=>source.find(f=>f.name===n).definition.replace(/\r/g,'');
let read=get('can_read_content');read=read.replace("and case when p.venue_director", "and academy_private.library_audience_for(p,c) and case when p.venue_director");
let notice=get('notice_content_for');notice=notice.replace('select case when p.venue_director','select academy_private.library_audience_for(p,c) and case when p.venue_director');
let save=get('academy_save_content');save=save.replace(' -- Keys must never'," perform academy_private.validate_library_access(jsonb_populate_record(null::public.academy_content,p_document));\n -- Keys must never");
let menu=get('academy_save_menu');menu=menu.replace(" proposed:=jsonb_populate_record", " perform academy_private.validate_menu_news(p_document->'payload');\n proposed:=jsonb_populate_record");
for(const [n,s] of Object.entries({read,notice,save,menu}))if(!s.includes(n==='read'||n==='notice'?'library_audience_for':n==='save'?'validate_library_access':'validate_menu_news'))throw Error('Patch missing '+n);
fs.writeFileSync(path.join(root,'supabase/migrations/034_library_access_and_menu_new.sql'),'-- Optional library audiences; existing rows and availability are unchanged.\nbegin;\n'+helper+[read,notice,save,menu].map(s=>s.trim()+';').join('\n')+'\ncommit;\n');
console.log('Migration 034 built without modifying content rows.');
