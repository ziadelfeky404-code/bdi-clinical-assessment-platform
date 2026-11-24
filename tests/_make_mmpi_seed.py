import json, os

base = os.path.dirname(os.path.abspath(__file__))
source = os.path.join(base, '_mmpi_selftestatlas.json')
out = os.path.join(base, '..', 'supabase', 'seed_mmpi.sql')

with open(source, encoding='utf-8') as f:
    bank = json.load(f)
questions = bank['questions'][1:]
assert len(questions) == 566, len(questions)

PRIMARY = {
    'L': ('L', 'الكذب', 'Lie'),
    'F': ('F', 'التزييف', 'Validity'),
    'K': ('K', 'التصحيح', 'Correction'),
    'Hs': ('Hs', 'توهم المرض', 'Hypochondriasis'),
    'D': ('D', 'الاكتئاب', 'Depression'),
    'Hy': ('Hy', 'الهستيريا', 'Hysteria'),
    'Pd': ('Pd', 'الانحراف السيكوباثي', 'Psychopathic deviate'),
    'Mf': ('Mf', 'الذكورة والأنوثة', 'Masculinity-femininity'),
    'Pa': ('Pa', 'البارانويا', 'Paranoia'),
    'Pt': ('Pt', 'القلق النفسي', 'Psychasthenia'),
    'Sc': ('Sc', 'الفصام', 'Schizophrenia'),
    'Ma': ('Ma', 'الهوس الخفيف', 'Hypomania'),
    'Si': ('Si', 'الانطواء الاجتماعي', 'Social introversion'),
    'Q': ('Q', 'غير قابل للإجابة', 'Cannot answer'),
}
EXTRA = {
    'Es': ('Es', 'تقدير الذات', 'Ego strength'),
    'Cn': ('Cn', 'النزاهة', 'Canonical'),
    'Dy': ('Dy', 'الاكتئاب الديناميكي', 'Dynamic depression'),
    'St': ('St', 'القلق البدني', 'Somatic tension'),
    'Re': ('Re', 'الانفعالية', 'Responsiveness'),
    'Do': ('Do', 'الانضباط', 'Dominance'),
    'MAS': ('MAS', 'مقياس القلق', 'Manifest anxiety'),
    'A': ('A', 'القلق العام', 'Anxiety'),
    'Pr': ('Pr', 'الميل للجريمة', 'Prison'),
}
LABELS = {**PRIMARY, **EXTRA}
TOKEN_ALIAS = {'Mf-m': 'Mf', 'Mf-f': 'Mf', 'MAS': 'MAS'}
IGNORE = {'0', 'R', 'GENDER1', 'GENDER2', ''}

NORM = {
    'M': {
        'L': (5.70, 2.52), 'F': (13.68, 6.86), 'K': (13.00, 4.66),
        'Hs': (15.42, 4.79), 'D': (26.16, 4.97), 'Hy': (22.07, 5.36),
        'Pd': (24.38, 4.27), 'Pa': (12.84, 3.92), 'Pt': (31.14, 5.71),
        'Sc': (36.47, 8.24), 'Ma': (21.22, 4.88), 'Si': (34.51, 6.88),
        'MAS': (18.86, 7.45), 'Dy': (26.09, 8.05), 'Do': (15.39, 3.12),
        'Re': (20.54, 4.13), 'Cn': (25.26, 3.76)
    },
    'F': {
        'L': (5.64, 2.48), 'F': (11.69, 5.02), 'K': (12.25, 4.26),
        'Hs': (16.35, 4.95), 'D': (28.40, 5.04), 'Hy': (22.82, 5.54),
        'Pd': (23.33, 4.44), 'Pa': (12.62, 3.93), 'Pt': (31.17, 5.86),
        'Sc': (34.89, 7.63), 'Ma': (19.18, 4.89), 'Si': (37.27, 6.71),
        'MAS': (20.43, 7.35), 'Dy': (29.12, 7.61), 'Do': (15.10, 2.76),
        'Re': (21.78, 3.13), 'Cn': (24.86, 3.70)
    }
}
MF_NORM = {'M': (27.56, 4.04), 'F': (31.83, 3.86)}
CORRECTIONS = {'Hs': ('K', 0.5), 'Pd': ('K', 0.4), 'Pt': ('K', 1.0), 'Sc': ('K', 1.0), 'Ma': ('K', 0.2)}


def tokens(raw):
    out = []
    for token in (raw or '').split('&'):
        token = token.strip()
        if token in IGNORE:
            continue
        token = TOKEN_ALIAS.get(token, token)
        if token in LABELS and token not in out:
            out.append(token)
    return out


