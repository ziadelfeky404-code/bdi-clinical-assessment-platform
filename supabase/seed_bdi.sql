-- Seed: Beck Depression Inventory (BDI-II) as the first clinical assessment
do $$
declare
  v_assessment_id uuid;
begin
  insert into public.assessments (
    slug, title_ar, title_en, patient_label_ar, patient_label_en, category, suite,
    description_ar, description_en,
    instructions_ar, instructions_en,
    version, active, sort_order, cutoffs, critical_rules
  ) values (
    'bdi-ii',
    'قائمة بيك للاكتئاب (النسخة الثانية)',
    'Beck Depression Inventory (BDI-II)',
    'أداة التقييم الإكلينيكي',
    'Clinical Assessment Inventory',
    'clinical',
    'clinical',
    'أداة من 21 بنداً لتقييم الحالة النفسية العامة والشعور بالأسبوعين الماضيين.',
    'A 21-item tool for assessing general psychological state and recent feelings over the past two weeks.',
    'اقرأ كل مجموعة من العبارات بعناية، ثم اختر العبارة الأقرب إلى شعورك خلال الأسبوعين الماضيين. سيتم الانتقال تلقائياً إلى البند التالي بعد الاختيار.',
    'Read each group of statements carefully and choose the one that best describes you over the past two weeks. The next item will appear automatically after each choice.',
    '2.0', true, 10,
    '[
      {"key":"minimal","min":0,"max":9,"ar":"داخل المدى الأقل (في حده الأدنى)","en":"Within Minimal Range (Minimal Depression)","descAr":"تشير الدرجة الكلية إلى خلو الحالة من الأعراض الاكتئابية الإكلينيكية الدالة، مع استقرار انفعالي عام ضمن الحدود الطبيعية.","descEn":"The total score indicates no clinically significant depressive symptoms, with general emotional stability within normal limits.","tone":"emerald"},
      {"key":"mild","min":10,"max":16,"ar":"اكتئاب معتدل","en":"Mild Depression","descAr":"تشير الدرجة الكلية إلى وجود أعراض اكتئابية خفيفة قد ترتبط بضغوط حياتية عابرة، وتستجيب بفعالية للإرشاد النفسي والدعم المعرفي.","descEn":"The total score suggests mild depressive symptoms, often related to transient stressors and responsive to counselling and cognitive support.","tone":"amber"},
      {"key":"moderate","min":17,"max":29,"ar":"اكتئاب متوسط","en":"Moderate Depression","descAr":"تشير الدرجة الكلية إلى مستوى متوسط من الأعراض المؤثرة على الأداء الوظيفي والمزاجي، مما يستدعي خطة تدخل معرفي سلوكي ومتابعة دورية.","descEn":"The total score indicates moderate symptoms affecting functioning and mood, warranting a CBT intervention plan and regular follow-up.","tone":"orange"},
      {"key":"severe","min":30,"max":63,"ar":"اكتئاب شديد","en":"Severe Depression","descAr":"تشير الدرجة الكلية إلى ارتفاع حاد في شدة الأعراض عبر الأبعاد المعرفية والوجدانية والبدنية، مما يتطلب تدخلاً إكلينيكياً متخصصاً وعاجلاً.","descEn":"The total score indicates a marked elevation across cognitive, affective and somatic dimensions, requiring prompt specialist intervention.","tone":"rose"}
    ]'::jsonb,
    '[
      {"position":9,"minScore":1,"type":"suicide","severity":"critical","titleAr":"تنبيه إكلينيكي حرج — البند (9): الأفكار الانتحارية","bodyAr":"أظهر المفحوص استجابة إيجابية في بند الأفكار الانتحارية. يجب إجراء مقابلة إكلينيكية فورية لتقييم الخطورة ووضع خطة أمان عاجلة.","titleEn":"CRITICAL ALERT — Item (9): Suicidal Ideation","bodyEn":"The examinee endorsed suicidal ideation. An immediate clinical risk assessment and safety plan are mandatory."},
      {"position":2,"minScore":1,"type":"pessimism","severity":"high","titleAr":"تنبيه إكلينيكي هام — البند (2): التشاؤم واليأس","bodyAr":"يُعد التشاؤم واليأس منبئاً إكلينيكياً هاماً بخطر إيذاء النفس. يُوصى بمتابعة هذا المؤشر بدقة.","titleEn":"CLINICAL WARNING — Item (2): Pessimism & Hopelessness","bodyEn":"Pessimism and hopelessness are important predictors of self-harm risk. Close clinical monitoring is advised."}
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
    version = excluded.version,
    cutoffs = excluded.cutoffs,
    critical_rules = excluded.critical_rules
  returning id into v_assessment_id;

  if not exists (select 1 from public.assessment_items where assessment_id = v_assessment_id) then
    insert into public.assessment_items (assessment_id, position, domain_ar, domain_en, title_ar, title_en, text_ar, text_en, options) values
      (v_assessment_id, 1, 'البُعد الوجداني', 'Affective', 'الحزن والكآبة', 'Sadness',
       'أشعر بالحزن والتعاسة لدرجة لا أستطيع تحملها.', 'I am so sad and unhappy that I can''t stand it.',
       '[{"score":0,"ar":"لا أشعر بالحزن.","en":"I do not feel sad."},{"score":1,"ar":"أشعر بالحزن.","en":"I feel sad."},{"score":2,"ar":"أشعر بالحزن طوال الوقت ولا أستطيع التخلص منه.","en":"I am sad all the time and I can''t snap out of it."},{"score":3,"ar":"أشعر بالحزن والتعاسة لدرجة لا أستطيع تحملها.","en":"I am so sad and unhappy that I can''t stand it."}]'::jsonb),

      (v_assessment_id, 2, 'البُعد المعرفي', 'Cognitive', 'التشاؤم (النظرة للمستقبل)', 'Pessimism',
       'أشعر أنه لا يوجد ما أتطلع إليه في المستقبل.', 'I feel I have nothing to look forward to.',
       '[{"score":0,"ar":"لست متشائماً بخصوص المستقبل.","en":"I am not particularly discouraged about the future."},{"score":1,"ar":"أشعر بالتشاؤم بخصوص المستقبل.","en":"I feel discouraged about the future."},{"score":2,"ar":"أشعر أنه لا يوجد ما أتطلع إليه في المستقبل.","en":"I feel I have nothing to look forward to."},{"score":3,"ar":"أشعر أن المستقبل ميئوس منه وأن الأمور لن تتحسن.","en":"I feel the future is hopeless and that things cannot improve."}]'::jsonb),

      (v_assessment_id, 3, 'البُعد المعرفي', 'Cognitive', 'الشعور بالفشل', 'Sense of Failure',
       'أشعر أنني فشلت أكثر من الشخص العادي.', 'I feel I have failed more than the average person.',
       '[{"score":0,"ar":"لا أشعر بأنني شخص فاشل.","en":"I do not feel like a failure."},{"score":1,"ar":"أشعر أنني فشلت أكثر من الشخص العادي.","en":"I feel I have failed more than the average person."},{"score":2,"ar":"عندما أنظر إلى حياتي السابقة، كل ما أراه هو الكثير من الفشل.","en":"As I look back on my life, all I can see is a lot of failures."},{"score":3,"ar":"أشعر أنني شخص فاشل تماماً.","en":"I feel I am a complete failure as a person."}]'::jsonb),

      (v_assessment_id, 4, 'البُعد الوجداني', 'Affective', 'فقدان الاستمتاع والرضا', 'Loss of Satisfaction',
       'لا أستمتع بالأشياء بالطريقة التي تعودت عليها.', 'I don''t enjoy things the way I used to.',
       '[{"score":0,"ar":"أحصل على نفس القدر من الرضا والاستمتاع بالأشياء كما تعودت.","en":"I get as much satisfaction out of things as I used to."},{"score":1,"ar":"لا أستمتع بالأشياء بالطريقة التي تعودت عليها.","en":"I don''t enjoy things the way I used to."},{"score":2,"ar":"لم أعد أحصل على رضا حقيقي من أي شيء.","en":"I don''t get real satisfaction out of anything anymore."},{"score":3,"ar":"أشعر بعدم الرضا والملل من كل شيء.","en":"I am dissatisfied or bored with everything."}]'::jsonb),

      (v_assessment_id, 5, 'البُعد المعرفي', 'Cognitive', 'الشعور بالذنب', 'Guilty Feelings',
       'أشعر بالذنب في كثير من الأحيان.', 'I feel guilty a good part of the time.',
       '[{"score":0,"ar":"لا أشعر بأي ذنب خاص.","en":"I don''t feel particularly guilty."},{"score":1,"ar":"أشعر بالذنب في كثير من الأحيان.","en":"I feel guilty a good part of the time."},{"score":2,"ar":"أشعر بالذنب الشديد في معظم الأوقات.","en":"I feel quite guilty most of the time."},{"score":3,"ar":"أشعر بالذنب طوال الوقت.","en":"I feel guilty all of the time."}]'::jsonb),

      (v_assessment_id, 6, 'البُعد المعرفي', 'Cognitive', 'توقع العقاب', 'Sense of Punishment',
       'أشعر أنني قد أتعرض لعقاب.', 'I feel I may be punished.',
       '[{"score":0,"ar":"لا أشعر أنني أتعرض لعقاب.","en":"I don''t feel I am being punished."},{"score":1,"ar":"أشعر أنني قد أتعرض لعقاب.","en":"I feel I may be punished."},{"score":2,"ar":"أتوقع أن أتعرض لعقاب.","en":"I expect to be punished."},{"score":3,"ar":"أشعر أنني أتعرض لعقاب بالفعل.","en":"I feel I am being punished."}]'::jsonb),

      (v_assessment_id, 7, 'البُعد المعرفي', 'Cognitive', 'عدم الرضا عن الذات', 'Self-Dislike',
       'أشعر بخيبة أمل في نفسي.', 'I am disappointed in myself.',
       '[{"score":0,"ar":"لا أشعر بخيبة أمل في نفسي.","en":"I don''t feel disappointed in myself."},{"score":1,"ar":"أشعر بخيبة أمل في نفسي.","en":"I am disappointed in myself."},{"score":2,"ar":"أشعر بالاشمئزاز من نفسي.","en":"I am disgusted with myself."},{"score":3,"ar":"أكره نفسي.","en":"I hate myself."}]'::jsonb),

      (v_assessment_id, 8, 'البُعد المعرفي', 'Cognitive', 'لوم الذات وانتقادها', 'Self-Accusation',
       'أنتقد نفسي بسبب نقاط ضعفي أو أخطائي.', 'I am critical of myself for my weaknesses or mistakes.',
       '[{"score":0,"ar":"لا أشعر أنني أسوأ من أي شخص آخر.","en":"I don''t feel I am any worse than anybody else."},{"score":1,"ar":"أنتقد نفسي بسبب نقاط ضعفي أو أخطائي.","en":"I am critical of myself for my weaknesses or mistakes."},{"score":2,"ar":"ألوم نفسي طوال الوقت على أخطائي.","en":"I blame myself all the time for my faults."},{"score":3,"ar":"ألوم نفسي على كل شيء سيئ يحدث.","en":"I blame myself for everything bad that happens."}]'::jsonb),

      (v_assessment_id, 9, 'البُعد المعرفي', 'Cognitive', 'الأفكار الانتحارية', 'Suicidal Ideation',
       'لدي أفكار للتخلص من حياتي، ولكنني لن أنفذها.', 'I have thoughts of killing myself, but I would not carry them out.',
       '[{"score":0,"ar":"ليس لدي أي أفكار للتخلص من حياتي.","en":"I don''t have any thoughts of killing myself."},{"score":1,"ar":"لدي أفكار للتخلص من حياتي، ولكنني لن أنفذها.","en":"I have thoughts of killing myself, but I would not carry them out."},{"score":2,"ar":"أرغب في أن أقتل نفسي.","en":"I would like to kill myself."},{"score":3,"ar":"سأقتل نفسي لو سنحت لي الفرصة.","en":"I would kill myself if I had the chance."}]'::jsonb),

      (v_assessment_id, 10, 'البُعد الوجداني', 'Affective', 'نوبات البكاء', 'Crying Spells',
       'أبكي الآن أكثر مما تعودت عليه.', 'I cry more now than I used to.',
       '[{"score":0,"ar":"لا أبكي أكثر من المعتاد.","en":"I don''t cry any more than usual."},{"score":1,"ar":"أبكي الآن أكثر مما تعودت عليه.","en":"I cry more now than I used to."},{"score":2,"ar":"أبكي طوال الوقت الآن.","en":"I cry all the time now."},{"score":3,"ar":"كنت قادراً على البكاء فيما مضى، ولكنني الآن لا أستطيع البكاء حتى لو أردت ذلك.","en":"I used to be able to cry, but now I can''t cry even though I want to."}]'::jsonb),

      (v_assessment_id, 11, 'البُعد الوجداني', 'Affective', 'سرعة الاستثارة والانزعاج', 'Irritability',
       'أصبح من السهل استثارتي أو إزعاجي أكثر مما اعتدت.', 'I am slightly more irritated now than usual.',
       '[{"score":0,"ar":"لست أكثر انزعاجاً أو استثارة الآن مما اعتدت عليه.","en":"I am no more irritated by things than I ever was."},{"score":1,"ar":"أصبح من السهل استثارتي أو إزعاجي أكثر مما اعتدت.","en":"I am slightly more irritated now than usual."},{"score":2,"ar":"أشعر بالانزعاج والاستثارة في معظم الأوقات.","en":"I am quite annoyed or irritated a good deal of the time."},{"score":3,"ar":"أشعر بالانزعاج والاستثارة طوال الوقت.","en":"I feel irritated all the time."}]'::jsonb),

      (v_assessment_id, 12, 'البُعد الوجداني', 'Affective', 'الانسحاب الاجتماعي', 'Social Withdrawal',
       'أصبحت أقل اهتماماً بالآخرين مما كنت عليه.', 'I am less interested in other people than I used to be.',
       '[{"score":0,"ar":"لم أفقد اهتمامي بالآخرين.","en":"I have not lost interest in other people."},{"score":1,"ar":"أصبحت أقل اهتماماً بالآخرين مما كنت عليه.","en":"I am less interested in other people than I used to be."},{"score":2,"ar":"فقدت معظم اهتمامي بالآخرين.","en":"I have lost most of my interest in other people."},{"score":3,"ar":"فقدت كل اهتمامي بالآخرين تماماً.","en":"I have lost all of my interest in other people."}]'::jsonb),

      (v_assessment_id, 13, 'البُعد المعرفي', 'Cognitive', 'التردد وصعوبة اتخاذ القرارات', 'Indecisiveness',
       'أؤجل اتخاذ القرارات أكثر مما تعودت عليه.', 'I put off making decisions more than I used to.',
       '[{"score":0,"ar":"أتخذ قراراتي بنفس الكفاءة التي تعودت عليها.","en":"I make decisions about as well as I ever could."},{"score":1,"ar":"أؤجل اتخاذ القرارات أكثر مما تعودت عليه.","en":"I put off making decisions more than I used to."},{"score":2,"ar":"أجد صعوبة أكبر في اتخاذ القرارات مما كان عليه الحال سابقاً.","en":"I have greater difficulty in making decisions more than I used to."},{"score":3,"ar":"لم أعد قادراً على اتخاذ أي قرارات على الإطلاق.","en":"I can''t make decisions at all anymore."}]'::jsonb),

      (v_assessment_id, 14, 'البُعد المعرفي', 'Cognitive', 'تغير صورة الجسم', 'Body Image Distortion',
       'أشعر بالقلق من أنني أبدو أكبر سناً أو أقل جاذبية.', 'I am worried that I am looking old or unattractive.',
       '[{"score":0,"ar":"لا أشعر أن مظهري أسوأ مما كان عليه.","en":"I don''t feel that I look any worse than I used to."},{"score":1,"ar":"أشعر بالقلق من أنني أبدو أكبر سناً أو أقل جاذبية.","en":"I am worried that I am looking old or unattractive."},{"score":2,"ar":"أشعر أن هناك تغيرات دائمة في مظهري تجعلني أبدو غير جذاب.","en":"I feel there are permanent changes in my appearance that make me look unattractive."},{"score":3,"ar":"أعتقد أن مظهري قبيح ومنفر.","en":"I believe that I look ugly."}]'::jsonb),

      (v_assessment_id, 15, 'البُعد الوجداني', 'Affective', 'تراجع القدرة على العمل', 'Work Inhibition',
       'أحتاج إلى بذل جهد إضافي لكي أبدأ في عمل أي شيء.', 'It takes an extra effort to get started at doing something.',
       '[{"score":0,"ar":"أستطيع العمل بنفس الكفاءة التي تعودت عليها.","en":"I can work about as well as before."},{"score":1,"ar":"أحتاج إلى بذل جهد إضافي لكي أبدأ في عمل أي شيء.","en":"It takes an extra effort to get started at doing something."},{"score":2,"ar":"أضطر لدفع نفسي بشدة لكي أقوم بأي عمل.","en":"I have to push myself very hard to do anything."},{"score":3,"ar":"لا أستطيع القيام بأي عمل على الإطلاق.","en":"I can''t do any work at all."}]'::jsonb),

      (v_assessment_id, 16, 'البُعد البدني والجسمي', 'Somatic', 'اضطرابات النوم والأرق', 'Sleep Disturbance',
       'لا أنام جيداً كما تعودت.', 'I don''t sleep as well as I used to.',
       '[{"score":0,"ar":"أستطيع النوم جيداً كالمعتاد.","en":"I can sleep as well as usual."},{"score":1,"ar":"لا أنام جيداً كما تعودت.","en":"I don''t sleep as well as I used to."},{"score":2,"ar":"أستيقظ مبكراً بساعة أو ساعتين عن المعتاد وأجد صعوبة في العودة للنوم.","en":"I wake up 1-2 hours earlier than usual and find it hard to get back to sleep."},{"score":3,"ar":"أستيقظ مبكراً بعدة ساعات عن المعتاد ولا أستطيع العودة للنوم مرة أخرى.","en":"I wake up several hours earlier than I used to and cannot get back to sleep."}]'::jsonb),

      (v_assessment_id, 17, 'البُعد البدني والجسمي', 'Somatic', 'التعب والإرهاق البدني', 'Fatigability',
       'أتعب بسهولة أكبر مما تعودت عليه.', 'I get tired more easily than I used to.',
       '[{"score":0,"ar":"لا أشعر بالتعب أكثر من المعتاد.","en":"I don''t get more tired than usual."},{"score":1,"ar":"أتعب بسهولة أكبر مما تعودت عليه.","en":"I get tired more easily than I used to."},{"score":2,"ar":"أتعب من القيام بأي شيء تقريباً.","en":"I get tired from doing almost anything."},{"score":3,"ar":"أشعر بالتعب الشديد لدرجة لا أستطيع معها عمل أي شيء.","en":"I am too tired to do anything."}]'::jsonb),

      (v_assessment_id, 18, 'البُعد البدني والجسمي', 'Somatic', 'فقدان الشهية للطعام', 'Loss of Appetite',
       'شهيتي للطعام ليست جيدة كما كانت.', 'My appetite is not as good as it used to be.',
       '[{"score":0,"ar":"شهيتي للطعام ليست أسوأ من المعتاد.","en":"My appetite is no worse than usual."},{"score":1,"ar":"شهيتي للطعام ليست جيدة كما كانت.","en":"My appetite is not as good as it used to be."},{"score":2,"ar":"شهيتي للطعام أسوأ بكثير الآن.","en":"My appetite is much worse now."},{"score":3,"ar":"ليست لدي شهية للطعام على الإطلاق.","en":"I have no appetite at all anymore."}]'::jsonb),

      (v_assessment_id, 19, 'البُعد البدني والجسمي', 'Somatic', 'فقدان الوزن', 'Weight Loss',
       'فقدت أكثر من كيلوجرامين (2 كجم) من وزني.', 'I have lost more than five pounds (2 kg).',
       '[{"score":0,"ar":"لم أفقد الكثير من وزني مؤخراً (أو وزني ثابت).","en":"I haven''t lost much weight, if any, lately."},{"score":1,"ar":"فقدت أكثر من كيلوجرامين (2 كجم) من وزني.","en":"I have lost more than five pounds (2 kg)."},{"score":2,"ar":"فقدت أكثر من أربعة كيلوجرامات (4 كجم) من وزني.","en":"I have lost more than ten pounds (4 kg)."},{"score":3,"ar":"فقدت أكثر من ستة كيلوجرامات (6 كجم) من وزني.","en":"I have lost more than fifteen pounds (6 kg)."} ]'::jsonb),

      (v_assessment_id, 20, 'البُعد البدني والجسمي', 'Somatic', 'الانشغال الصحي والقلق الجسدي', 'Somatic Preoccupation',
       'أشعر بالقلق بسبب مشكلات جسدية مثل الآلام أو اضطراب المعدة أو الإمساك.', 'I am worried about physical problems like aches, pains, upset stomach, or constipation.',
       '[{"score":0,"ar":"لست قلقاً على صحتي أكثر من المعتاد.","en":"I am no more worried about my health than usual."},{"score":1,"ar":"أشعر بالقلق بسبب مشكلات جسدية مثل الآلام أو اضطراب المعدة أو الإمساك.","en":"I am worried about physical problems like aches, pains, upset stomach, or constipation."},{"score":2,"ar":"أشعر بقلق بالغ بشأن مشكلاتي الصحية ومن الصعب أن أفكر في أي شيء آخر.","en":"I am very worried about physical problems and it''s hard to think of much else."},{"score":3,"ar":"أشعر بقلق شديد للغاية على صحتي لدرجة لا أستطيع التفكير في أي شيء آخر.","en":"I am so worried about my physical problems that I cannot think of anything else."}]'::jsonb),

      (v_assessment_id, 21, 'البُعد البدني والجسمي', 'Somatic', 'فقدان الاهتمام الجنسي', 'Loss of Libido',
       'أصبحت أقل اهتماماً بالجنس مما تعودت عليه.', 'I am less interested in sex than I used to be.',
       '[{"score":0,"ar":"لم ألاحظ أي تغير حديث في اهتمامي الجنسي.","en":"I have not noticed any recent change in my interest in sex."},{"score":1,"ar":"أصبحت أقل اهتماماً بالجنس مما تعودت عليه.","en":"I am less interested in sex than I used to be."},{"score":2,"ar":"أصبح اهتمامي بالجنس أقل بكثير الآن.","en":"I have almost no interest in sex."},{"score":3,"ar":"فقدت اهتمامي بالجنس تماماً.","en":"I have lost interest in sex completely."}]'::jsonb);
  end if;
end $$;
