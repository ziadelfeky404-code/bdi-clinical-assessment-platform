"""Build MMPI subscales from tests/تصحيح mmpi.pdf.

Item keys and published norms are transcribed from the correction appendix
(Harris-Lingoes, Serkownek, Wiener and Little/Fisher subscales).  Numbers marked
in the appendix as belonging to Form ر are translated back to the original
item numbering used by the application before any key is stored.
"""

import json
from pathlib import Path

base = Path(__file__).resolve().parent
seed_path = base.parent / "supabase" / "seed_mmpi.sql"
seed = seed_path.read_text(encoding="utf-8")

meta_line = next(line for line in seed.splitlines() if line.strip().startswith("'[{\"key\":\"L\""))
meta_raw = meta_line.strip().removeprefix("'").split("'::jsonb")[0]
# Rebuild subscale entries from the transcription below so rerunning the
# generator stays deterministic even after the generated seed is committed.
scale_meta = [e for e in json.loads(meta_raw) if e.get("group") != "subscale"]
existing = {(e.get("key"), e.get("gender")) for e in scale_meta}

# Form ر image numbers -> numbers used by the application.  Only the three
# Pd substitutions are printed explicitly in the appendix (page 6).  Other
# appendix numbers are used as printed; two Si items are OCR digit errors that
# are corrected to their neighbouring Si items (109->111, 291->292).
FORM_R_PD = {387: 479, 394: 521, 406: 368}
OCR_SI_CORRECTIONS = {109: 111, 291: 292}


def original(items, parent):
    mapping = FORM_R_PD if parent == "Pd" else OCR_SI_CORRECTIONS if parent == "Si" else {}
    return sorted({mapping.get(i, i) for i in items})


def published_bands(label):
    return [
        {"min": 65, "max": None, "rangeLabel": "T ≥ 65",
         "ar": f"درجات {label} أعلى من المعتاد في المجموعة المرجعية. تُقرأ مع بقية المقاييس ومقاييس الصلاحية قبل أي استنتاج."},
        {"min": 50, "max": 64, "rangeLabel": "50–64",
         "ar": f"درجات {label} ضمن النطاق المعتاد للمجموعة المرجعية."},
        {"min": None, "max": 49, "rangeLabel": "T < 50",
         "ar": f"درجات {label} أقل من المعتاد في المجموعة المرجعية."},
    ]


def raw_only_bands(label):
    return [{
        "min": None, "max": None, "rangeLabel": "درجة خام",
        "ar": (f"درجة {label} هي عدد البنود المؤكدة من قائمة المقياس. المتوسطات والانحرافات المعيارية "
               "غير منشورة في ملحق التصحيح، لذلك لا تُحوَّل إلى درجة تائية وتُقرأ في سياق النتائج الأخرى."),
    }]


