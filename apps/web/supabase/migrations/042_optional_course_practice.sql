-- Explicit completion lists keep additional practice from changing an existing
-- compulsory training path. Courses without a list retain their previous rules.
begin;
do $optional_tests$
declare definition text; pattern text:='exists(select 1 from required_courses c where c.id=t.course_id)';
begin
 definition:=pg_get_functiondef('academy_private.general_training_status(uuid,text,text,text)'::regprocedure);
 if position('completionTestIds' in definition)=0 then
  if position(pattern in definition)=0 then raise exception 'Review current general_training_status before applying optional practice';end if;
  insert into academy_private.audit_log(actor_id,action,target,details)
  values(auth.uid(),'course_completion_tests_before','academy_private.general_training_status',jsonb_build_object('definition',definition));
  execute replace(definition,pattern,'exists(select 1 from required_courses c where c.id=t.course_id and (not c.payload ? ''completionTestIds'' or c.payload->''completionTestIds'' ? t.id))');
 end if;
end $optional_tests$;
commit;

