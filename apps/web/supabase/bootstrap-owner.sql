-- Run separately after inspecting identity and approving this role assignment.
begin;
do $$ begin
 if not exists(select 1 from auth.users where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and lower(email)='settlerbro@gmail.com' and email_confirmed_at is not null) then
 raise exception 'Verified owner identity does not match'; end if;
end $$;
insert into public.academy_profiles(id,full_name,role,status)
select id,coalesce(raw_user_meta_data->>'full_name','Владелец академии'),'admin','active'
from auth.users where id='68a8567e-625e-41bc-bb37-6744d729c3d4' and lower(email)='settlerbro@gmail.com' and email_confirmed_at is not null
on conflict(id) do update set role='admin',status='active',updated_at=now();
commit;
