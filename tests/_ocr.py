import os, sys, json, easyocr

base = os.path.dirname(os.path.abspath(__file__))
pages = os.path.join(base, '_pages')
out = os.path.join(base, '_ocr')
os.makedirs(out, exist_ok=True)

reader = easyocr.Reader(['ar', 'en'], gpu=False, verbose=False)

targets = sys.argv[1:]
files = [os.path.join(pages, t) for t in targets] if targets else [os.path.join(pages, f) for f in sorted(os.listdir(pages)) if f.endswith('.png')]

for f in files:
    if not os.path.exists(f):
        print('missing', f)
        continue
    result = reader.readtext(f, detail=0, paragraph=True)
    text = '\n'.join(result)
    dest = os.path.join(out, os.path.splitext(os.path.basename(f))[0] + '.txt')
    with open(dest, 'w', encoding='utf-8') as fh:
        fh.write(text)
    print(f'{os.path.basename(f)} -> {len(text)} chars')
