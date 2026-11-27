-- Migration: multi-scale scoring + image items + neutral public metadata
-- Adds scale metadata and item images, then refreshes the public read and
-- server-side scoring functions. Safe to re-run.

alter table public.assessments
  add column if not exists scale_meta jsonb not null default '[]'::jsonb;

alter table public.assessment_items
  add column if not exists image_url text not null default '',
  add column if not exists scales jsonb not null default '[]'::jsonb;

create or replace function public.get_assessment_public(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'slug', a.slug,
    'titleAr', coalesce(nullif(a.patient_label_ar, ''), a.title_ar),
    'titleEn', coalesce(nullif(a.patient_label_en, ''), a.title_en),
    'descriptionAr', a.description_ar,
    'descriptionEn', a.description_en,
    'instructionsAr', a.instructions_ar,
    'instructionsEn', a.instructions_en,
    'suite', a.suite,
    'version', a.version,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'position', i.position,
        'textAr', i.text_ar,
        'textEn', i.text_en,
        'imageUrl', i.image_url,
        'options', i.options
      ) order by i.position)
      from public.assessment_items i
      where i.assessment_id = a.id
    ), '[]'::jsonb)
  )
  from public.assessments a
  where a.slug = p_slug and a.active = true;
$$;

-- Code-based lookup: validates without consuming; neutral fields only.
create or replace function public.get_assessment_by_access_code(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_hash text := encode(extensions.digest(coalesce(trim(p_code), ''), 'sha256'), 'hex');
  v_code public.access_codes%rowtype;
  v_result jsonb;
begin
  select * into v_code from public.access_codes where code_hash = v_hash;
  if not found or v_code.used_at is not null or v_code.revoked
     or v_code.expires_at <= now() or v_code.attempts >= 10 then
    if found and v_code.attempts < 10 then
      update public.access_codes set attempts = attempts + 1 where id = v_code.id;
    end if;
    raise exception 'رقم الدخول غير صالح أو منتهي الصلاحية';
  end if;

  select jsonb_build_object(
    'slug', a.slug,
    'titleAr', coalesce(nullif(a.patient_label_ar, ''), a.title_ar),
    'titleEn', coalesce(nullif(a.patient_label_en, ''), a.title_en),
    'descriptionAr', a.description_ar,
    'descriptionEn', a.description_en,
    'instructionsAr', a.instructions_ar,
    'instructionsEn', a.instructions_en,
    'suite', a.suite,
    'version', a.version,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'position', i.position,
        'textAr', i.text_ar,
        'textEn', i.text_en,
        'imageUrl', i.image_url,
        'options', i.options
      ) order by i.position)
      from public.assessment_items i
      where i.assessment_id = a.id
    ), '[]'::jsonb)
  ) into v_result
  from public.assessments a
  where a.id = v_code.assessment_id and a.active = true;

  if v_result is null then
    raise exception 'رقم الدخول غير صالح أو منتهي الصلاحية';
  end if;
  return v_result;
end $$;

create or replace function public.get_public_settings() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(s.key, s.value), '{}'::jsonb)
  from public.app_settings s
  where s.key like 'public.%';
$$;

-- =============================================================================
-- 5. SERVER-SIDE SUBMISSION & SCORING (patient never receives a score)
-- =============================================================================