# key, parent, Arabic label, English label, overview, yes items, no items,
# norms {gender: (mean, sd)}.  Empty dict means unpublished norms.
SUBSCALES = [
    ("D1", "D", "الاكتئاب الذاتي", "Subjective depression",
     "الحزن والإحباط وتقدير الذات السلبي كما يظهر في الإجابات.",
     [32, 41, 43, 52, 67, 86, 104, 138, 142, 158, 159, 182, 189, 236, 259],
     [2, 8, 46, 57, 88, 107, 122, 131, 152, 160, 191, 207, 208, 242, 272, 285, 296],
     {"M": (6.86, 3.37), "F": (8.55, 3.98)}),
    ("D2", "D", "التخلف النفسحركي", "Psychomotor retardation",
     "بطء الحركة والكلام وقلة المبادرة كما يذكرها المجيب.",
     [41, 52, 182, 259], [8, 30, 39, 57, 64, 89, 95, 145, 207, 208, 233],
     {"M": (5.29, 1.18), "F": (5.89, 1.95)}),
    ("D3", "D", "اعتلال الوظائف البدنية", "Physical malfunctioning",
     "الشكاوى البدنية وضعف الطاقة التي يذكرها المجيب.",
     [130, 189, 193, 288], [2, 18, 51, 153, 154, 155, 160],
     {"M": (3.09, 1.44), "F": (3.27, 1.57)}),
    ("D4", "D", "التبلد الذهني", "Mental dullness",
     "صعوبة التركيز وبطء التفكير كما تظهر في الإجابات.",
     [32, 41, 86, 104, 159, 182, 259, 290], [8, 9, 46, 88, 122, 178, 207],
     {"M": (1.92, 1.88), "F": (2.26, 2.11)}),
    ("D5", "D", "إطالة التفكير في المتاعب", "Brooding",
     "ميل المجيب إلى استحضار المتاعب والقلق المستمر.",
     [41, 67, 104, 138, 142, 158, 182, 236], [88, 107],
     {"M": (2.16, 0.83), "F": (3.01, 1.84)}),
    ("DO", "D", "الاكتئاب: البنود الواضحة", "Depression: obvious items",
     "البنود الواضحة من مقياس الاكتئاب حسب تصحيح واينر.",
     [3, 32, 41, 52, 67, 86, 104, 138, 142, 158, 159, 182, 189, 236, 259, 288, 290],
     [2, 8, 9, 18, 36, 46, 51, 57, 88, 95, 107, 122, 131, 152, 153, 154, 178, 207, 242, 270, 271, 272, 285],
     {"M": (7.72, 4.36), "F": (9.64, 4.92)}),
    ("DS", "D", "الاكتئاب: البنود الغامضة", "Depression: subtle items",
     "البنود الغامضة من مقياس الاكتئاب حسب تصحيح واينر.",
     [5, 130, 193], [30, 39, 58, 64, 80, 89, 98, 145, 155, 160, 191, 208, 233, 241, 248, 263, 296],
     {"M": (10.33, 2.78), "F": (11.03, 2.71)}),
    ("HY1", "Hy", "إنكار القلق الاجتماعي", "Denial of social anxiety",
     "نفي الشعور بالحرج أو التوتر في المواقف الاجتماعية.",
     [], [141, 172, 180, 201, 267, 292],
     {"M": (3.47, 1.81), "F": (3.29, 1.86)}),
    ("HY2", "Hy", "الحاجة إلى الحب", "Need for affection",
     "الحاجة إلى الود والدعم من الآخرين كما تظهر في الإجابات.",
     [253], [71, 89, 93, 109, 124, 136, 162, 234, 265, 289],
     {"M": (4.93, 2.45), "F": (4.68, 2.33)}),
    ("HY3", "Hy", "الإعياء والمرض", "Fatigue / illness",
     "أعراض جسدية وصحية يذكرها المجيب.",
     [32, 43, 76, 189, 238], [2, 3, 8, 9, 51, 107, 137, 153, 160, 163],
     {"M": (2.20, 2.33), "F": (2.69, 2.61)}),
    ("HY4", "Hy", "الشكاوى البدنية", "Somatic complaints",
     "اتساع نطاق الشكاوى الجسدية المذكورة.",
     [10, 23, 44, 47, 186], [7, 55, 103, 115, 174, 188, 190, 192, 230, 243, 274],
     {"M": (2.79, 2.47), "F": (4.24, 3.00)}),
    ("HY5", "Hy", "كبح العدوان", "Inhibition of aggression",
     "ميل المجيب إلى كبح العدوان أو التململ.",
     [], [6, 12, 30, 128, 129, 147, 170],
     {"M": (2.54, 1.38), "F": (3.04, 1.50)}),
    ("AD", "Hy", "الاعتراف بالأعراض", "Acknowledgment of symptoms",
     "اعتراف المجيب بالأعراض الجسدية والنفسية حسب تصحيح ليتل وفيشر.",
     [10, 23, 32, 43, 44, 47, 76, 114, 179, 186, 189, 238],
     [2, 3, 7, 8, 9, 51, 55, 103, 107, 128, 137, 153, 160, 163, 174, 175, 188, 190, 243],
     {"M": (4.82, 4.13), "F": (6.84, 4.91)}),
    ("HYO", "Hy", "الهستيريا: البنود الواضحة", "Hysteria: obvious items",
     "البنود الواضحة من مقياس الهستيريا حسب تصحيح واينر.",
     [10, 23, 32, 43, 44, 47, 76, 114, 179, 186, 189, 238],
     [2, 3, 7, 8, 9, 51, 53, 103, 107, 128, 137, 153, 163, 174, 175, 188, 192, 230, 243, 274],
     {"M": (4.58, 4.10), "F": (6.66, 4.77)}),
    ("HYS", "Hy", "الهستيريا: البنود الغامضة", "Hysteria: subtle items",
     "البنود الغامضة من مقياس الهستيريا حسب تصحيح واينر.",
     [253], [6, 12, 26, 30, 71, 89, 93, 109, 124, 129, 136, 141, 147, 160, 162, 170, 172, 180, 190, 201, 213, 234, 265, 267, 279, 289, 292],
     {"M": (12.75, 4.52), "F": (13.18, 4.20)}),
    ("DN", "Hy", "إنكار الأعراض", "Denial of symptoms",
     "نفي المجيب للأعراض الجسدية والنفسية حسب تصحيح ليتل وفيشر.",
     [253], [6, 12, 26, 30, 71, 89, 93, 109, 124, 129, 136, 141, 147, 162, 170, 172, 180, 201, 213, 234, 265, 267, 279, 289, 292],
     {"M": (11.94, 4.51), "F": (12.45, 4.26)}),
    ("PD1", "Pd", "الخلاف العائلي", "Family conflict",
     "احتكاكات أو توتر داخل الأسرة كما يذكرها المجيب.",
     [21, 42, 212, 216, 224, 245], [96, 137, 235, 237, 257],
     {"M": (1.80, 1.74), "F": (1.82, 1.72)}),
    ("PD2", "Pd", "صراع السلطة", "Authority conflict",
     "تعارض مع السلطة أو القواعد كما يظهر في الإجابات.",
     [38, 59, 118, 520], [37, 82, 141, 173, 289, 294, 429],
     {"M": (4.18, 1.63), "F": (3.39, 1.36)}),
    ("PD3", "Pd", "رباطة الجأش الاجتماعية", "Social poise",
     "الثقة والاتزان في المواقف الاجتماعية.",
     [64, 387, 394, 520], [82, 141, 171, 180, 201, 267, 304, 352],
     {"M": (7.66, 2.46), "F": (6.90, 2.64)}),
    ("PD4A", "Pd", "الاغتراب الاجتماعي", "Social alienation",
     "شعور المجيب بالانفصال عن الآخرين أو قلة الانتماء.",
     [16, 24, 35, 64, 67, 94, 110, 127, 146, 239, 244, 284, 305, 406, 520],
     [20, 141, 170], {"M": (5.32, 2.82), "F": (5.41, 2.75)}),
    ("PD4B", "Pd", "الاغتراب الذاتي", "Self alienation",
     "شعور المجيب بعدم وضوح الرؤية الذاتية أو بالاغتراب عن نفسه.",
     [32, 33, 61, 67, 76, 84, 94, 102, 106, 127, 146, 215, 406], [8, 107],
     {"M": (3.83, 2.59), "F": (3.66, 2.62)}),
    ("PDO", "Pd", "الانحراف: البنود الواضحة", "Psychopathic deviate: obvious items",
     "البنود الواضحة من مقياس الانحراف حسب تصحيح واينر.",
     [16, 24, 32, 33, 35, 38, 42, 61, 67, 84, 94, 106, 110, 118, 215, 216, 224, 244, 245, 284],
     [8, 20, 37, 91, 107, 137, 287, 294],
     {"M": (5.82, 3.55), "F": (5.30, 3.48)}),
    ("PDS", "Pd", "الانحراف: البنود الغامضة", "Psychopathic deviate: subtle items",
     "البنود الغامضة من مقياس الانحراف حسب تصحيح واينر.",
     [21, 102, 127, 239], [82, 96, 134, 141, 155, 170, 171, 173, 180, 183, 201, 231, 235, 237, 248, 267, 289, 296],
     {"M": (8.89, 2.52), "F": (8.68, 2.41)}),
    ("MF1", "Mf", "النرجسية والحساسية المفرطة", "Narcissism / hypersensitivity",
     "حساسية مفرطة للنقد وصورة ذاتية إيجابية أو متضخمة.",
     [25, 89, 117, 179, 214, 217, 226, 239, 278, 282, 297, 299],
     [79, 133, 187, 198, 262, 264], {}),
    ("MF2", "Mf", "الاهتمامات الأنثوية النمطية", "Feminine interests",
     "اهتمامات وتفضيلات مصنفة أنثوية في هذه النسخة التاريخية.",
     [4, 70, 74, 77, 78, 87, 92, 132, 140, 149, 200, 204, 261, 295], [], {}),
    ("MF3", "Mf", "إنكار الاهتمامات الذكرية النمطية", "Denial of masculine interests",
     "نفي اهتمامات وتفضيلات مصنفة ذكورية في هذه النسخة.",
     [], [1, 18, 144, 176, 219, 221, 223, 283], {}),
    ("MF4", "Mf", "السلبية الجنسية", "Aversion to heterosexual activity",
     "عدم الارتياح للنشاط الجنسي المغاير كما يذكره المجيب.",
     [69], [19, 80, 231], {}),
    ("MF5", "Mf", "ناقد ذاتي", "Self-critical",
     "ميل المجيب إلى تقديس الذات أو نقدها بصورة مبالغ فيها.",
     [204], [92, 99, 115, 249, 254, 264], {}),
    ("MF6", "Mf", "اعتزال اجتماعي", "Social withdrawal",
     "انسحاب المجيب من المواقف الاجتماعية.",
     [], [89, 99, 112, 116, 117, 126, 140, 203, 229], {}),
    ("PA1", "Pa", "أفكار الاضطهاد", "Persecutory ideas",
     "شك المجيب في نوايا الآخرين أو شعوره بالاستهداف.",
     [16, 24, 35, 110, 121, 123, 127, 151, 157, 202, 275, 284, 291, 293, 338, 364],
     [347], {"M": (1.91, 2.15), "F": (1.80, 2.05)}),
    ("PA2", "Pa", "حساسية زائدة", "Hypersensitivity",
     "حساسية المجيب لطريقة تعامل الآخرين معه.",
     [24, 158, 205, 299, 317, 341, 365], [111, 268],
     {"M": (2.12, 1.46)}),
    ("PA3", "Pa", "السذاجة", "Naivete",
     "بساطة أو سذاجة في فهم دوافع الآخرين.",
     [314], [93, 109, 117, 124, 313, 316, 319, 348],
     {"M": (3.79, 2.03), "F": (3.55, 1.97)}),
    ("PAO", "Pa", "البارانويا: البنود الواضحة", "Paranoia: obvious items",
     "البنود الواضحة من مقياس البارانويا حسب تصحيح واينر.",
     [16, 22, 24, 35, 110, 121, 123, 151, 158, 202, 275, 284, 291, 293, 305, 317, 326, 338, 341, 364],
     [281, 294, 347], {"M": (2.58, 2.27), "F": (2.87, 2.48)}),
    ("PAS", "Pa", "البارانويا: البنود الغامضة", "Paranoia: subtle items",
     "البنود الغامضة من مقياس البارانويا حسب تصحيح واينر.",
     [15, 127, 157, 299, 365], [93, 107, 109, 111, 117, 124, 268, 313, 316, 319, 327, 348],
     {"M": (6.00, 2.28), "F": (5.54, 2.13)}),
    ("SC1A", "Sc", "الاغتراب الاجتماعي", "Social alienation",
     "انفصال المجيب عن الآخرين وضعف المشاركة الاجتماعية.",
     [16, 21, 24, 35, 52, 121, 157, 212, 241, 282, 305, 312, 324, 325, 352, 364],
     [65, 220, 276, 306, 309], {"M": (3.48, 2.31), "F": (3.68, 2.43)}),
    ("SC1B", "Sc", "الاغتراب الانفعالي", "Emotional alienation",
     "صعوبة الشعور بالارتباط الوجداني أو فقدان الموضوع.",
     [76, 104, 202, 301, 339, 355, 360, 363], [8, 196, 322],
     {"M": (2.17, 1.08), "F": (2.04, 1.14)}),
    ("SC2A", "Sc", "نقص تحكم الأنا معرفياً", "Ego control: cognitive",
     "صعوبة ضبط الأفكار وتشتت الانتباه.",
     [32, 33, 159, 168, 182, 335, 345, 349, 356], [178],
     {"M": (1.43, 1.56), "F": (1.46, 1.58)}),
    ("SC2B", "Sc", "نقص تحكم الأنا نزوعياً", "Ego control: volitional",
     "صعوبة ضبط الدوافع والسلوك.",
     [32, 40, 41, 76, 104, 202, 259, 301, 335, 339, 356], [8, 196, 322],
     {"M": (1.59, 1.68), "F": (2.17, 1.98)}),
    ("SC2C", "Sc", "قصور الكف", "Ego control: inadequacy",
     "شعور المجيب بقصور قدرته على مواجهة المواقف.",
     [22, 97, 156, 194, 238, 266, 291, 303, 352, 354, 360], [],
     {"M": (1.44, 1.53)}),
    ("SC3", "Sc", "خبرات حسية خلطية", "Sensory experiences",
     "خبرات إدراكية أو حسية غير معتادة يذكرها المجيب.",
     [22, 33, 47, 156, 194, 210, 251, 273, 291, 332, 334, 341, 345, 350],
     [103, 119, 187, 192, 281, 330], {"M": (2.36, 2.37), "F": (2.72, 2.54)}),
    ("MA1", "Ma", "اللاأخلاقية", "Amorality",
     "تساهل المجيب مع القواعد الأخلاقية كما تظهر في الإجابات.",
     [11, 143, 250, 271, 277, 298], [], {"M": (1.70, 1.22), "F": (1.38, 1.17)}),
    ("MA2", "Ma", "الإسراع النفسي الحركي", "Psychomotor acceleration",
     "ارتفاع النشاط وسرعة الكلام والحركة.",
     [13, 97, 100, 134, 181, 228, 238, 266, 268], [111, 119],
     {"M": (3.67, 1.39), "F": (3.45, 1.57)}),
    ("MA3", "Ma", "رباطة الجأش", "Imperturbability",
     "هدوء ظاهري وعدم تأثر بالضغوط.",
     [167, 222, 240], [105, 148, 171, 180, 267],
     {"M": (3.43, 1.73), "F": (2.91, 1.66)}),
    ("MA4", "Ma", "تضخم الأنا", "Ego inflation",
     "مبالغة في تقدير الذات والقدرات.",
     [11, 59, 64, 73, 109, 157, 212, 232, 233], [],
     {"M": (2.63, 1.64), "F": (2.71, 1.66)}),
    ("MAO", "Ma", "الهوس: البنود الواضحة", "Hypomania: obvious items",
     "البنود الواضحة من مقياس الهوس الخفيف حسب تصحيح واينر.",
     [13, 22, 59, 73, 97, 100, 156, 157, 167, 194, 212, 226, 238, 250, 251, 263, 266, 277, 279, 298],
     [111, 119, 120], {"M": (5.83, 2.84)}),
    ("MAS", "Ma", "الهوس: البنود الغامضة", "Hypomania: subtle items",
     "البنود الغامضة من مقياس الهوس الخفيف حسب تصحيح واينر.",
     [11, 21, 64, 109, 127, 134, 143, 181, 222, 228, 232, 233, 240, 271],
     [101, 105, 148, 166, 171, 180, 267, 289],
     {"M": (9.30, 2.59), "F": (9.04, 2.55)}),
    ("SI1", "Si", "عدم الارتياح الشخصي", "Personal discomfort",
     "توتر المجيب داخل المواقف الاجتماعية.",
     [32, 67, 82, 138, 147, 171, 172, 180, 201, 236, 267, 278, 292, 304, 321, 336, 359, 369, 377, 381, 383, 388, 396],
     [57, 109, 353, 371], {}),
    ("SI2", "Si", "عدم الارتياح مع الآخرين", "Discomfort with others",
     "صعوبة التفاعل مع الآخرين والشعور بالحرج.",
     [372, 377, 385, 386, 390, 393], [357, 378, 379, 384, 387, 394, 395, 399], {}),
    ("SI3", "Si", "الرزانة والتصلب", "Rigidity",
     "تصلب في الآراء وصعوبة التكيف الاجتماعي.",
     [], [33, 91, 99, 143, 208, 229, 231, 254, 367, 370, 375, 376, 378, 379, 385, 393], {}),
    ("SI4", "Si", "الحساسية الزائدة", "Hypersensitivity",
     "حساسية المجيب لتقييم الآخرين له.",
     [25, 32, 126, 138, 236, 278, 291, 372, 390, 396], [], {}),
    ("SI5", "Si", "عدم الثقة", "Distrust",
     "شك المجيب في دوافع الآخرين.",
     [117, 124, 147, 278, 316, 359, 369, 373, 383, 389, 398], [399], {}),
    ("SI6", "Si", "الشواغل البدنية", "Physical concerns",
     "انشغال المجيب بالأعراض والمخاوف البدنية.",
     [33, 236, 332], [119, 193, 262, 281, 309, 378, 380], {}),
]

