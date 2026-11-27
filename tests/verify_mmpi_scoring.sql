-- Independent re-score check for every completed MMPI report.
-- Paste into the Supabase SQL editor. It recomputes raw scores from the stored
-- answers and current item keys, applies K corrections and composites, derives
-- T scores from the published norms, then compares them with the saved report.
-- Expected result: raw_mismatches = 0, t_mismatches = 0,
-- unpublished_with_t = 0.
with report_scope as (
  select rp.id report_id, rp.snapshot, se.id session_id,
         case when rp.snapshot ->> 'patientGender' like '%أنثى%' then 'F' else 'M' end gender
  from public.reports rp
  join public.assessments a on a.id = rp.assessment_id
  join public.sessions se on se.id = rp.session_id
  where a.slug = 'mmpi-566' and coalesce(rp.severity_key, '') <> 'incomplete'
),
meta as (
  select rs.report_id, d.value def
  from report_scope rs
  cross join lateral jsonb_array_elements(rs.snapshot -> 'scaleMeta') d
  where not (d.value ? 'gender') or d.value ->> 'gender' = rs.gender
),
meta_keys as (
  select distinct report_id, def ->> 'key' key from meta
),
base as (
  select rs.report_id, s ->> 'key' key,
         sum((case
                when s ->> 'direction' = 'reverse' then (im.item_max - an.recorded_score)::numeric
                when s ->> 'direction' = 'no' then (case when an.recorded_score = 0 then 1 else 0 end)::numeric
                when s ->> 'direction' = 'yes' then (case when an.recorded_score = 1 then 1 else 0 end)::numeric
                when s ->> 'direction' = 'skip' then (case when an.recorded_score = 2 then 1 else 0 end)::numeric
                else an.recorded_score::numeric
              end) * coalesce((s ->> 'weight')::numeric, 1)) raw
  from report_scope rs
  join public.answers an on an.session_id = rs.session_id
  join public.assessment_items it on it.id = an.item_id
  join lateral (
    select max((o ->> 'score')::integer) item_max
    from jsonb_array_elements(it.options) o
  ) im on true
  cross join lateral jsonb_array_elements(coalesce(it.scales, '[]'::jsonb)) s
  join meta_keys mk on mk.report_id = rs.report_id and mk.key = s ->> 'key'
  group by rs.report_id, s ->> 'key'
),
corrected as (
  select b.report_id, b.key,
         b.raw + coalesce(
           (select c.raw from base c where c.report_id = b.report_id and c.key = m.def ->> 'correctionKey')
             * (m.def ->> 'correctionWeight')::numeric, 0) raw
  from base b
  join meta m on m.report_id = b.report_id and m.def ->> 'key' = b.key
  where not (m.def ? 'compositeKeys')
),
composites as (
  select m.report_id, m.def ->> 'key' key,
         sum(coalesce((select c.raw from corrected c where c.report_id = m.report_id and c.key = k), 0)) raw
  from meta m
  cross join lateral jsonb_array_elements_text(m.def -> 'compositeKeys') k
  where m.def ? 'compositeKeys'
  group by m.report_id, m.def ->> 'key'
),
scores as (
  select * from corrected
  union all
  select * from composites
),
tcalc as (
  select s.report_id, s.key, s.raw,
         round(50 + 10 * ((s.raw - (m.def ->> 'mean')::numeric) / nullif((m.def ->> 'sd')::numeric, 0))) t
  from scores s
  join meta m on m.report_id = s.report_id and m.def ->> 'key' = s.key
  where m.def ? 'mean' and m.def ? 'sd'
),
raw_diff as (
  select 1
  from scores s join report_scope rs on rs.report_id = s.report_id
  where rs.snapshot -> 'scaleRaw' ? s.key
    and (rs.snapshot -> 'scaleRaw' ->> s.key)::numeric <> s.raw
),
t_diff as (
  select 1
  from tcalc t join report_scope rs on rs.report_id = t.report_id
  where rs.snapshot -> 'scaleTScores' ? t.key
    and (rs.snapshot -> 'scaleTScores' ->> t.key)::numeric <> t.t
),
unpub_t as (
  select 1
  from meta m join report_scope rs on rs.report_id = m.report_id
  where m.def ->> 'normSource' = 'unpublished'
    and rs.snapshot -> 'scaleTScores' ? (m.def ->> 'key')
)
select
  (select count(*) from report_scope) reports_checked,
  (select count(*) from scores) raw_scores_checked,
  (select count(*) from raw_diff) raw_mismatches,
  (select count(*) from tcalc) t_scores_checked,
  (select count(*) from t_diff) t_mismatches,
  (select count(*) from unpub_t) unpublished_with_t;
