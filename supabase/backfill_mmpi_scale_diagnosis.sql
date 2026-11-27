-- Backfill MMPI per-group diagnoses for reports created before scaleDiagnosis
-- was added to submit_assessment. Existing raw and T scores are reused; the
-- current assessment scale_meta and the report's recorded gender select the
-- matching band text from the approved correction key.
create or replace function public.backfill_mmpi_scale_diagnosis()
returns integer
language plpgsql
set search_path = public, extensions
as $$
declare
  r record;
  v_meta jsonb;
  v_def jsonb;
  v_band jsonb;
  v_gender text;
  v_diagnosis jsonb;
  v_raw jsonb;
  v_t_scores jsonb;
  v_class_scores jsonb;
  v_value numeric;
  v_derived numeric;
  v_component text;
  v_t_value numeric;
  v_updated integer := 0;
begin
  select a.scale_meta into v_meta
  from public.assessments a
  where a.slug = 'mmpi-566';

  if v_meta is null then
    raise exception 'MMPI scale metadata is missing';
  end if;

  for r in
    select rp.*
    from public.reports rp
    join public.assessments a on a.id = rp.assessment_id
    where a.slug = 'mmpi-566'
      and coalesce(rp.severity_key, '') <> 'incomplete'
      and (select count(*) from jsonb_object_keys(coalesce(rp.snapshot -> 'scaleRaw', '{}'::jsonb))) > 1
  loop
    v_gender := case
      when coalesce(r.snapshot ->> 'patientGender', '') like '%ذكر%' then 'M'
      when coalesce(r.snapshot ->> 'patientGender', '') like '%أنثى%' then 'F'
      else ''
    end;
    v_raw := coalesce(r.snapshot -> 'scaleRaw', '{}'::jsonb);
    v_t_scores := coalesce(r.snapshot -> 'scaleTScores', '{}'::jsonb);

    -- Re-score scales added to the key after this report was created (R scale)
    -- from the stored answers, then derive their T scores from current norms.
    for v_def in select value from jsonb_array_elements(v_meta) as x(value)
    loop
      if v_def ? 'gender' and v_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_def ? 'key' and v_def ? 'bands') or v_raw ? (v_def ->> 'key') then
        continue;
      end if;

      select coalesce(sum(
        (case
          when s ->> 'direction' = 'reverse' then (om.item_max - a.recorded_score)::numeric
          when s ->> 'direction' = 'no' then (case when a.recorded_score = 0 then 1 else 0 end)::numeric
          when s ->> 'direction' = 'yes' then (case when a.recorded_score = 1 then 1 else 0 end)::numeric
          when s ->> 'direction' = 'skip' then (case when a.recorded_score = 2 then 1 else 0 end)::numeric
          else a.recorded_score::numeric
        end) * coalesce((s ->> 'weight')::numeric, 1)
      ), 0)
      into v_derived
      from public.answers a
      join public.assessment_items i on i.id = a.item_id
      cross join lateral jsonb_array_elements(coalesce(i.scales, '[]'::jsonb)) s
      cross join lateral (
        select max((o ->> 'score')::integer) as item_max
        from jsonb_array_elements(i.options) o
      ) om
      where a.session_id = r.session_id
        and s ->> 'key' = v_def ->> 'key';

      v_raw := jsonb_set(v_raw, array[v_def ->> 'key'], to_jsonb(v_derived), true);

      if v_def ? 'mean' and v_def ? 'sd' and (v_def ->> 'sd')::numeric <> 0 then
        v_t_value := round(50 + 10 * (
          (v_derived - (v_def ->> 'mean')::numeric) / (v_def ->> 'sd')::numeric
        ));
        v_t_scores := jsonb_set(v_t_scores, array[v_def ->> 'key'], to_jsonb(v_t_value), true);
      end if;
    end loop;

    -- Composite subscales are sums of their already-scored components.
    for v_def in select value from jsonb_array_elements(v_meta) as x(value)
    loop
      if v_def ? 'gender' and v_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_def ? 'compositeKeys' and v_def ? 'key' and v_def ? 'bands') then
        continue;
      end if;
      -- Always recompute: older snapshots may contain a zero placeholder from
      -- before composite keys were supported.
      v_derived := 0;
      for v_component in
        select value from jsonb_array_elements_text(v_def -> 'compositeKeys')
      loop
        v_derived := v_derived + coalesce((v_raw ->> v_component)::numeric, 0);
      end loop;
      v_raw := jsonb_set(v_raw, array[v_def ->> 'key'], to_jsonb(v_derived), true);
      if v_def ? 'mean' and v_def ? 'sd' and (v_def ->> 'sd')::numeric <> 0 then
        v_t_value := round(50 + 10 * (
          (v_derived - (v_def ->> 'mean')::numeric) / (v_def ->> 'sd')::numeric
        ));
        v_t_scores := jsonb_set(v_t_scores, array[v_def ->> 'key'], to_jsonb(v_t_value), true);
      end if;
    end loop;

    v_class_scores := v_raw || v_t_scores;
    v_diagnosis := '[]'::jsonb;

    for v_def in select value from jsonb_array_elements(v_meta) as x(value)
    loop
      if v_def ? 'gender' and v_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_def ? 'key' and v_def ? 'bands') then
        continue;
      end if;
      if not (v_class_scores ? (v_def ->> 'key')) then
        continue;
      end if;

      v_value := (v_class_scores ->> (v_def ->> 'key'))::numeric;
      v_band := null;

      for v_band in select value from jsonb_array_elements(v_def -> 'bands') as y(value)
      loop
        if (v_band ->> 'min') is null or v_value >= (v_band ->> 'min')::numeric then
          if (v_band ->> 'max') is null or v_value <= (v_band ->> 'max')::numeric then
            exit;
          end if;
        end if;
        v_band := null;
      end loop;

      if v_band is not null then
        v_diagnosis := v_diagnosis || jsonb_build_object(
          'key', v_def ->> 'key',
          'group', coalesce(v_def ->> 'group', 'other'),
          'ar', coalesce(v_def ->> 'diagnosisLabel', v_def ->> 'ar', v_def ->> 'key'),
          'en', coalesce(v_def ->> 'en', ''),
          'raw', v_raw ->> (v_def ->> 'key'),
          'score', v_class_scores ->> (v_def ->> 'key'),
          'tScore', v_t_scores ->> (v_def ->> 'key'),
          'rangeLabel', v_band ->> 'rangeLabel',
          'normSource', coalesce(v_def ->> 'normSource', 'published'),
          'parent', v_def ->> 'parent',
          'overviewAr', coalesce(v_def ->> 'overviewAr', ''),
          'diagnosisAr', v_band ->> 'ar'
        );
      end if;
    end loop;

    update public.reports rp
    set snapshot = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(rp.snapshot, '{scaleDiagnosis}', v_diagnosis, true),
          '{scaleRaw}', v_raw, true
        ),
        '{scaleTScores}', v_t_scores, true
      ),
      '{scaleMeta}', v_meta, true
    )
    where rp.id = r.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end $$;

revoke all on function public.backfill_mmpi_scale_diagnosis() from public, anon, authenticated;
