import os, fitz

base = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(base, '_pages_all')
os.makedirs(out, exist_ok=True)
files = ['اختبار MMPI(1)-1.pdf', 'تصحيح mmpi.pdf', 'مقياس ييل براون للوسواس القهرى.pdf']

for pdf in files:
    doc = fitz.open(os.path.join(base, pdf))
    stem = ''.join(c if c.isalnum() or c in '-_' else '_' for c in os.path.splitext(pdf)[0])
    for i, page in enumerate(doc):
        pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), alpha=False)
        pix.save(os.path.join(out, f'{stem}_p{i+1:02d}.png'))
    print(pdf, len(doc))
