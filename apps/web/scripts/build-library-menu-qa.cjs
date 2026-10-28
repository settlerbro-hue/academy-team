const fs=require('node:fs'),path=require('node:path'),root=path.join(__dirname,'..');
const prefix=`begin;
create temporary table qa_library_before(uid uuid,cid text,allowed boolean) on commit drop;
do $$ declare p record;begin for p in select id from public.academy_profiles loop
 perform set_config('request.jwt.claim.sub',p.id::text,true);
 insert into qa_library_before select p.id,c.id,academy_private.can_read_content(c.id) from public.academy_content c where kind='material';
end loop;end $$;
`;
const sql=fs.readFileSync(path.join(root,'supabase/migrations/034_library_access_and_menu_new.sql'),'utf8').replace(/^begin;$/m,'').replace(/^commit;$/m,'');
fs.writeFileSync(path.join(root,'supabase/sources/library-menu-rollback-qa.sql'),prefix+sql+fs.readFileSync(path.join(__dirname,'test-library-menu.sql'),'utf8'));
