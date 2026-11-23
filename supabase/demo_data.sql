-- Psychometric Hub — demo mode
-- Creates a ready-to-use demo specialist account and realistic demo reports.
-- Safe to re-run: public.seed_demo_data() removes previous DEMO-* sessions first.

-- =============================================================================
-- 1. DEMO SPECIALIST ACCOUNT
-- =============================================================================

do $$
declare
  v_uid uuid;
begin
  if not exists (select 1 from auth.users where email = 'demo@menoufia.edu.eg') then
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
      'demo@menoufia.edu.eg', extensions.crypt('Demo@2026', extensions.gen_salt('bf')),
      now(), now(), now(),
      '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
      '', '', '', '', '', '', '', '', false, false, false
    );

    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_uid,
      jsonb_build_object('sub', v_uid::text, 'email', 'demo@menoufia.edu.eg', 'email_verified', true),
      'email', 'demo@menoufia.edu.eg', now(), now(), now()
    );

    insert into public.specialists (id, full_name, email, role)
    values (v_uid, 'حساب العرض التجريبي', 'demo@menoufia.edu.eg', 'admin');
  end if;
end $$;

-- =============================================================================
-- 2. IDENTITY HELPER (used by the reset button in the dashboard)
-- =============================================================================

create or replace function public.seed_demo_data() returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_a_id uuid;
  v_item record;
  v_rec record;
  v_result jsonb;
  v_session_id uuid;
  v_session_code text;
  v_code text;
  v_answers jsonb;
  v_score integer;
  v_i integer;
  v_created timestamptz;
  v_count integer := 0;
  v_stress_ar text[] := array[
    'أشعر أن الأمور تتجاوز قدرتي على التحكم.',
    'أجد صعوبة في التوقف عن التفكير في مشاكلي.',
    'أشعر بالتوتر في معظم أوقات اليوم.',
    'أجد صعوبة في الاسترخاء مساءً.',
    'أشعر أن طاقتي استُنزفت بسرعة.',
    'أتأثر كثيراً بالأخبار والمواقف اليومية.',
    'أجد صعوبة في التركيز على عمل واحد.',
    'أشعر بضيق في الصدر عند الضغط.',
    'أتجنب المواقف التي تتطلب قرارات سريعة.',
    'أشعر أنني بحاجة إلى فترة راحة طويلة.',
    'ألاحظ تغيّراً في نومي بسبب الضغط.',
    'أشعر أنني أتعامل مع الأمور بهدوء.'
  ];
  v_stress_en text[] := array[
    'I feel things are beyond my control.',
    'I find it hard to stop thinking about my problems.',
    'I feel tense during most of the day.',
    'I find it hard to relax in the evening.',
    'I feel my energy is drained quickly.',
    'I am strongly affected by daily events.',
    'I find it hard to focus on one task.',
    'I feel tightness in my chest under pressure.',
    'I avoid situations that need quick decisions.',
    'I feel I need a long break.',
    'I notice changes in my sleep due to stress.',
    'I feel I handle things calmly.'
  ];
  v_coping_ar text[] := array[
    'أخطط لخطوات واضحة عند مواجهة مشكلة.',
    'أطلب المساعدة من شخص أثق به.',
    'أحاول رؤية الجانب الإيجابي من الموقف.',
    'أؤجل الحل وأفكر فيه لاحقاً.',
    'أمارس نشاطاً بدنياً عند الضغط.',
    'أكتب ما أشعر به لتنظيم أفكاري.',
    'أتجنب الحديث عن المشكلة مع الآخرين.',
    'أقسّم المشكلة إلى أجزاء صغيرة.',
    'ألجأ إلى الروتين اليومي المعتاد.',
    'أعيد تقييم أولوياتي بسرعة.'
  ];
  v_coping_en text[] := array[
    'I plan clear steps when facing a problem.',
    'I ask someone I trust for help.',
    'I try to see the positive side of a situation.',
    'I postpone solving it and think later.',
    'I do physical activity when stressed.',
    'I write down my feelings to organize my thoughts.',
    'I avoid talking about the problem with others.',
    'I break the problem into smaller parts.',
    'I rely on my usual daily routine.',
    'I quickly reconsider my priorities.'
  ];