COMPOSITES = {
    "PD4": ["PD4A", "PD4B"],
    "SC1": ["SC1A", "SC1B"],
    "SC2": ["SC2A", "SC2B", "SC2C"],
}
COMPOSITE_NORMS = {
    "PD4": {"M": (7.50, 3.94), "F": (7.30, 3.98)},
    "SC1": {"M": (3.85, 3.19), "F": (4.16, 3.30)},
    "SC2": {"M": (4.35, 3.58), "F": (4.10, 2.75)},
}
COMPOSITE_LABELS = {
    "PD4": ("الاغتراب", "Alienation total", "محصلة الاغتراب الاجتماعي والذاتي."),
    "SC1": ("فقدان الموضوع", "Loss of object", "محصلة الاغتراب الاجتماعي والانفعالي."),
    "SC2": ("نقص تحكم الأنا", "Ego control total", "محصلة مؤشرات ضبط الأنا الفرعية."),
}
COMPOSITE_PARENTS = {"PD4": "Pd", "SC1": "Sc", "SC2": "Sc"}

added = 0
for key, parent, label, en, overview, yes, no, norms in SUBSCALES:
    yes_items, no_items = original(yes, parent), original(no, parent)
    for gender in ("M", "F"):
        if (key, gender) in existing:
            continue
        published = gender in norms
        mean, sd = norms.get(gender, (None, None))
        entry = {
            "key": key, "ar": label, "en": en, "gender": gender,
            "group": "subscale", "parent": parent,
            "diagnosisLabel": label, "overviewAr": overview,
            "hidden": True, "source": "tests/تصحيح mmpi.pdf",
            "normSource": "published" if published else "unpublished",
            "yes": yes_items, "no": no_items,
            "bands": published_bands(label) if published else raw_only_bands(label),
        }
        if published:
            entry["mean"], entry["sd"] = mean, sd
        scale_meta.append(entry)
        added += 1

