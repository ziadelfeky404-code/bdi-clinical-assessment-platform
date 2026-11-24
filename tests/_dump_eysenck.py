import os, json

base = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(base, '_extracted', 'قائمة_واستخبار_ايزنك__الصحيح', 'text.json')
out = os.path.join(base, '_eysenck')
os.makedirs(out, exist_ok=True)
for page in json.load(open(p, encoding='utf-8')):
    with open(os.path.join(out, f'page{page["page"]}.txt'), 'w', encoding='utf-8') as f:
        f.write(page['text'])
    print(page['page'], len(page['text']))
