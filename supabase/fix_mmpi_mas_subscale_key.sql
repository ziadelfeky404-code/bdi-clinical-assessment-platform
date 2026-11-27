-- The Ma subtle-items group is labelled MAS in the correction appendix, but
-- this platform already uses MAS for the Manifest Anxiety research scale.
-- Earlier subscale imports appended the 22 Ma-S items to the research key,
-- making MAS score 72 items instead of 50. Remove those links; the generated
-- subscale update then re-adds them under the unique key MASUB.
with legacy(position) as (
  values
    (11), (21), (64), (101), (105), (109), (127), (134), (143), (148),
    (166), (171), (180), (181), (222), (228), (232), (233), (240), (267),
    (271), (289)
)
update public.assessment_items ai
set scales = coalesce((
  select jsonb_agg(x.value order by x.ord)
  from jsonb_array_elements(coalesce(ai.scales, '[]'::jsonb)) with ordinality as x(value, ord)
  where x.value ->> 'key' <> 'MAS'
), '[]'::jsonb)
where ai.assessment_id = (select id from public.assessments where slug = 'mmpi-566')
  and ai.position in (select position from legacy);
