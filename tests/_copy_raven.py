import os, shutil

base = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(base, '_extracted', 'إختبار_المصفوفات_المتتابعه_لرافن_عملى')
dst = os.path.join(os.path.dirname(base), 'assets', 'raven')
os.makedirs(dst, exist_ok=True)

sets = [('A', 2), ('B', 14), ('C', 26), ('D', 38), ('E', 50)]
for letter, start in sets:
    for n in range(1, 13):
        page = start + n - 1
        found = [f for f in os.listdir(src) if f.startswith(f'p{page}_img1.')]
        if not found:
            print('missing', page)
            continue
        ext = os.path.splitext(found[0])[1]
        target = os.path.join(dst, f'{letter}{n:02d}{ext}')
        shutil.copy2(os.path.join(src, found[0]), target)
        print(os.path.basename(target))
