-- A course can add practice lessons without changing the existing attestation.
begin;
do $learning$
declare
  definition text;
  lesson_rows constant text := 'jsonb_array_elements(case when jsonb_typeof(c.payload->''lessons'')=''array'' then c.payload->''lessons'' else ''[]''::jsonb end)';
  required_lesson constant text := '(not c.payload ? ''completionLessonIds'' or c.payload->''completionLessonIds'' ? coalesce(l.value->>''id'',(l.n-1)::text))';
  venue_marker constant text := '(c.id not in (''guru-50011'',''104648''';
begin
  definition := pg_get_functiondef('academy_private.general_training_status(uuid,text,text,text)'::regprocedure);
  if position('completionLessonIds' in definition) = 0 then
    if position(lesson_rows || ') as total' in definition) = 0
       or position(lesson_rows || ' with ordinality l(value,n) where exists' in definition) = 0
       or position('completionTestIds' in definition) = 0 then
      raise exception 'Review the current attestation function';
    end if;
    definition := replace(definition, lesson_rows || ') as total',
      lesson_rows || ' with ordinality l(value,n) where ' || required_lesson || ') as total');
    definition := replace(definition, lesson_rows || ' with ordinality l(value,n) where exists',
      lesson_rows || ' with ordinality l(value,n) where ' || required_lesson || ' and exists');
    execute definition;
  end if;

  definition := pg_get_functiondef('academy_private.can_read_content(text)'::regprocedure);
  if position('c.course_id is distinct from ''guru-50011''' in definition) = 0 then
    if position(venue_marker in definition) = 0 then
      raise exception 'Review the current venue access function';
    end if;
    execute replace(definition, venue_marker,
      '(c.course_id is distinct from ''guru-50011'' and c.id not in (''guru-50011'',''104648''');
  end if;
end $learning$;
commit;