# Composites are appended last so their components are already scored.
for key, components in COMPOSITES.items():
    label, en, overview = COMPOSITE_LABELS[key]
    for gender in ("M", "F"):
        if (key, gender) in existing:
            continue
        published = gender in COMPOSITE_NORMS[key]
        mean, sd = COMPOSITE_NORMS[key].get(gender, (None, None))
        entry = {
            "key": key, "ar": label, "en": en, "gender": gender,
            "group": "subscale", "parent": COMPOSITE_PARENTS[key],
            "diagnosisLabel": label, "overviewAr": overview,
            "hidden": True, "source": "tests/تصحيح mmpi.pdf",
            "normSource": "published" if published else "unpublished",
            "compositeKeys": components,
            "bands": published_bands(label) if published else raw_only_bands(label),
        }
        if published:
            entry["mean"], entry["sd"] = mean, sd
        scale_meta.append(entry)
        added += 1

meta_json = json.dumps(scale_meta, ensure_ascii=False, separators=(",", ":"))
(base / "_mmpi_subscales.json").write_text(
    json.dumps([e for e in scale_meta if e.get("group") == "subscale"],
               ensure_ascii=False, indent=2),
    encoding="utf-8",
)
(base / "_mmpi_subscale_update.sql").write_text(
    "update public.assessments\n"
    "set scale_meta = '" + meta_json.replace("'", "''") + "'::jsonb\n"
    "where slug = 'mmpi-566';\n",
    encoding="utf-8",
)
item_rows = []
for key, parent, label, en, overview, yes, no, norms in SUBSCALES:
    for position in original(yes, parent):
        item_rows.append((position, key, "yes"))
    for position in original(no, parent):
        item_rows.append((position, key, "no"))
