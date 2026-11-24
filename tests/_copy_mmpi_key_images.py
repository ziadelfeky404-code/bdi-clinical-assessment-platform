import os, shutil

base = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(base, '_extracted', 'تصحيح_mmpi')
dst = os.path.join(base, '_pages_all')
os.makedirs(dst, exist_ok=True)

for p in range(1, 19):
    found = [f for f in os.listdir(src) if f.startswith(f'p{p}_img2.')]
    if found:
        shutil.copy2(os.path.join(src, found[0]), os.path.join(dst, f'mmpikey_p{p:02d}.jpeg'))
        print(p)