def scale_meta():
    result = []
    for sex, label in [('M', 'ذكر'), ('F', 'أنثى')]:
        for key in ['L', 'F', 'K', 'Hs', 'D', 'Hy', 'Pd', 'Mf', 'Pa', 'Pt', 'Sc', 'Ma', 'Si',
                    'Q', 'Es', 'Cn', 'Dy', 'St', 'Re', 'Do', 'MAS', 'A', 'Pr']:
            _, ar, en = LABELS[key]
            entry = {'key': key, 'ar': ar, 'en': en, 'gender': sex}
            if key == 'Mf':
                entry['mean'], entry['sd'] = MF_NORM[sex]
            elif key in NORM[sex]:
                entry['mean'], entry['sd'] = NORM[sex][key]
            if key in CORRECTIONS:
                entry['correctionKey'], entry['correctionWeight'] = CORRECTIONS[key]
            result.append(entry)

    clinical = ['Hs', 'D', 'Hy', 'Pd', 'Pa', 'Pt', 'Sc', 'Ma']
    result.append({
        'key': 'clinicalMax', 'ar': 'أعلى ارتفاع سريري', 'en': 'Highest clinical elevation',
        'derive': 'maxT', 'sourceKeys': clinical, 'hidden': True
    })
    result.append({
        'key': 'clinicalMax', 'hidden': True, 'classify': True, 'elevate': 65,
        'severityKey': 'elevated', 'severityAr': 'ارتفاع سريري واضح',
        'severityEn': 'Clinically significant elevation',
        'severityDescAr': 'واحد أو أكثر من المقاييس السريرية الرئيسية فوق 65 درجة تائية وفق الجدول التقريبي المستخدم. يُقرأ في سياق مقاييس الصدق والأداء الإكلينيكي.',
        'severityDescEn': 'One or more main clinical scales exceed T=65 on the approximate table used; interpret with validity scales and clinical context.',
        'tone': 'amber'
    })
    result.append({
        'key': 'clinicalMax', 'hidden': True, 'classify': True, 'elevate': 75,
        'severityKey': 'marked', 'severityAr': 'ارتفاع سريري شديد',
        'severityEn': 'Marked clinical elevation',
        'severityDescAr': 'واحد أو أكثر من المقاييس السريرية الرئيسية عند 75 درجة تائية أو أكثر. يتطلب تفسيراً متخصصاً ومراجعة مقاييس الصدق.',
        'severityDescEn': 'One or more main clinical scales reach T=75 or above; specialist interpretation and validity review are required.',
        'tone': 'rose'
    })
    return result


def sqlish(value):
    return json.dumps(value, ensure_ascii=False).replace("'", "''")


items = []
for i, q in enumerate(questions, 1):
    scales = []
    for option_key, direction in [('A', 'yes'), ('B', 'no'), ('C', 'skip')]:
        for token in tokens(q.get('answer', {}).get(option_key, {}).get('score')):
            scales.append({'key': token, 'direction': direction})
    items.append({
        'position': i,
        'textAr': q['question'],
        'textEn': '',
        'scales': scales,
        'options': [
            {'score': 1, 'ar': 'صحيح', 'en': 'True', 'totalScore': 1},
            {'score': 0, 'ar': 'خطأ', 'en': 'False', 'totalScore': 0},
            {'score': 2, 'ar': 'لا أستطيع الإجابة', 'en': 'Cannot answer', 'totalScore': 0}
        ]
    })

cutoffs = [{
    'key': 'within', 'min': 0, 'max': 566, 'ar': 'ضمن المدى المعتاد',
    'en': 'Within expected range',
    'descAr': 'لم تتجاوز المقاييس السريرية الرئيسية العتبة المعتمدة في الجدول التقريبي. تُراجع الدرجات التفصيلية ومقاييس الصدق داخل التقرير.',
    'descEn': 'No main clinical scale exceeded the threshold on the approximate table. Review the detailed scales and validity indices in the report.',
    'tone': 'emerald'
}]

sql = """-- Seed: Minnesota Multiphasic Personality Inventory, 566-item Form R
-- Patient-facing copy is deliberately neutral. Scoring remains server-side.
-- Item wording source: SelfTestAtlas Arabic item bank (public, unofficial), version 139.
-- Key source: the same item bank's per-option scale tokens, so item numbers and keys align.
-- K-correction and approximate T norms: public 1982 Form R tables; report as provisional.
do $$
declare
  v_id uuid;
begin
  insert into public.assessments (
    slug, title_ar, title_en, patient_label_ar, patient_label_en, category, suite,
    description_ar, description_en, instructions_ar, instructions_en,
    version, active, sort_order, cutoffs, critical_rules, scale_meta
  ) values (
    'mmpi-566',
    'جرد مينيسوتا متعدد الأوجه للشخصية (566 مفردة)',
    'Minnesota Multiphasic Personality Inventory (Form R, 566 items)',
    'استبيان سمات الشخصية',
    'Personality inventory',
    'clinical', 'clinical',
    'استبيان طويل من 566 عبارة لتكوين صورة وصفية عن سمات الشخصية وطريقة الاستجابة. لا توجد إجابات صحيحة أو خاطئة.',
    'A 566-statement inventory for a descriptive picture of personality and response style. There are no right or wrong answers.',
    ' اقرأ كل عبارة واختر: صحيح، أو خطأ، أو لا أستطيع الإجابة. حاول أن تكون إجابتك الأولى هي الأقرب لشعورك المعتاد.',
    'For each statement choose True, False, or Cannot answer. Use your first reaction as the closest answer.',
    '1.0', true, 40,
    '%s'::jsonb,
    '[]'::jsonb,
    '%s'::jsonb
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

  insert into public.assessment_items (
    assessment_id, position, domain_ar, domain_en, title_ar, title_en,
    text_ar, text_en, options, scales
  )
  select
    v_id,
    (item ->> 'position')::integer,
    'عبارات الاستبيان', 'Inventory statements',
    'العبارة ' || (item ->> 'position'), 'Statement ' || (item ->> 'position'),
    item ->> 'textAr', item ->> 'textEn',
    item -> 'options', item -> 'scales'
  from jsonb_array_elements('%s'::jsonb) as item;
end $$;
""" % (sqlish(cutoffs), sqlish(scale_meta()), sqlish(items))

with open(out, 'w', encoding='utf-8') as f:
    f.write(sql)

print(out)
print('items', len(items), 'scales', len(scale_meta()), 'sql bytes', len(sql))
