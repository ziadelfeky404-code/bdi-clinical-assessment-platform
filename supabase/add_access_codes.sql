-- Migration: specialist-issued, single-use numeric assessment access codes
-- Applies to psychometric-hub (ylpgsstplbeldiafxsti). Safe to re-run.

create extension if not exists pgcrypto with schema extensions;

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

create index if not exists idx_access_codes_hash on public.access_codes(code_hash);
create index if not exists idx_access_codes_lifecycle on public.access_codes(assessment_id, used_at, expires_at);

alter table public.access_codes enable row level security;
drop policy if exists access_codes_specialist_all on public.access_codes;
create policy access_codes_specialist_all on public.access_codes
  for all to authenticated
  using (public.is_specialist()) with check (public.is_specialist());

-- Keep the original scoring implementation under an internal name.
do $$
begin
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'submit_assessment' and p.pronargs = 7
  ) then
    alter function public.submit_assessment(text, text, integer, text, text, text, jsonb)
      rename to submit_assessment_scoring;
  end if;
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

-- Recent codes for the specialist, masked; includes status and expiry.
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

-- Public lookup by code: validates without consuming; returns neutral assessment content only.
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

-- Public submission now requires a valid single-use code (specialists may seed demo data by slug).
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

revoke execute on function public.submit_assessment_scoring(text, text, integer, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.get_public_catalog() from public, anon;
revoke execute on function public.get_assessment_public(text) from public, anon;
revoke execute on function public.issue_assessment_access_code(uuid, integer) from public, anon;
revoke execute on function public.list_access_codes() from public, anon;
revoke execute on function public.revoke_access_code(uuid) from public, anon;
revoke execute on function public.create_specialist_account(text, text, text, text) from public, anon;
revoke execute on function public.delete_specialist_account(uuid) from public, anon;
grant execute on function public.get_assessment_by_access_code(text) to anon, authenticated;
grant execute on function public.issue_assessment_access_code(uuid, integer) to authenticated;
grant execute on function public.list_access_codes() to authenticated;
grant execute on function public.revoke_access_code(uuid) to authenticated;
grant execute on function public.submit_assessment(text, text, integer, text, text, text, jsonb, text) to anon, authenticated;
