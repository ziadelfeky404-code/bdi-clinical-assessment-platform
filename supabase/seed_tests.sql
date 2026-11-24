-- Seed: additional standardized clinical assessments
-- All assessments in this file belong to the clinical suite (الحقيبة الإكلينيكية).
-- Scoring stays server-side; the patient API never exposes keys, cutoffs or domain titles.

-- =============================================================================
-- Yale-Brown Obsessive Compulsive Scale (Y-BOCS)
-- =============================================================================
do $$
declare
  v_id uuid;
begin
  insert into public.assessments (
    slug, title_ar, title_en, patient_label_ar, patient_label_en, category, suite,
    description_ar, description_en, instructions_ar, instructions_en,
    version, active, sort_order, cutoffs, critical_rules, scale_meta
  ) values (
    'y-bocs',
    'مقياس ييل براون للوسواس القهري',
    'Yale-Brown Obsessive Compulsive Scale (Y-BOCS)',
    'استبيان تقييم إكلينيكي',
    'Clinical rating inventory',
    'clinical', 'clinical',
    'أداة من 10 بنود لتقييم تكرار بعض الأفكار والسلوكيات وأثرها في الحياة اليومية خلال الأسبوع الماضي.',
    'A 10-item tool for rating the frequency and daily-life impact of recurring thoughts and actions over the past week.',
    'لكل بند، اختر العبارة التي تصف معدل حدوث ما ورد خلال السبعة أيام الماضية، بما فيها وقت الجلسة.',
    'For each item, choose the statement that best describes the past seven days, including the session time.',
    '1.0', true, 20,
    '[
      {"key":"subclinical","min":0,"max":7,"ar":"تحت العتبة السريرية","en":"Subclinical","descAr":"درجات منخفضة جداً لا تشير إلى اضطراب وسواسي قهري ذي دلالة سريرية.","descEn":"Very low scores; no clinically significant obsessive-compulsive symptoms.","tone":"emerald"},
      {"key":"mild","min":8,"max":15,"ar":"خفيف","en":"Mild","descAr":"أعراض خفيفة قابلة للملاحظة، وقد تستدعي متابعة دورية وتقييماً سياقياً.","descEn":"Mild symptoms; periodic monitoring and contextual assessment may be appropriate.","tone":"amber"},
      {"key":"moderate","min":16,"max":23,"ar":"متوسط","en":"Moderate","descAr":"أعراض متوسطة تؤثر في الأداء اليومي وتستدعي خطة تدخل إكلينيكي منظم.","descEn":"Moderate symptoms affecting daily functioning; a structured intervention plan is indicated.","tone":"orange"},
      {"key":"severe","min":24,"max":31,"ar":"شديد","en":"Severe","descAr":"أعراض شديدة ذات أثر واضح على الأداء، وتتطلب تدخلاً متخصصاً ومتابعة قريبة.","descEn":"Severe symptoms with marked functional impact; specialist intervention and close follow-up are required.","tone":"rose"},
      {"key":"extreme","min":32,"max":40,"ar":"شديد جداً","en":"Extreme","descAr":"درجات قصوى تعكس أثراً بالغاً وتتطلب تقييماً وتدخلاً عاجلاً متعدد التخصصات.","descEn":"Extreme scores reflecting severe impairment; prompt multidisciplinary assessment and intervention are required.","tone":"rose"}
    ]'::jsonb,
    '[]'::jsonb,
    '[
      {"key":"obsession","ar":"الأفكار الوسواسية","en":"Obsessions","max":20,"elevate":12},
      {"key":"compulsion","ar":"الأفعال القهرية","en":"Compulsions","max":20,"elevate":12}
    ]'::jsonb
  )
  on conflict (slug) do update set
    title_ar = excluded.title_ar,
    title_en = excluded.title_en,
    patient_label_ar = excluded.patient_label_ar,
    patient_label_en = excluded.patient_label_en,
    description_ar = excluded.description_ar,
    description_en = excluded.description_en,
    instructions_ar = excluded.instructions_ar,
    instructions_en = excluded.instructions_en,
    cutoffs = excluded.cutoffs,
    critical_rules = excluded.critical_rules,
    scale_meta = excluded.scale_meta,
    suite = 'clinical'
  returning id into v_id;

  delete from public.assessment_items where assessment_id = v_id;

  insert into public.assessment_items (assessment_id, position, domain_ar, domain_en, title_ar, title_en, text_ar, text_en, scales, options) values
    (v_id, 1, 'الأفكار الوسواسية', 'Obsessions', 'زمن الأفكار الوسواسية', 'Time spent',
     'مقدار الوقت الذي تستغرقه الأفكار الوسواسية خلال السبعة أيام الماضية بما فيها وقت الجلسة.',
     'Amount of time spent on obsessions during the past seven days, including the session.',
     '[{"key":"obsession","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا شيء.","en":"None."},{"score":1,"ar":"أقل من ساعة في اليوم، أو تتكرر أحياناً بمعدل 8 مرات فأقل يومياً.","en":"Less than one hour per day, or occasional, 8 or fewer times daily."},{"score":2,"ar":"من ساعة إلى 3 ساعات في اليوم، أو تتكرر أكثر من 8 مرات في اليوم لكن ساعات اليوم خالية من الأفكار الوسواسية.","en":"One to three hours per day, or more than 8 times daily with obsession-free hours."},{"score":3,"ar":"من 3 إلى 8 ساعات في اليوم، أو تحدث كثيراً جداً في معظم ساعات اليوم.","en":"Three to eight hours per day, or very frequent during most hours."},{"score":4,"ar":"أكثر من 8 ساعات في اليوم، أو تحدث بشكل دائم بحيث لا تمر ساعة دون وساوس كثيرة.","en":"More than eight hours per day, or continuous with hardly an hour free of obsessions."}]'::jsonb),

    (v_id, 2, 'الأفكار الوسواسية', 'Obsessions', 'تعارض الأفكار مع الأنشطة', 'Interference',
     'مقدار التعارض الذي تحدثه الأفكار الوسواسية مع نشاطاتك الاجتماعية أو العملية.',
     'Interference caused by obsessions with social or occupational activities.',
     '[{"key":"obsession","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا يتأثر النشاط العام.","en":"No interference."},{"score":1,"ar":"تعارض خفيف مع النشاطات الاجتماعية أو العملية، ولكن النشاط العام لا يتأثر.","en":"Slight interference, but overall functioning is not impaired."},{"score":2,"ar":"تعارض واضح في النشاطات الاجتماعية أو العملية، ولكن يمكن السيطرة عليه.","en":"Definite interference but still manageable."},{"score":3,"ar":"يسبب خللاً كبيراً في أداء النشاطات الاجتماعية أو العملية.","en":"Marked interference in social or occupational functioning."},{"score":4,"ar":"يسبب عجزاً بليغاً في الأداء.","en":"Severe interference/incapacitating."}]'::jsonb),

    (v_id, 3, 'الأفكار الوسواسية', 'Obsessions', 'القلق المصاحب', 'Distress',
     'مقدار التوتر والقلق المصاحب للأفكار الوسواسية.',
     'Distress associated with the obsessions.',
     '[{"key":"obsession","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا يوجد.","en":"None."},{"score":1,"ar":"خفيف أحياناً، وليس مزعجاً.","en":"Mild, occasional, not upsetting."},{"score":2,"ar":"متوسط غالباً، مزعج ولكن يمكن السيطرة عليه.","en":"Moderate, frequent, upsetting but controllable."},{"score":3,"ar":"شديد أغلب الوقت ومزعج جداً.","en":"Severe, most of the time, very distressing."},{"score":4,"ar":"بليغ، يسبب عجزاً شديداً ومستمراً.","en":"Extreme, incapacitating distress."}]'::jsonb),

    (v_id, 4, 'الأفكار الوسواسية', 'Obsessions', 'مقاومة الأفكار', 'Resistance',
     'مقدار الجهد المبذول في مقاومة الأفكار الوسواسية.',
     'Effort made to resist the obsessions.',
     '[{"key":"obsession","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا حاجة للمقاومة لأن الأفكار قليلة أو غائبة.","en":"No resistance needed; obsessions are minimal or absent."},{"score":1,"ar":"مقاومة خفيفة؛ يحاول المقاومة أحياناً دون بذل جهد كبير.","en":"Slight resistance; tries to resist occasionally without much effort."},{"score":2,"ar":"مقاومة متوسطة؛ يحاول المقاومة في معظم الأحيان ويبذل جهداً بعض الوقت.","en":"Moderate resistance; attempts to resist most of the time with some effort."},{"score":3,"ar":"مقاومة قوية؛ يقاوم باستمرار لكن بصعوبة، ولا يستسلم تماماً.","en":"Strong resistance; resists continuously but with difficulty."},{"score":4,"ar":"يستسلم تماماً للأفكار دون محاولة مقاومة تذكر.","en":"Complete surrender; no attempt to resist."}]'::jsonb),

    (v_id, 5, 'الأفكار الوسواسية', 'Obsessions', 'السيطرة على الأفكار', 'Control',
     'مقدار سيطرتك على الأفكار الوسواسية.',
     'Degree of control over the obsessions.',
     '[{"key":"obsession","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"سيطرة تامة.","en":"Complete control."},{"score":1,"ar":"سيطرة كبيرة؛ يستطيع عادة إيقاف الفكرة أو صرف الانتباه عنها بجهد بسيط.","en":"Much control; usually able to stop or divert attention with modest effort."},{"score":2,"ar":"سيطرة متوسطة؛ يستطيع أحياناً صرف الانتباه عن الفكرة بصعوبة.","en":"Moderate control; sometimes able to divert attention with difficulty."},{"score":3,"ar":"سيطرة قليلة؛ ينجح نادراً في إيقاف الفكرة أو صرف الانتباه عنها.","en":"Little control; rarely able to stop or divert attention."},{"score":4,"ar":"لا سيطرة؛ لا يستطيع صرف الانتباه عن الفكرة حتى للحظات.","en":"No control; unable to divert attention even briefly."}]'::jsonb),

    (v_id, 6, 'الأفعال القهرية', 'Compulsions', 'زمن الأفعال القهرية', 'Time spent',
     'مقدار الوقت الذي تقضيه في أداء الأفعال القهرية خلال السبعة أيام الماضية.',
     'Amount of time spent performing compulsions during the past seven days.',
     '[{"key":"compulsion","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا شيء.","en":"None."},{"score":1,"ar":"أقل من ساعة في اليوم، أو أحياناً بمعدل 8 مرات فأقل يومياً.","en":"Less than one hour per day, or occasional, 8 or fewer times daily."},{"score":2,"ar":"من ساعة إلى 3 ساعات في اليوم، أو أكثر من 8 مرات يومياً.","en":"One to three hours per day, or more than 8 times daily."},{"score":3,"ar":"من 3 إلى 8 ساعات في اليوم، أو كثيراً جداً في معظم ساعات اليوم.","en":"Three to eight hours per day, or very frequent during most hours."},{"score":4,"ar":"أكثر من 8 ساعات في اليوم، أو بشكل دائم بحيث لا تمر ساعة دون أداء الفعل.","en":"More than eight hours per day, or continuous."}]'::jsonb),

    (v_id, 7, 'الأفعال القهرية', 'Compulsions', 'تعارض الأفعال', 'Interference',
     'مقدار التعارض الذي تحدثه الأفعال القهرية مع نشاطاتك الاجتماعية أو العملية.',
     'Interference caused by compulsions with social or occupational activities.',
     '[{"key":"compulsion","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا يتأثر النشاط العام.","en":"No interference."},{"score":1,"ar":"تعارض خفيف مع النشاطات الاجتماعية أو العملية، ولكن النشاط العام لا يتأثر.","en":"Slight interference, but overall functioning is not impaired."},{"score":2,"ar":"تعارض واضح ولكن يمكن السيطرة عليه.","en":"Definite interference but still manageable."},{"score":3,"ar":"يسبب خللاً كبيراً في أداء النشاطات.","en":"Marked interference in functioning."},{"score":4,"ar":"يسبب عجزاً بليغاً في الأداء.","en":"Severe interference/incapacitating."}]'::jsonb),

    (v_id, 8, 'الأفعال القهرية', 'Compulsions', 'القلق عند منع الفعل', 'Distress',
     'مقدار التوتر والقلق الناتج عن محاولة الامتناع عن الأفعال القهرية.',
     'Anxiety if prevented from performing the compulsion.',
     '[{"key":"compulsion","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا يوجد قلق عند الامتناع.","en":"None."},{"score":1,"ar":"قلق بسيط عند الامتناع يمكن احتماله.","en":"Mild anxiety when prevented, easily tolerated."},{"score":2,"ar":"قلق واضح عند الامتناع يمكن احتماله بصعوبة.","en":"Moderate anxiety when prevented, tolerated with difficulty."},{"score":3,"ar":"قلق شديد جداً عند الامتناع يسبب عجزاً كبيراً.","en":"Severe anxiety when prevented, causing marked impairment."},{"score":4,"ar":"قلق بليغ يسبب عجزاً كاملاً عند الامتناع.","en":"Extreme, incapacitating anxiety when prevented."}]'::jsonb),

    (v_id, 9, 'الأفعال القهرية', 'Compulsions', 'مقاومة الأفعال', 'Resistance',
     'مقدار الجهد المبذول في مقاومة الأفعال القهرية.',
     'Effort made to resist the compulsions.',
     '[{"key":"compulsion","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"لا حاجة للمقاومة لأن الأفعال قليلة أو غائبة.","en":"No resistance needed; compulsions are minimal or absent."},{"score":1,"ar":"مقاومة خفيفة؛ يحاول المقاومة أحياناً.","en":"Slight resistance; tries to resist occasionally."},{"score":2,"ar":"مقاومة متوسطة؛ يحاول المقاومة في معظم الأحيان ويبذل جهداً بعض الوقت.","en":"Moderate resistance; attempts to resist most of the time with some effort."},{"score":3,"ar":"مقاومة قوية؛ يقاوم باستمرار لكن بصعوبة.","en":"Strong resistance; resists continuously but with difficulty."},{"score":4,"ar":"يستسلم تماماً للأفعال دون محاولة مقاومة تذكر.","en":"Complete surrender; no attempt to resist."}]'::jsonb),

    (v_id, 10, 'الأفعال القهرية', 'Compulsions', 'السيطرة على الأفعال', 'Control',
     'مقدار سيطرتك على الأفعال القهرية.',
     'Degree of control over the compulsions.',
     '[{"key":"compulsion","direction":"positive"}]'::jsonb,
     '[{"score":0,"ar":"سيطرة تامة.","en":"Complete control."},{"score":1,"ar":"سيطرة كبيرة؛ يستطيع عادة إيقاف الفعل أو تأخيره بسهولة.","en":"Much control; usually able to stop or delay the compulsion easily."},{"score":2,"ar":"سيطرة متوسطة؛ يستطيع تأخير الفعل بصعوبة في بعض الأحيان.","en":"Moderate control; able to delay with some difficulty."},{"score":3,"ar":"سيطرة قليلة؛ ينجح نادراً في تأخير الفعل.","en":"Little control; rarely able to delay."},{"score":4,"ar":"لا سيطرة؛ لا يستطيع تأخير الفعل حتى للحظات.","en":"No control; unable to delay even briefly."}]'::jsonb);
