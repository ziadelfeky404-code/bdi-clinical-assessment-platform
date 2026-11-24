import os, fitz, sys

base = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(base, "_pages")
os.makedirs(out, exist_ok=True)

def render(pdf, pages, zoom=1.6):
    path = os.path.join(base, pdf)
    doc = fitz.open(path)
    stem = ''.join(c if c.isalnum() or c in '-_' else '_' for c in os.path.splitext(pdf)[0])
    for p in pages:
        if p > len(doc):
            continue
        pix = doc[p-1].get_pixmap(matrix=fitz.Matrix(zoom, zoom), alpha=False)
        dest = os.path.join(out, f'{stem}_p{p}.png')
        pix.save(dest)
        print(dest)

render('اختبار MMPI(1)-1.pdf', [1, 2, 3, 4, 5])
render('تصحيح mmpi.pdf', [1, 2, 3])
render('مقياس ييل براون للوسواس القهرى.pdf', [1, 2, 3])
render('إختبار_المصفوفات_المتتابعه_لرافن_عملى.pdf', [1, 2, 3])
render('قائمة واستخبار ايزنك  الصحيح.pdf', [1])