-- Internal scoring implementation. Public entry point is the wrapper below.
create or replace function public.submit_assessment_scoring(
  p_slug text,
  p_patient_name text,
  p_age integer,
  p_gender text,
  p_examiner text,
  p_notes text,
  p_answers jsonb
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_assessment public.assessments%rowtype;
  v_session_id uuid;
  v_code text;
  v_answer jsonb;
  v_item public.assessment_items%rowtype;
  v_scores integer[];
  v_recorded integer;
  v_total integer := 0;
  v_total_option jsonb;
  v_max integer := 0;
  v_cutoff jsonb := null;
  v_rule jsonb;
  v_alerts jsonb := '[]'::jsonb;
  v_breakdown jsonb := '[]'::jsonb;
  v_item_count integer;
  v_chosen_ar text;
  v_chosen_en text;
  v_scale_meta jsonb;
  v_scale_def jsonb;
  v_item_scale jsonb;
  v_scale_scores jsonb := '{}'::jsonb;
  v_scale_t_scores jsonb := '{}'::jsonb;
  v_class_scores jsonb;
  v_t_score numeric;
  v_max_t numeric;
  v_item_max integer;
  v_contribution numeric;
  v_scale_cutoff jsonb := null;
  v_scale_excess numeric;
  v_best_excess numeric := -1;
  v_best_elevate numeric := -1;
  v_patient_gender text;
  v_visible_scale_meta jsonb := '[]'::jsonb;
  v_raw_scale_scores jsonb;
  v_scale_diagnosis jsonb := '[]'::jsonb;
  v_diagnosis_band jsonb;
  v_band jsonb;
  v_diagnosis_value numeric;
  v_composite numeric;
  v_component_key text;
begin
  v_patient_gender := case
    when p_gender like '%أنثى%' then 'F'
    else 'M'
  end;
  select * into v_assessment
  from public.assessments
  where slug = p_slug and active = true;
  if not found then
    raise exception 'هذا التقييم غير متاح حالياً';
  end if;

  select count(*) into v_item_count
  from public.assessment_items where assessment_id = v_assessment.id;

  v_scale_meta := coalesce(v_assessment.scale_meta, '[]'::jsonb);
  for v_scale_def in select value from jsonb_array_elements(v_scale_meta)
  loop
    if v_scale_def ? 'gender' and v_scale_def->>'gender' <> v_patient_gender then
      continue;
    end if;
    v_visible_scale_meta := v_visible_scale_meta || v_scale_def;
    if v_scale_def ? 'key' then
      v_scale_scores := v_scale_scores || jsonb_build_object(v_scale_def->>'key', 0);
    end if;
  end loop;

  if jsonb_array_length(coalesce(p_answers, '[]'::jsonb)) <> v_item_count then
    raise exception 'يجب الإجابة على جميع البنود';
  end if;

  v_code := 'PSY-' || to_char(now(), 'YYYYMMDD') || '-' || upper(substr(gen_random_uuid()::text, 1, 6));

  insert into public.sessions (
    assessment_id, patient_code, patient_name, patient_age,
    patient_gender, examiner_name, notes
  ) values (
    v_assessment.id, v_code, coalesce(nullif(trim(p_patient_name), ''), 'مجهول'),
    nullif(p_age, 0), coalesce(nullif(trim(p_gender), ''), 'غير محدد'),
    coalesce(nullif(trim(p_examiner), ''), ''), coalesce(p_notes, '')
  ) returning id into v_session_id;

  for v_answer in select value from jsonb_array_elements(p_answers)
  loop
    select * into v_item
    from public.assessment_items
    where assessment_id = v_assessment.id
      and position = (v_answer->>'position')::integer;
    if not found then
      raise exception 'بند غير صالح';
    end if;

    select coalesce(array_agg(x.value::integer), '{}'::integer[]) into v_scores
    from jsonb_array_elements_text(v_answer->'scores') as x(value);

    if coalesce(array_length(v_scores, 1), 0) = 0 then
      raise exception 'إجابة فارغة';
    end if;

    select max(s) into v_recorded from unnest(v_scores) as s;

    select o into v_total_option
    from jsonb_array_elements(v_item.options) o
    where (o->>'score')::integer = v_recorded limit 1;
    v_total := v_total + coalesce((v_total_option ->> 'totalScore')::integer, v_recorded);
    v_chosen_ar := v_total_option ->> 'ar';
    v_chosen_en := v_total_option ->> 'en';

    insert into public.answers (
      session_id, item_id, position, selected_scores, recorded_score,
      domain_ar, text_ar, chosen_ar
    ) values (
      v_session_id, v_item.id, v_item.position, v_scores, v_recorded,
      v_item.domain_ar, v_item.text_ar, coalesce(v_chosen_ar, '')
    );

    v_breakdown := v_breakdown || jsonb_build_object(
      'position', v_item.position,
      'domainAr', v_item.domain_ar,
      'textAr', v_item.text_ar,
      'textEn', v_item.text_en,
      'score', v_recorded,
      'chosenAr', coalesce(v_chosen_ar, ''),
      'chosenEn', coalesce(v_chosen_en, '')
    );

    select max((o->>'score')::integer) into v_item_max
    from jsonb_array_elements(v_item.options) as o;

    for v_item_scale in select value from jsonb_array_elements(coalesce(v_item.scales, '[]'::jsonb))
    loop
      if v_item_scale ? 'key' and v_scale_scores ? (v_item_scale->>'key') then
        v_contribution := case
          when v_item_scale->>'direction' = 'reverse' then (coalesce(v_item_max, 0) - v_recorded)::numeric
          when v_item_scale->>'direction' = 'no' then (case when v_recorded = 0 then 1 else 0 end)::numeric
          when v_item_scale->>'direction' = 'yes' then (case when v_recorded = 1 then 1 else 0 end)::numeric
          when v_item_scale->>'direction' = 'skip' then (case when v_recorded = 2 then 1 else 0 end)::numeric
          else v_recorded::numeric
        end;
        if v_item_scale ? 'weight' then
          v_contribution := v_contribution * (v_item_scale->>'weight')::numeric;
        end if;
        v_scale_scores := jsonb_set(
          v_scale_scores,
          array[v_item_scale->>'key'],
          to_jsonb((v_scale_scores->>(v_item_scale->>'key'))::numeric + v_contribution),
          true
        );
      end if;
    end loop;
  end loop;

  select coalesce(sum(item_max), 0) into v_max
  from (
    select max(coalesce((o->>'totalScore')::integer, (o->>'score')::integer)) as item_max
    from public.assessment_items i, jsonb_array_elements(i.options) o
    where i.assessment_id = v_assessment.id
    group by i.id
  ) as per_item;

  select c into v_cutoff
  from jsonb_array_elements(v_assessment.cutoffs) c
  where v_total between (c->>'min')::integer and (c->>'max')::integer
  order by (c->>'min')::integer
  limit 1;

  for v_rule in select value from jsonb_array_elements(v_assessment.critical_rules)
  loop
    if exists (
      select 1 from public.answers a
      where a.session_id = v_session_id
        and a.position = (v_rule->>'position')::integer
        and a.recorded_score >= (v_rule->>'minScore')::integer
    ) then
      v_alerts := v_alerts || jsonb_build_object(
        'type', v_rule->>'type',
        'severity', v_rule->>'severity',
        'titleAr', v_rule->>'titleAr',
        'bodyAr', v_rule->>'bodyAr',
        'titleEn', v_rule->>'titleEn',
        'bodyEn', v_rule->>'bodyEn',
        'position', v_rule->>'position',
        'score', (
          select a.recorded_score from public.answers a
          where a.session_id = v_session_id
            and a.position = (v_rule->>'position')::integer
        )
      );
    end if;
  end loop;

  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if v_scale_def ? 'correctionKey' and v_scale_def ? 'correctionWeight'
       and v_scale_scores ? (v_scale_def->>'correctionKey') then
      v_scale_scores := jsonb_set(
        v_scale_scores,
        array[v_scale_def->>'key'],
        to_jsonb((v_scale_scores->>(v_scale_def->>'key'))::numeric
          + (v_scale_scores->>(v_scale_def->>'correctionKey'))::numeric * (v_scale_def->>'correctionWeight')::numeric),
        true
      );
    end if;
  end loop;

  -- Composite subscales are sums of their already-scored components.
  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if v_scale_def ? 'compositeKeys' and v_scale_def ? 'key' then
      v_composite := 0;
      for v_component_key in
        select value from jsonb_array_elements_text(v_scale_def -> 'compositeKeys')
      loop
        v_composite := v_composite
          + coalesce((v_scale_scores ->> v_component_key)::numeric, 0);
      end loop;
      v_scale_scores := jsonb_set(
        v_scale_scores,
        array[v_scale_def ->> 'key'],
        to_jsonb(v_composite),
        true
      );
    end if;
  end loop;

  v_raw_scale_scores := v_scale_scores;

  v_class_scores := v_scale_scores;

  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if v_scale_def ? 'key' and v_scale_def ? 'mean' and v_scale_def ? 'sd'
       and v_scale_scores ? (v_scale_def ->> 'key') then
      v_t_score := round(50 + 10 * (
        ((v_scale_scores ->> (v_scale_def ->> 'key'))::numeric - (v_scale_def ->> 'mean')::numeric)
        / nullif((v_scale_def ->> 'sd')::numeric, 0)
      ));
      v_scale_t_scores := v_scale_t_scores || jsonb_build_object(v_scale_def ->> 'key', v_t_score);
      v_class_scores := jsonb_set(
        v_class_scores,
        array[v_scale_def ->> 'key'],
        to_jsonb(v_t_score),
        true
      );
    end if;
  end loop;

  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if v_scale_def ? 'bands' and v_scale_def ? 'key'
       and v_class_scores ? (v_scale_def ->> 'key') then
      v_diagnosis_value := (v_class_scores ->> (v_scale_def ->> 'key'))::numeric;
      v_diagnosis_band := null;
      for v_band in select value from jsonb_array_elements(v_scale_def -> 'bands')
      loop
        if (v_band ->> 'min') is null or v_diagnosis_value >= (v_band ->> 'min')::numeric then
          if (v_band ->> 'max') is null or v_diagnosis_value <= (v_band ->> 'max')::numeric then
            v_diagnosis_band := v_band;
            exit;
          end if;
        end if;
      end loop;
      if v_diagnosis_band is not null then
        v_scale_diagnosis := v_scale_diagnosis || jsonb_build_object(
          'key', v_scale_def ->> 'key',
          'group', coalesce(v_scale_def ->> 'group', 'other'),
          'ar', coalesce(v_scale_def ->> 'diagnosisLabel', v_scale_def ->> 'ar', v_scale_def ->> 'key'),
          'en', coalesce(v_scale_def ->> 'en', ''),
          'raw', v_raw_scale_scores ->> (v_scale_def ->> 'key'),
          'score', v_class_scores ->> (v_scale_def ->> 'key'),
          'tScore', v_scale_t_scores ->> (v_scale_def ->> 'key'),
          'rangeLabel', v_diagnosis_band ->> 'rangeLabel',
          'normSource', coalesce(v_scale_def ->> 'normSource', 'published'),
          'parent', v_scale_def ->> 'parent',
          'overviewAr', coalesce(v_scale_def ->> 'overviewAr', ''),
          'diagnosisAr', v_diagnosis_band ->> 'ar'
        );
      end if;
    end if;
  end loop;

  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if v_scale_def ->> 'derive' = 'maxT' and v_scale_def ? 'sourceKeys' then
      select max((v_class_scores ->> k.value)::numeric) into v_max_t
      from jsonb_array_elements_text(v_scale_def -> 'sourceKeys') as k(value)
      where v_class_scores ? k.value;
      if v_max_t is not null then
        v_class_scores := jsonb_set(
          v_class_scores,
          array[v_scale_def ->> 'key'],
          to_jsonb(v_max_t),
          true
        );
      end if;
    end if;
  end loop;

  for v_scale_def in select value from jsonb_array_elements(v_visible_scale_meta)
  loop
    if coalesce((v_scale_def ->> 'classify')::boolean, false)
       and v_scale_def ? 'elevate'
       and v_class_scores ? (v_scale_def ->> 'key') then
      v_scale_excess := (v_class_scores ->> (v_scale_def ->> 'key'))::numeric
        - (v_scale_def ->> 'elevate')::numeric;
      if v_scale_excess >= 0 and (v_scale_def ->> 'elevate')::numeric > v_best_elevate then
        v_best_elevate := (v_scale_def ->> 'elevate')::numeric;
        v_best_excess := v_scale_excess;
        v_scale_cutoff := jsonb_build_object(
          'key', coalesce(v_scale_def ->> 'severityKey', v_scale_def ->> 'key'),
          'ar', coalesce(v_scale_def ->> 'severityAr', v_scale_def ->> 'ar', v_scale_def ->> 'key'),
          'en', coalesce(v_scale_def ->> 'severityEn', v_scale_def ->> 'en', v_scale_def ->> 'key'),
          'descAr', coalesce(v_scale_def ->> 'severityDescAr', ''),
          'descEn', coalesce(v_scale_def ->> 'severityDescEn', ''),
          'tone', coalesce(v_scale_def ->> 'tone', 'amber')
        );
      end if;
    end if;
  end loop;

  if v_scale_cutoff is not null then
    v_cutoff := v_scale_cutoff;
  end if;

  insert into public.reports (
    session_id, assessment_id, raw_score, max_score,
    severity_key, severity_ar, severity_en,
    severity_desc_ar, severity_desc_en, alerts, snapshot, version
  ) values (
    v_session_id, v_assessment.id, v_total, v_max,
    coalesce(v_cutoff->>'key', 'unclassified'),
    coalesce(v_cutoff->>'ar', 'غير مصنف'),
    coalesce(v_cutoff->>'en', 'Unclassified'),
    coalesce(v_cutoff->>'descAr', ''),
    coalesce(v_cutoff->>'descEn', ''),
    v_alerts,
    jsonb_build_object(
      'assessmentTitleAr', v_assessment.title_ar,
      'assessmentTitleEn', v_assessment.title_en,
      'patientCode', v_code,
      'patientName', coalesce(nullif(trim(p_patient_name), ''), 'مجهول'),
      'patientAge', nullif(p_age, 0),
      'patientGender', coalesce(nullif(trim(p_gender), ''), 'غير محدد'),
      'examinerName', coalesce(nullif(trim(p_examiner), ''), ''),
      'notes', coalesce(p_notes, ''),
      'items', v_breakdown,
      'scaleScores', v_class_scores,
      'scaleRaw', v_scale_scores,
      'scaleTScores', v_scale_t_scores,
      'scaleDiagnosis', v_scale_diagnosis,
      'scaleMeta', v_visible_scale_meta
    ),
    v_assessment.version
  );

  update public.sessions set completed_at = now() where id = v_session_id;

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'assessmentTitleAr', v_assessment.title_ar
  );
