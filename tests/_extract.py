import os, sys, fitz, json

base = os.path.dirname(os.path.abspath(__file__))
out = os.path.join(base, "_extracted")
os.makedirs(out, exist_ok=True)

for name in os.listdir(base):
    if not name.lower().endswith('.pdf'):
        continue
    path = os.path.join(base, name)
    doc = fitz.open(path)
    stem = os.path.splitext(name)[0]
    stem = ''.join(c if c.isalnum() or c in '-_' else '_' for c in stem)
    folder = os.path.join(out, stem)
    os.makedirs(folder, exist_ok=True)
    pages = []
    for i, page in enumerate(doc):
        text = page.get_text('text')
        pages.append({'page': i+1, 'text': text})
        images = page.get_images(full=True)
        for j, img in enumerate(images):
            xref = img[0]
            try:
                data = doc.extract_image(xref)
                ext = data.get('ext', 'png')
                with open(os.path.join(folder, f'p{i+1}_img{j+1}.{ext}'), 'wb') as f:
                    f.write(data['image'])
            except Exception as e:
                pass
    with open(os.path.join(folder, 'text.json'), 'w', encoding='utf-8') as f:
        json.dump(pages, f, ensure_ascii=False, indent=2)
    print(f'{name}: pages={len(doc)}, chars={sum(len(p["text"]) for p in pages)}')
