-- Re-score completed MMPI reports from the stored answers using the current
-- correction key. Older reports kept raw scores from before K weights and from
-- before the Ma-S key collision was fixed, so their raw/T values and grouped
-- diagnoses could drift from the approved key. This function rebuilds them.
create or replace function public.repair_mmpi_reports()
returns integer
language plpgsql
set search_path = public, extensions
as $$
declare
  r record;
  v_meta jsonb;
  v_scale_def jsonb;
  v_band jsonb;
  v_gender text;
  v_seen jsonb;
  v_raw jsonb;
  v_t_scores jsonb;
  v_class_scores jsonb;
  v_diagnosis jsonb;
  v_derived numeric;
  v_t_value numeric;
  v_component text;
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
      and exists (select 1 from public.answers an where an.session_id = rp.session_id)
  loop
    v_gender := case
      when coalesce(r.snapshot ->> 'patientGender', '') like '%أنثى%' then 'F'
      else 'M'
    end;
    v_seen := '{}'::jsonb;
    v_raw := '{}'::jsonb;
    v_t_scores := '{}'::jsonb;
    v_diagnosis := '[]'::jsonb;

    -- Base scores from the recorded answers and the published item keys.
    for v_scale_def in select value from jsonb_array_elements(v_meta)
    loop
      if v_scale_def ? 'gender' and v_scale_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_scale_def ? 'key') or v_scale_def ? 'compositeKeys'
         or v_seen ? (v_scale_def ->> 'key') then
        continue;
      end if;
      v_seen := v_seen || jsonb_build_object(v_scale_def ->> 'key', true);

      select coalesce(sum(
        (case
          when s ->> 'direction' = 'reverse' then (om.item_max - an.recorded_score)::numeric
          when s ->> 'direction' = 'no' then (case when an.recorded_score = 0 then 1 else 0 end)::numeric
          when s ->> 'direction' = 'yes' then (case when an.recorded_score = 1 then 1 else 0 end)::numeric
          when s ->> 'direction' = 'skip' then (case when an.recorded_score = 2 then 1 else 0 end)::numeric
          else an.recorded_score::numeric
        end) * coalesce((s ->> 'weight')::numeric, 1)
      ), 0)
      into v_derived
      from public.answers an
      join public.assessment_items i on i.id = an.item_id
      cross join lateral jsonb_array_elements(coalesce(i.scales, '[]'::jsonb)) s
      cross join lateral (
        select max((o ->> 'score')::integer) as item_max
        from jsonb_array_elements(i.options) o
      ) om
      where an.session_id = r.session_id
        and s ->> 'key' = v_scale_def ->> 'key';

      v_raw := jsonb_set(v_raw, array[v_scale_def ->> 'key'], to_jsonb(v_derived), true);
    end loop;

    -- K correction, as specified in the correction appendix.
    for v_scale_def in select value from jsonb_array_elements(v_meta)
    loop
      if v_scale_def ? 'gender' and v_scale_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_scale_def ? 'correctionKey' and v_scale_def ? 'correctionWeight' and v_scale_def ? 'key') then
        continue;
      end if;
      if not (v_raw ? (v_scale_def ->> 'key')) or not (v_raw ? (v_scale_def ->> 'correctionKey')) then
        continue;
      end if;
      v_raw := jsonb_set(
        v_raw,
        array[v_scale_def ->> 'key'],
        to_jsonb((v_raw ->> (v_scale_def ->> 'key'))::numeric
          + (v_raw ->> (v_scale_def ->> 'correctionKey'))::numeric
            * (v_scale_def ->> 'correctionWeight')::numeric),
        true
      );
    end loop;

    -- Composite subscales are sums of their already-corrected components.
    for v_scale_def in select value from jsonb_array_elements(v_meta)
    loop
      if v_scale_def ? 'gender' and v_scale_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_scale_def ? 'compositeKeys' and v_scale_def ? 'key') then
        continue;
      end if;
      v_derived := 0;
      for v_component in
        select value from jsonb_array_elements_text(v_scale_def -> 'compositeKeys')
      loop
        v_derived := v_derived + coalesce((v_raw ->> v_component)::numeric, 0);
      end loop;
      v_raw := jsonb_set(v_raw, array[v_scale_def ->> 'key'], to_jsonb(v_derived), true);
    end loop;

    -- T scores only where the appendix publishes a mean and SD.
    for v_scale_def in select value from jsonb_array_elements(v_meta)
    loop
      if v_scale_def ? 'gender' and v_scale_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_scale_def ? 'mean' and v_scale_def ? 'sd' and v_scale_def ? 'key') then
        continue;
      end if;
      if not (v_raw ? (v_scale_def ->> 'key')) or ((v_scale_def ->> 'sd')::numeric = 0) then
        continue;
      end if;
      v_t_value := round(50 + 10 * (
        ((v_raw ->> (v_scale_def ->> 'key'))::numeric - (v_scale_def ->> 'mean')::numeric)
        / (v_scale_def ->> 'sd')::numeric
      ));
      v_t_scores := jsonb_set(v_t_scores, array[v_scale_def ->> 'key'], to_jsonb(v_t_value), true);
    end loop;

    v_class_scores := v_raw || v_t_scores;
    v_seen := '{}'::jsonb;

    -- Rebuild grouped diagnoses so stale keys from older imports disappear.
    for v_scale_def in select value from jsonb_array_elements(v_meta)
    loop
      if v_scale_def ? 'gender' and v_scale_def ->> 'gender' <> v_gender then
        continue;
      end if;
      if not (v_scale_def ? 'bands' and v_scale_def ? 'key')
         or v_seen ? (v_scale_def ->> 'key') then
        continue;
      end if;
      if not (v_class_scores ? (v_scale_def ->> 'key')) then
        continue;
      end if;
      v_seen := v_seen || jsonb_build_object(v_scale_def ->> 'key', true);
      v_derived := (v_class_scores ->> (v_scale_def ->> 'key'))::numeric;

      for v_band in select value from jsonb_array_elements(v_scale_def -> 'bands')
      loop
        if ((v_band ->> 'min') is null or v_derived >= (v_band ->> 'min')::numeric)
           and ((v_band ->> 'max') is null or v_derived <= (v_band ->> 'max')::numeric) then
          v_diagnosis := v_diagnosis || jsonb_build_object(
            'key', v_scale_def ->> 'key',
            'group', coalesce(v_scale_def ->> 'group', 'other'),
            'ar', coalesce(v_scale_def ->> 'diagnosisLabel', v_scale_def ->> 'ar', v_scale_def ->> 'key'),
            'en', coalesce(v_scale_def ->> 'en', ''),
            'raw', v_raw ->> (v_scale_def ->> 'key'),
            'score', v_class_scores ->> (v_scale_def ->> 'key'),
            'tScore', v_t_scores ->> (v_scale_def ->> 'key'),
            'rangeLabel', v_band ->> 'rangeLabel',
            'normSource', coalesce(v_scale_def ->> 'normSource', 'published'),
            'parent', v_scale_def ->> 'parent',
            'overviewAr', coalesce(v_scale_def ->> 'overviewAr', ''),
            'diagnosisAr', v_band ->> 'ar'
          );
          exit;
        end if;
      end loop;
    end loop;

    update public.reports rp
    set snapshot = jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            jsonb_set(rp.snapshot, '{scaleMeta}', v_meta, true),
            '{scaleRaw}', v_raw, true
          ),
          '{scaleScores}', v_class_scores, true
        ),
        '{scaleTScores}', v_t_scores, true
      ),
      '{scaleDiagnosis}', v_diagnosis, true
    )
    where rp.id = r.id;

    v_updated := v_updated + 1;
  end loop;

  return v_updated;
end $$;

revoke all on function public.repair_mmpi_reports() from public, anon, authenticated;
