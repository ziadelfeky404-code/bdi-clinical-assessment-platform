-- Psychometric Hub — database schema, security policies, server-side scoring and seed data
-- Project: psychometric-hub (ylpgsstplbeldiafxsti)

create extension if not exists pgcrypto with schema extensions;

-- =============================================================================
-- 1. TABLES
-- =============================================================================

create table if not exists public.specialists (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text not null,
  role text not null default 'specialist' check (role in ('admin', 'specialist')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.assessments (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title_ar text not null,
  title_en text not null,
  patient_label_ar text not null default '',
  patient_label_en text not null default '',
  category text not null default 'clinical',
  suite text not null default 'clinical' check (suite in ('clinical', 'special')),
  description_ar text not null default '',
  description_en text not null default '',
  instructions_ar text not null default '',
  instructions_en text not null default '',
  version text not null default '1.0',
  active boolean not null default true,
  cutoffs jsonb not null default '[]'::jsonb,
  critical_rules jsonb not null default '[]'::jsonb,
  scale_meta jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Single-use numeric codes issued by specialists; only hashes are stored.
create table if not exists public.access_codes (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments(id) on delete restrict,
  code_hash text not null unique,
  created_by uuid references public.specialists(id) on delete set null,
  expires_at timestamptz not null,
  used_at timestamptz,
  revoked boolean not null default false,
  attempts integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.assessment_items (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments(id) on delete cascade,
  position integer not null,
  domain_ar text not null default '',
  domain_en text not null default '',
  title_ar text not null default '',
  title_en text not null default '',
  text_ar text not null,
  text_en text not null,
  image_url text not null default '',
  options jsonb not null default '[]'::jsonb,
  scales jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  unique (assessment_id, position)
);

create table if not exists public.sessions (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.assessments(id) on delete restrict,
  patient_code text not null unique,
  patient_name text not null default '',
  patient_age integer,
  patient_gender text not null default '',
  examiner_name text not null default '',
  notes text not null default '',
  session_date date not null default current_date,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  item_id uuid not null references public.assessment_items(id) on delete restrict,
  position integer not null,
  selected_scores integer[] not null,
  recorded_score integer not null,
  domain_ar text not null default '',
  text_ar text not null default '',
  chosen_ar text not null default '',
  created_at timestamptz not null default now(),
  unique (session_id, item_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null unique references public.sessions(id) on delete cascade,
  assessment_id uuid not null references public.assessments(id) on delete restrict,
  raw_score integer not null,
  max_score integer not null,
  severity_key text not null,
  severity_ar text not null,
  severity_en text not null,
  severity_desc_ar text not null default '',
  severity_desc_en text not null default '',
  alerts jsonb not null default '[]'::jsonb,
  snapshot jsonb not null default '{}'::jsonb,
  version text not null default '1.0',
  narrative jsonb,
  clinical_notes text not null default '',
  review_status text not null default 'draft' check (review_status in ('draft', 'approved')),
  reviewed_by uuid,
  reviewed_by_name text not null default '',
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists idx_access_codes_hash on public.access_codes(code_hash);
create index if not exists idx_access_codes_lifecycle on public.access_codes(assessment_id, used_at, expires_at);
create index if not exists idx_items_assessment on public.assessment_items(assessment_id, position);
create index if not exists idx_assessments_suite on public.assessments(suite);
create index if not exists idx_reports_created on public.reports(created_at desc);
create index if not exists idx_reports_review_status on public.reports(review_status);
create index if not exists idx_sessions_assessment on public.sessions(assessment_id);

-- =============================================================================
-- 2. TIMESTAMP TRIGGERS
-- =============================================================================

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists trg_assessments_touch on public.assessments;
create trigger trg_assessments_touch before update on public.assessments
for each row execute function public.touch_updated_at();

drop trigger if exists trg_settings_touch on public.app_settings;
create trigger trg_settings_touch before update on public.app_settings
for each row execute function public.touch_updated_at();

-- =============================================================================
-- 3. ROLE HELPERS
-- =============================================================================

create or replace function public.is_specialist() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.specialists s
    where s.id = auth.uid() and s.active = true
  );
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select exists (
    select 1 from public.specialists s
    where s.id = auth.uid() and s.active = true and s.role = 'admin'
  );
$$;

-- =============================================================================
-- 4. PUBLIC (ANONYMOUS) READ APIs — safe fields only
-- =============================================================================

create or replace function public.get_public_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'slug', a.slug,
    'titleAr', coalesce(nullif(a.patient_label_ar, ''), a.title_ar),
    'titleEn', coalesce(nullif(a.patient_label_en, ''), a.title_en),
    'descriptionAr', a.description_ar,
    'descriptionEn', a.description_en,
    'category', a.category,
    'suite', a.suite,
    'version', a.version,
    'sortOrder', a.sort_order,
    'itemCount', (select count(*) from public.assessment_items i where i.assessment_id = a.id)
  ) order by a.sort_order, a.title_ar), '[]'::jsonb)
  from public.assessments a
  where a.active = true;
$$;

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
begin
  v_patient_gender := case
    when p_gender like '%ذكر%' then 'M'
    when p_gender like '%أنثى%' then 'F'
    else ''
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

-- Admin-only account creation (so the team can add specialists from the UI)
create or replace function public.create_specialist_account(
  p_email text, p_password text, p_full_name text, p_role text default 'specialist'
) returns jsonb
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_user_id uuid;
  v_email text := lower(trim(p_email));
begin
  if not public.is_admin() then
    raise exception 'غير مسموح لك بإضافة متخصصين';
  end if;
  if p_role not in ('admin', 'specialist') then
    raise exception 'دور غير صالح';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'كلمة المرور يجب ألا تقل عن 8 أحرف';
  end if;
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'هذا البريد مستخدم بالفعل';
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new,
    email_change_token_current, phone_change_token, reauthentication_token,
    email_change, phone_change, is_super_admin, is_sso_user, is_anonymous
  ) values (
    '00000000-0000-0000-0000-000000000000', v_user_id, 'authenticated', 'authenticated',
    v_email, extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    '', '', '', '', '', '', '', '', false, false, false
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id,
    last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email', v_email, now(), now(), now()
  );

  insert into public.specialists (id, full_name, email, role)
  values (v_user_id, coalesce(p_full_name, ''), v_email, p_role);

  return jsonb_build_object('ok', true, 'id', v_user_id, 'email', v_email);
end $$;

-- Admin-only account deletion (deleting the auth user cascades to specialists)
create or replace function public.delete_specialist_account(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_email text;
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'غير مسموح لك بحذف الحسابات';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'لا يمكنك حذف حسابك الخاص';
  end if;
  select email, full_name into v_email, v_name from public.specialists where id = p_user_id;
  if not found then
    raise exception 'الحساب غير موجود';
  end if;
  if lower(v_email) = 'demo@menoufia.edu.eg' then
    raise exception 'لا يمكن حذف حساب العرض التجريبي';
  end if;
  delete from auth.users where id = p_user_id;
  return jsonb_build_object('ok', true, 'email', v_email, 'fullName', v_name);
end $$;

-- Specialist-only issuance. The plain code is returned exactly once and never stored.
create or replace function public.issue_assessment_access_code(
  p_assessment_id uuid,
  p_expires_in_hours integer default 24
) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_code text;
  v_hash text;
  v_title text;
  v_expires timestamptz;
begin
  if not public.is_specialist() then
    raise exception 'غير مسموح بإصدار رموز الدخول';
  end if;

  select a.title_ar into v_title
  from public.assessments a where a.id = p_assessment_id and a.active = true;
  if not found then
    raise exception 'الاختبار غير متاح حالياً';
  end if;

  v_expires := now() + make_interval(hours => least(greatest(coalesce(p_expires_in_hours, 24), 1), 168));

  loop
    v_code := lpad(floor(random() * 100000000)::text, 8, '0');
    v_hash := encode(extensions.digest(v_code, 'sha256'), 'hex');
    exit when not exists (select 1 from public.access_codes where code_hash = v_hash);
  end loop;

  insert into public.access_codes (assessment_id, code_hash, created_by, expires_at)
  values (p_assessment_id, v_hash, auth.uid(), v_expires);

  return jsonb_build_object(
    'ok', true,
    'code', v_code,
    'expiresAt', v_expires,
    'assessmentTitleAr', v_title
  );
end $$;

create or replace function public.list_access_codes() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id,
    'assessmentTitleAr', a.title_ar,
    'maskedCode', '••••' || right(c.code_hash, 2),
    'createdAt', c.created_at,
    'expiresAt', c.expires_at,
    'usedAt', c.used_at,
    'revoked', c.revoked,
    'attempts', c.attempts
  ) order by c.created_at desc), '[]'::jsonb)
  from public.access_codes c
  join public.assessments a on a.id = c.assessment_id
  where public.is_specialist();
