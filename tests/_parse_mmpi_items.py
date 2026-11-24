import os, re, json

base = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(base, '_ocr_rtl')
out = os.path.join(base, '_mmpi_items.json')

ar2en = str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789')
items = {}

for p in range(1, 18):
    path = os.path.join(src, f'اختبار_MMPI_1_-1_p{p:02d}.txt')
    if not os.path.exists(path):
        continue
    text = open(path, encoding='utf-8').read().replace('\n', ' ')
    text = text.translate(ar2en)
    # Split on item numbers like "123 - " or "123-".
    parts = re.split(r'(?<!\d)(\d{1,3})\s*-\s*', text)
    for i in range(1, len(parts), 2):
        n = int(parts[i])
        body = parts[i+1].strip() if i+1 < len(parts) else ''
        if 1 <= n <= 566 and len(body) > 3:
            body = re.sub(r'\s+', ' ', body)
            if n not in items or len(body) > len(items[n]):
                items[n] = body

with open(out, 'w', encoding='utf-8') as f:
    json.dump(items, f, ensure_ascii=False, indent=2)

print('extracted', len(items), 'of 566')
print('missing sample', [n for n in range(1, 40) if n not in items])
