import os, sys, easyocr

base = os.path.dirname(os.path.abspath(__file__))
pages = os.path.join(base, '_pages_all')
out = os.path.join(base, '_ocr_all')
os.makedirs(out, exist_ok=True)

reader = easyocr.Reader(['ar', 'en'], gpu=False, verbose=False)
files = sorted(f for f in os.listdir(pages) if f.endswith('.png'))
start = int(sys.argv[1]) if len(sys.argv) > 1 else 0
end = int(sys.argv[2]) if len(sys.argv) > 2 else len(files)

for f in files[start:end]:
    dest = os.path.join(out, os.path.splitext(f)[0] + '.txt')
    if os.path.exists(dest):
        continue
    text = '\n'.join(reader.readtext(os.path.join(pages, f), detail=0, paragraph=True))
    with open(dest, 'w', encoding='utf-8') as fh:
        fh.write(text)
    print(f, len(text), flush=True)