$$;

create or replace function public.revoke_access_code(p_id uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_specialist() then
    raise exception 'غير مسموح بإدارة رموز الدخول';
  end if;
  update public.access_codes set revoked = true where id = p_id and used_at is null;
  return jsonb_build_object('ok', true);
end $$;

-- =============================================================================
-- 6. ROW LEVEL SECURITY
-- =============================================================================

alter table public.specialists enable row level security;
alter table public.app_settings enable row level security;
alter table public.assessments enable row level security;
alter table public.assessment_items enable row level security;
alter table public.sessions enable row level security;
alter table public.answers enable row level security;
alter table public.reports enable row level security;
alter table public.access_codes enable row level security;

drop policy if exists "specialists manage specialists" on public.specialists;
create policy "specialists view specialists" on public.specialists
for select to authenticated using (public.is_specialist());
create policy "admins insert specialists" on public.specialists
for insert to authenticated with check (public.is_admin());
create policy "admins update specialists" on public.specialists
for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins delete specialists" on public.specialists
for delete to authenticated using (public.is_admin());

drop policy if exists "public read settings" on public.app_settings;
create policy "public read settings" on public.app_settings
for select to anon, authenticated using (key like 'public.%');

drop policy if exists "specialists manage settings" on public.app_settings;
create policy "specialists manage settings" on public.app_settings
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists "specialists manage assessments" on public.assessments;
create policy "specialists manage assessments" on public.assessments
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists "specialists manage items" on public.assessment_items;
create policy "specialists manage items" on public.assessment_items
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists "specialists manage sessions" on public.sessions;
create policy "specialists manage sessions" on public.sessions
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists "specialists manage answers" on public.answers;
create policy "specialists manage answers" on public.answers
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists "specialists manage reports" on public.reports;
create policy "specialists manage reports" on public.reports
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

drop policy if exists access_codes_specialist_all on public.access_codes;
create policy access_codes_specialist_all on public.access_codes
for all to authenticated using (public.is_specialist()) with check (public.is_specialist());

grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to authenticated;
grant select on public.app_settings to anon;

-- Postgres grants EXECUTE to PUBLIC by default; close every internal entry point.
revoke execute on function public.submit_assessment_scoring(text, text, integer, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.get_public_catalog() from public, anon;
revoke execute on function public.get_assessment_public(text) from public, anon;
revoke execute on function public.issue_assessment_access_code(uuid, integer) from public, anon;
revoke execute on function public.list_access_codes() from public, anon;
revoke execute on function public.revoke_access_code(uuid) from public, anon;
revoke execute on function public.create_specialist_account(text, text, text, text) from public, anon;
revoke execute on function public.delete_specialist_account(uuid) from public, anon;

grant execute on function public.is_specialist() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.get_public_catalog() to authenticated;
grant execute on function public.get_assessment_public(text) to authenticated;
grant execute on function public.get_public_settings() to anon, authenticated;
grant execute on function public.get_assessment_by_access_code(text) to anon, authenticated;
grant execute on function public.submit_assessment(text, text, integer, text, text, text, jsonb, text) to anon, authenticated;
grant execute on function public.issue_assessment_access_code(uuid, integer) to authenticated;
grant execute on function public.list_access_codes() to authenticated;
grant execute on function public.revoke_access_code(uuid) to authenticated;
grant execute on function public.create_specialist_account(text, text, text, text) to authenticated;
grant execute on function public.delete_specialist_account(uuid) to authenticated;

-- =============================================================================
-- 7. PUBLIC SETTINGS SEED
-- =============================================================================

insert into public.app_settings (key, value) values
  ('public.siteNameAr', '"منصة التقييم الإكلينيكي"'),
  ('public.siteNameEn', '"Clinical Assessment Platform"'),
  ('public.universityAr', '"جامعة المنوفية"'),
  ('public.universityEn', '"Menoufia University"'),
  ('public.welcomeAr', '"أداة تقييم إكلينيكي متكاملة تُستخدم داخل السياق العلاجي والتربوي."'),
  ('public.welcomeEn', '"An integrated clinical assessment tool for therapeutic and educational practice."'),
  ('public.consentAr', '"أوافق على استخدام استجاباتي لأغراض التقييم الإكلينيكي، مع الحفاظ على سرية البيانات."'),
  ('public.consentEn', '"I agree that my responses may be used for clinical assessment purposes, with confidentiality maintained."'),
  ('public.thanksAr', '"تم تسجيل استجاباتك بنجاح. شكراً لوقتك وتعاونك."'),
  ('public.thanksEn', '"Your responses have been recorded. Thank you for your time and cooperation."'),
  ('public.footerAr', '"جامعة المنوفية — منصة التقييم الإكلينيكي"'),
  ('public.footerEn', '"Menoufia University — Clinical Assessment Platform"')
on conflict (key) do nothing;

-- =============================================================================
-- 8. FIRST ADMIN ACCOUNT (change the password after first login)
-- =============================================================================

do $$
declare
  v_uid uuid;
begin
  if not exists (select 1 from auth.users where email = 'admin@menoufia.edu.eg') then
    v_uid := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change_token_new,
      email_change_token_current, phone_change_token, reauthentication_token,
      email_change, phone_change, is_super_admin, is_sso_user, is_anonymous
    ) values (
      '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
      'admin@menoufia.edu.eg', extensions.crypt('Admin@2026', extensions.gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      '', '', '', '', '', '', '', '', false, false, false
    );
    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', 'admin@menoufia.edu.eg', 'email_verified', true),
      'email', 'admin@menoufia.edu.eg', now(), now(), now()
    );
    insert into public.specialists (id, full_name, email, role)
    values (v_uid, 'مدير النظام', 'admin@menoufia.edu.eg', 'admin');
  end if;
end $$;