end $$;

-- =============================================================================
-- Raven's Standard Progressive Matrices (SPM), 60 items
-- Answer key: classic SPM A-E. Images copied verbatim from the supplied Arabic booklet.
-- Norms below are an explicitly approximate teaching table for ages 13-25;
-- the specialist report should always interpret them in age context.
-- =============================================================================
do $$
declare
  v_id uuid;
  v_keys integer[] := array[
    4,5,1,2,6,3,6,2,1,3,4,5,
    2,6,1,2,1,3,5,6,4,3,4,5,
    8,2,3,8,7,4,5,1,7,6,1,2,
    3,4,3,7,8,6,5,4,1,2,5,6,
    7,6,8,2,1,5,1,6,3,2,4,5
  ];
  v_pos integer;
  v_set_index integer;
  v_set_letter text;
  v_local integer;
  v_choices integer;
  v_correct integer;
  v_opts jsonb;
  v_scales jsonb;
begin
  insert into public.assessments (
    slug, title_ar, title_en, patient_label_ar, patient_label_en, category, suite,
    description_ar, description_en, instructions_ar, instructions_en,
    version, active, sort_order, cutoffs, critical_rules, scale_meta
  ) values (
    'raven-spm',
    'اختبار المصفوفات المتتابعة لرافن (النسخة القياسية)',
    'Raven''s Standard Progressive Matrices (SPM)',
    'مصفوفات بصرية',
    'Visual matrices',
    'clinical', 'clinical',
    'ستون مصفوفة مصورة مرتبة في خمس مجموعات، لكل مصفوفة خيار صحيح واحد.',
    'Sixty visual matrices in five sets, with one correct option per matrix.',
    'انظر إلى كل مصفوفة، ثم اختر الخيار الذي يكمل النمط. لا يوجد زر تالٍ؛ سيتم الانتقال تلقائياً بعد الاختيار.',
    'Look at each matrix and choose the option that completes the pattern. The next item appears automatically after each choice.',
    '1.0', true, 30,
    '[
      {"key":"below","min":0,"max":24,"ar":"أقل من المتوسط بكثير","en":"Below average","descAr":"درجة منخفضة مقارنة بالجدول التقريبي للأعمار 13-25؛ تُقرأ دائماً في ضوء العمر ومستوى التعليم.","descEn":"Low relative to the approximate 13-25 norm table; always interpret in age and education context.","tone":"rose"},
      {"key":"low","min":25,"max":36,"ar":"دون المتوسط","en":"Below average","descAr":"أداء أقل من المتوسط وفق الجدول التقريبي؛ يوصى بالتفسير الإكلينيكي المصاحب.","descEn":"Below-average performance on the approximate norm table; clinical context is required.","tone":"orange"},
      {"key":"average","min":37,"max":48,"ar":"متوسط","en":"Average","descAr":"أداء ضمن المدى المتوسط بحسب الجدول التقريبي للأعمار 13-25.","descEn":"Average performance on the approximate 13-25 norm table.","tone":"emerald"},
      {"key":"above","min":49,"max":54,"ar":"فوق المتوسط","en":"Above average","descAr":"أداء فوق المتوسط وفق الجدول التقريبي؛ قد يستفيد من معايير عمرية أدق.","descEn":"Above-average performance on the approximate table; more precise age norms may refine this.","tone":"sky"},
      {"key":"superior","min":55,"max":60,"ar":"متفوق","en":"Superior","descAr":"أداء مرتفع جداً ضمن هذا الجدول التقريبي؛ لا يُعد تشخيصاً بذاته.","descEn":"Very high performance on this approximate table; not a diagnosis by itself.","tone":"amber"}
    ]'::jsonb,
    '[]'::jsonb,
    '[
      {"key":"A","ar":"المجموعة أ","en":"Set A","max":12},
      {"key":"B","ar":"المجموعة ب","en":"Set B","max":12},
      {"key":"C","ar":"المجموعة ج","en":"Set C","max":12},
      {"key":"D","ar":"المجموعة د","en":"Set D","max":12},
      {"key":"E","ar":"المجموعة هـ","en":"Set E","max":12}
    ]'::jsonb
  )
  on conflict (slug) do update set
    title_ar = excluded.title_ar,
    title_en = excluded.title_en,
    patient_label_ar = excluded.patient_label_ar,
    patient_label_en = excluded.patient_label_en,
    description_ar = excluded.description_ar,
    description_en = excluded.description_en,
    instructions_ar = excluded.instructions_ar,
    instructions_en = excluded.instructions_en,
    cutoffs = excluded.cutoffs,
    critical_rules = excluded.critical_rules,
    scale_meta = excluded.scale_meta,
    suite = 'clinical'
  returning id into v_id;

  delete from public.assessment_items where assessment_id = v_id;

  for v_pos in 1..60 loop
    v_set_index := ((v_pos - 1) / 12) + 1;
    v_local := ((v_pos - 1) % 12) + 1;
    v_set_letter := case v_set_index when 1 then 'A' when 2 then 'B' when 3 then 'C' when 4 then 'D' else 'E' end;
    v_choices := case when v_set_index <= 2 then 6 else 8 end;
    v_correct := v_keys[v_pos];

    select jsonb_agg(jsonb_build_object(
      'score', case when s = v_correct then 1 else 0 end,
      'ar', to_char(s, 'FM9'),
      'en', to_char(s, 'FM9')
    ) order by s) into v_opts
    from generate_series(1, v_choices) as s;

    v_scales := jsonb_build_array(jsonb_build_object('key', v_set_letter, 'direction', 'positive'));

    insert into public.assessment_items (
      assessment_id, position, domain_ar, domain_en, title_ar, title_en,
      text_ar, text_en, image_url, options, scales
    ) values (
      v_id, v_pos,
      'المجموعة ' || v_set_letter, 'Set ' || v_set_letter,
      'المصفوفة ' || v_local, 'Matrix ' || v_local,
      '', '',
      'assets/raven/' || v_set_letter || lpad(v_local::text, 2, '0') || '.jpeg',
      v_opts, v_scales
    );
  end loop;
end $$;
