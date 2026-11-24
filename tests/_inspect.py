import os, fitz

base = os.path.dirname(os.path.abspath(__file__))
for name in sorted(os.listdir(base)):
    if not name.lower().endswith('.pdf'):
        continue
    doc = fitz.open(os.path.join(base, name))
    print('\n', name, 'pages', len(doc))
    for i in [0, 1, 2, 3, 10, 20, len(doc)-1]:
        if i >= len(doc):
            continue
        p = doc[i]
        imgs = p.get_images(full=True)
        print(f'  p{i+1}: text={len(p.get_text("text"))} images={len(imgs)} sizes={[ (im[2], im[3]) for im in imgs[:6] ]}')
