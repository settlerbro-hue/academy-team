begin;
insert into public.academy_content(id,kind,title,restaurant_id,department,payload) values('qa-audience-shared','course','QA shared',null,null,'{}'),('qa-audience-local','course','QA local','minsk','Бар','{}');
update public.academy_profiles set role='employee',status='active',restaurant_id='minsk',department='Бар',position='Бармен',training_level='trainee' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare denied boolean;begin
 denied:=false;begin perform public.academy_set_training_level(auth.uid(),'certified');exception when others then denied:=true;end;if not denied then raise exception 'Employee certified self';end if;
 denied:=false;begin perform public.academy_set_course_audience('qa-audience-shared','["Бармен"]','["trainee"]','{}');exception when others then denied:=true;end;if not denied then raise exception 'Employee edited audience';end if;
end $$;
select set_config('request.jwt.claim.sub','68a8567e-625e-41bc-bb37-6744d729c3d4',true);
select public.academy_set_training_level('4233956d-46bb-44c6-a266-759203b6648a','certified');
select public.academy_set_course_audience('qa-audience-shared','["Бармен","Официант"]','["trainee","certified"]','{"Бармен":"start","Официант":"additional"}');
do $$ declare denied boolean;begin
 if not exists(select 1 from public.academy_profiles where id='4233956d-46bb-44c6-a266-759203b6648a' and training_level='certified' and role='employee') then raise exception 'Owner stage edit failed';end if;
 if not exists(select 1 from public.academy_content where id='qa-audience-shared' and payload->'audiencePositions' @> '["Бармен","Официант"]' and payload->'audiencePriorities'->>'Бармен'='start' and payload->'audiencePriorities'->>'Официант'='additional') then raise exception 'Multi audience priorities failed';end if;
 denied:=false;begin perform public.academy_set_course_audience('qa-audience-shared','[null]','["trainee"]','{}');exception when others then denied:=true;end;if not denied then raise exception 'Null position accepted';end if;
 denied:=false;begin perform public.academy_set_course_audience('qa-audience-shared','[]','["trainee"]','{}');exception when others then denied:=true;end;if not denied then raise exception 'Empty positions accepted';end if;
end $$;
reset role;
update public.academy_profiles set role='manager' where id='4233956d-46bb-44c6-a266-759203b6648a';
set local role authenticated;
select set_config('request.jwt.claim.sub','4233956d-46bb-44c6-a266-759203b6648a',true);
do $$ declare denied boolean;begin
 perform public.academy_set_course_audience('qa-audience-local','["Бармен","Барбэк"]','["trainee"]','{"Бармен":"attestation"}');
 denied:=false;begin perform public.academy_set_course_audience('qa-audience-shared','["Бармен"]','["trainee"]','{}');exception when others then denied:=true;end;if not denied then raise exception 'Manager edited shared course';end if;
 denied:=false;begin perform public.academy_set_training_level(auth.uid(),'certified');exception when others then denied:=true;end;if not denied then raise exception 'Manager self certified';end if;
end $$;
reset role;
update public.academy_profiles set department='Руководитель',position='Управляющий',training_level='certified' where id='4233956d-46bb-44c6-a266-759203b6648a';
do $$ begin if exists(select 1 from public.academy_profiles where id='4233956d-46bb-44c6-a266-759203b6648a' and training_level is not null) then raise exception 'Leader has stage';end if;end $$;
rollback;
select 'PASS: multiple positions, individual priorities, levels, owner edit, scoped administrator edit, no self certification, invalid categories rejected, leaders exempt; fixtures rolled back' as test_result;
