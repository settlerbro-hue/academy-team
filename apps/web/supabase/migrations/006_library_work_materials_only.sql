-- Apply after seed and migration 005. Only frozen legacy imports are affected.
-- Reversible: records remain as drafts, with their files and results untouched.
begin;
update public.academy_content
set published=false,
 payload=payload || '{"catalogArchiveReason":"legacy-news-contests-and-public-channels"}'::jsonb,
 updated_at=now()
where kind='material' and id in (
 'announcement-44c19c0dd8b5','announcement-9b20eb1606e5','announcement-4232a2768736',
 'announcement-b92aef2e47a2','announcement-aa398cb63df9','announcement-cc336cc47f71',
 'announcement-2b0ff637aff4','announcement-9d36d35046d5','announcement-9acabaf1da5e',
 'announcement-39a31bd701f0','announcement-6a9dbb3859da','announcement-dbf38e15a1df',
 'announcement-b39a1e942c89','announcement-64c3e6d88b7c',
 'library-import-9c10537810',
 'library-import-a6dc32c68a','library-import-3584f4310c','library-import-fbddeb3303',
 'library-import-316255d0fa','library-import-88b34c7d41','library-import-13ce8e315c',
 'library-import-dc65440851','library-import-77546ca09c','library-import-363f4e8cb6',
 'library-import-ac01377dc7'
);
commit;
select id,title from public.academy_content where kind='material' and published=true order by title;