item_rows = sorted(set(item_rows))
values_sql = ",\n".join(
    f"  ({position}, '{key}', '{direction}')" for position, key, direction in item_rows
)
(base / "_mmpi_subscale_item_updates.sql").write_text(
    "with subscale_items(position, key, direction) as (\n  values\n"
    + values_sql
    + "\n),\n"
    "grouped as (\n"
    "  select position,\n"
    "    jsonb_agg(jsonb_build_object('key', key, 'direction', direction) order by key) as additions\n"
    "  from subscale_items\n"
    "  group by position\n"
    ")\n"
    "update public.assessment_items ai\n"
    "set scales = coalesce(ai.scales, '[]'::jsonb) || coalesce((\n"
    "  select jsonb_agg(addition) from jsonb_array_elements(grouped.additions) as addition\n"
    "  where not exists (\n"
    "    select 1 from jsonb_array_elements(coalesce(ai.scales, '[]'::jsonb)) s\n"
    "    where s ->> 'key' = addition ->> 'key'\n"
    "  )\n"
    "), '[]'::jsonb)\n"
    "from grouped\n"
    "where ai.assessment_id = (select id from public.assessments where slug = 'mmpi-566')\n"
    "  and ai.position = grouped.position;\n",
    encoding="utf-8",
)

new_seed = seed.replace(meta_line, "    '" + meta_json.replace("'", "''") + "'::jsonb,", 1)
seed_path.write_text(new_seed, encoding="utf-8")

print("subscale definitions", len(SUBSCALES) + len(COMPOSITES))
print("meta entries added", added, "total", len(scale_meta))
print("item scale rows", len(item_rows))
print("pd mappings", len(FORM_R_PD), "si ocr corrections", len(OCR_SI_CORRECTIONS))