end $$;

-- Public submission: anon callers must provide a valid single-use code.
-- Specialists may seed demo data by slug (their session authenticates the call).
create or replace function public.submit_assessment(
  p_slug text,
  p_patient_name text,
  p_age integer,
  p_gender text,
  p_examiner text,
  p_notes text,
  p_answers jsonb,
  p_access_code text default null
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_code public.access_codes%rowtype;
  v_hash text;
  v_slug text := p_slug;
  v_result jsonb;
  v_title text;
  v_has_code boolean := coalesce(trim(p_access_code), '') <> '';
begin
  if v_has_code then
    v_hash := encode(extensions.digest(trim(p_access_code), 'sha256'), 'hex');
    select * into v_code
    from public.access_codes where code_hash = v_hash
    for update skip locked;

    if not found or v_code.used_at is not null or v_code.revoked
       or v_code.expires_at <= now() or v_code.attempts >= 10 then
      if found and v_code.attempts < 10 then
        update public.access_codes set attempts = attempts + 1 where id = v_code.id;
      end if;
      raise exception 'رقم الدخول غير صالح أو منتهي الصلاحية';
    end if;

    select a.slug into v_slug
    from public.assessments a where a.id = v_code.assessment_id and a.active = true;
    if not found then
      raise exception 'رقم الدخول غير صالح أو منتهي الصلاحية';
    end if;
  elsif not public.is_specialist() then
    raise exception 'رقم الدخول مطلوب للبدء';
  end if;

  v_result := public.submit_assessment_scoring(
    v_slug, p_patient_name, p_age, p_gender, p_examiner, p_notes, p_answers
  );

  if v_has_code then
    update public.access_codes set used_at = now()
    where id = v_code.id and used_at is null;

    select coalesce(nullif(a.patient_label_ar, ''), a.title_ar) into v_title
    from public.assessments a where a.slug = v_slug;
    v_result := v_result || jsonb_build_object('assessmentTitleAr', coalesce(v_title, ''));
  end if;

  return v_result;
end $$;
