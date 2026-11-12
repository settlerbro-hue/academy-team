begin;

-- Compare the saved answers with the same immutable key used for grading.
-- Return feedback on submitted choices without returning the answer key.
create or replace function public.academy_test_mistakes(p_attempt_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'index', question.number - 1,
        'selected', choices.supplied,
        'wrong', (
          select coalesce(jsonb_agg(value), '[]'::jsonb)
          from jsonb_array_elements(choices.supplied)
          where not (choices.expected @> jsonb_build_array(value))
        ),
        'incomplete', not (choices.supplied @> choices.expected)
      ) order by question.number
    )
    from jsonb_array_elements(a.snapshot->'questions') with ordinality as question(body, number)
    cross join lateral (
      select k.keys->(question.body->>'id') as expected,
             case when jsonb_typeof(a.answers->(question.body->>'id')) = 'array'
               then a.answers->(question.body->>'id') else '[]'::jsonb end as supplied
    ) choices
    where question.body->>'type' is distinct from 'text'
      and jsonb_typeof(choices.expected) = 'array'
      and not (choices.supplied @> choices.expected and choices.expected @> choices.supplied)
  ), '[]'::jsonb)
  from public.academy_attempts a
  join academy_private.attempt_keys k on k.attempt_id = a.id
  where a.id = p_attempt_id
    and a.user_id = auth.uid()
    and a.submitted_at is not null
    and academy_private.is_active();
$$;

revoke all on function public.academy_test_mistakes(uuid) from public, anon;
grant execute on function public.academy_test_mistakes(uuid) to authenticated;

commit;