begin
  -- Reset previous demo data only.
  delete from public.reports where coalesce(snapshot->>'demo', '') = 'true';
  delete from public.sessions where patient_code like 'DEMO-%';
  delete from public.assessment_items where assessment_id in (
    select id from public.assessments where slug in ('stress-check', 'coping-style')
  );
  delete from public.assessments where slug in ('stress-check', 'coping-style');

  -- Extra demo assessments (patient-facing labels stay neutral).
  insert into public.assessments (
    slug, title_ar, title_en, patient_label_ar, patient_label_en,
    category, suite, description_ar, description_en, instructions_ar, instructions_en,
    version, active, cutoffs, critical_rules, sort_order
  ) values (
    'stress-check', 'استبيان التوتر العام', 'General Stress Checklist',
    'استبيان الحالة العامة', 'General Wellbeing Checklist',
    'clinical', 'clinical',
    'أداة من 12 بنداً لقياس مستوى الضغط النفسي والتوتر.',
    'A 12-item tool for measuring perceived stress.',
    'اختر الإجابة الأقرب إلى حالتك خلال آخر شهر.',
    'Choose the answer closest to how you felt over the past month.',
    '1.0', true,
    '[
      {"min":0,"max":11,"key":"low","ar":"منخفض","en":"Low","descAr":"مستوى ضغط منخفض ضمن المعدل المعتاد.","descEn":"Low stress level."},
      {"min":12,"max":23,"key":"moderate","ar":"متوسط","en":"Moderate","descAr":"مستوى ضغط متوسط يستحق المتابعة الدورية.","descEn":"Moderate stress level."},
      {"min":24,"max":36,"key":"high","ar":"مرتفع","en":"High","descAr":"مستوى ضغط مرتفع يتطلب تدخلاً إكلينيكياً.","descEn":"High stress level."}
    ]'::jsonb,
    '[
      {"position":11,"minScore":2,"type":"follow_up","severity":"high","titleAr":"متابعة إكلينيكية — البند 11","bodyAr":"استجابة مرتفعة في بند اضطراب النوم، يُنصح بمراجعة الحالة مع المتخصص.","titleEn":"Clinical follow-up — item 11","bodyEn":"Elevated response on the sleep item; specialist review recommended."}
    ]'::jsonb,
    20
  ), (
    'coping-style', 'مقياس أساليب التكيف', 'Coping Styles Inventory',
    'استبيان خصائص الشخصية', 'Personality Checklist',
    'personality', 'special',
    'أداة من 10 بنود لاستكشاف طرق التعامل مع الضغوط.',
    'A 10-item tool for exploring ways of handling pressure.',
    'اختر الإجابة التي تعبّر عنك عادةً.',
    'Choose the answer that usually describes you.',
    '1.0', true,
    '[
      {"min":0,"max":12,"key":"balanced","ar":"متوازن","en":"Balanced","descAr":"نمط تكيف متوازن ومرن.","descEn":"Balanced coping pattern."},
      {"min":13,"max":20,"key":"developing","ar":"قيد التطور","en":"Developing","descAr":"بعض الأساليب تحتاج إلى تنمية وتدعيم.","descEn":"Some coping skills could be strengthened."},
      {"min":21,"max":30,"key":"strained","ar":"مجهود","en":"Strained","descAr":"أساليب التكيف الحالية مرهقة وتستحق الدعم.","descEn":"Current coping style appears strained."}
    ]'::jsonb,
    '[]'::jsonb,
    30
  );

  -- Items for stress-check.
  select id into v_a_id from public.assessments where slug = 'stress-check';
  for v_i in 1 .. array_length(v_stress_ar, 1) loop
    insert into public.assessment_items (assessment_id, position, domain_ar, text_ar, text_en, options)
    values (
      v_a_id, v_i, 'التوتر العام', v_stress_ar[v_i], v_stress_en[v_i],
      jsonb_build_array(
        jsonb_build_object('score', 0, 'ar', 'لا يحدث ذلك أبداً', 'en', 'Never'),
        jsonb_build_object('score', 1, 'ar', 'يحدث أحياناً', 'en', 'Sometimes'),
        jsonb_build_object('score', 2, 'ar', 'يحدث غالباً', 'en', 'Often'),
        jsonb_build_object('score', 3, 'ar', 'يحدث دائماً تقريباً', 'en', 'Almost always')
      )
    );
  end loop;

  -- Items for coping-style.
  select id into v_a_id from public.assessments where slug = 'coping-style';
  for v_i in 1 .. array_length(v_coping_ar, 1) loop
    insert into public.assessment_items (assessment_id, position, domain_ar, text_ar, text_en, options)
    values (
      v_a_id, v_i, 'أساليب التكيف', v_coping_ar[v_i], v_coping_en[v_i],
      jsonb_build_array(
        jsonb_build_object('score', 0, 'ar', 'لا أفعل ذلك أبداً', 'en', 'Never'),
        jsonb_build_object('score', 1, 'ar', 'أفعل ذلك قليلاً', 'en', 'Slightly'),
        jsonb_build_object('score', 2, 'ar', 'أفعل ذلك غالباً', 'en', 'Often'),
        jsonb_build_object('score', 3, 'ar', 'أفعل ذلك دائماً', 'en', 'Always')
      )
    );
  end loop;

  -- Demo scenarios.
  for v_rec in
    select * from (values
      ('bdi-ii'::text, 'أحمد م. (تجريبي)'::text, 28::int, 'ذكر'::text, 'د. محمد حسن'::text, 1::int, 'minimal'::text),
      ('bdi-ii'::text, 'سارة ع. (تجريبي)'::text, 34::int, 'أنثى'::text, 'د. محمد حسن'::text, 2::int, 'mild'::text),
      ('bdi-ii'::text, 'محمود أ. (تجريبي)'::text, 22::int, 'ذكر'::text, 'د. محمد حسن'::text, 3::int, 'moderate'::text),
      ('bdi-ii'::text, 'نور س. (تجريبي)'::text, 41::int, 'أنثى'::text, 'د. محمد حسن'::text, 4::int, 'severe'::text),
      ('bdi-ii'::text, 'خالد ر. (تجريبي)'::text, 19::int, 'ذكر'::text, 'د. محمد حسن'::text, 5::int, 'critical9'::text),
      ('bdi-ii'::text, 'ريم ف. (تجريبي)'::text, 37::int, 'أنثى'::text, 'د. محمد حسن'::text, 6::int, 'critical2'::text),
      ('stress-check'::text, 'يوسف ن. (تجريبي)'::text, 30::int, 'ذكر'::text, 'د. سارة علي'::text, 8::int, 'stress_low'::text),
      ('stress-check'::text, 'هالة م. (تجريبي)'::text, 45::int, 'أنثى'::text, 'د. سارة علي'::text, 9::int, 'stress_mid'::text),
      ('stress-check'::text, 'عمر خ. (تجريبي)'::text, 26::int, 'ذكر'::text, 'د. سارة علي'::text, 10::int, 'stress_high'::text),
      ('coping-style'::text, 'منى أ. (تجريبي)'::text, 33::int, 'أنثى'::text, 'د. سارة علي'::text, 11::int, 'coping_low'::text),
      ('coping-style'::text, 'طارق ي. (تجريبي)'::text, 39::int, 'ذكر'::text, 'د. سارة علي'::text, 12::int, 'coping_high'::text)
    ) as t(slug, patient_name, patient_age, patient_gender, examiner, days_ago, pattern)
  loop
    select id into v_a_id from public.assessments where slug = v_rec.slug;
    v_answers := '[]'::jsonb;

    for v_item in select position from public.assessment_items where assessment_id = v_a_id order by position loop
      v_score := case v_rec.pattern
        when 'minimal' then 0
        when 'mild' then case when v_item.position <= 12 then 1 else 0 end
        when 'moderate' then case when v_item.position <= 9 then 2 when v_item.position <= 16 then 1 else 0 end
        when 'severe' then case when v_item.position <= 12 then 3 else 2 end
        when 'critical9' then case when v_item.position = 9 then 3 else 1 end
        when 'critical2' then case when v_item.position = 2 then 2 when v_item.position <= 10 then 1 else 0 end
        when 'stress_low' then case when v_item.position = 12 then 0 else 0 end
        when 'stress_mid' then case when v_item.position <= 8 then 2 else 0 end
        when 'stress_high' then case when v_item.position <= 10 then 3 else 2 end
        when 'coping_low' then case when v_item.position <= 5 then 1 else 0 end
        when 'coping_high' then case when v_item.position <= 9 then 3 else 2 end
        else 0
      end;

      v_answers := v_answers || jsonb_build_object(
        'position', v_item.position,
        'scores', jsonb_build_array(v_score)
      );
    end loop;

    v_result := public.submit_assessment(
      v_rec.slug, v_rec.patient_name, v_rec.patient_age, v_rec.patient_gender,
      v_rec.examiner, 'بيانات تجريبية للعرض — لا تُستخدم للتشخيص', v_answers
    );
    v_session_code := v_result->>'code';

    select id into v_session_id from public.sessions where patient_code = v_session_code;
    v_code := 'DEMO-' || substring(v_session_code from 5);
    v_created := now() - (v_rec.days_ago || ' days')::interval;

    update public.sessions
    set patient_code = v_code,
        created_at = v_created,
        session_date = v_created::date,
        completed_at = v_created
    where id = v_session_id;

    update public.reports
    set created_at = v_created,
        snapshot = jsonb_set(snapshot, '{demo}', 'true'::jsonb)
    where session_id = v_session_id;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'demoReports', v_count);
end $$;

grant execute on function public.seed_demo_data() to authenticated;

select public.seed_demo_data();
