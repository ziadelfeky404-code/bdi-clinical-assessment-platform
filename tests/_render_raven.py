import os, fitz

base = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(base, '_pages_all')
os.makedirs(out, exist_ok=True)
doc = fitz.open(os.path.join(base, 'إختبار_المصفوفات_المتتابعه_لرافن_عملى.pdf'))
for i, page in enumerate(doc):
    pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), alpha=False)
    pix.save(os.path.join(out, f'raven_p{i+1:02d}.png'))
print('rendered', len(doc))
