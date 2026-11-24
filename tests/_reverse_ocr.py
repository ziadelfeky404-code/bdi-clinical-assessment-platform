import os

base = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(base, '_ocr_fast')
out = os.path.join(base, '_ocr_rtl')
os.makedirs(out, exist_ok=True)

for name in os.listdir(src):
    if not name.endswith('.txt'):
        continue
    text = open(os.path.join(src, name), encoding='utf-8').read()
    lines = []
    for line in text.splitlines():
        words = line.split()
        lines.append(' '.join(reversed(words)) if words else '')
    with open(os.path.join(out, name), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print(name)
