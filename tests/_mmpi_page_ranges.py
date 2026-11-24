import os,re
base=os.path.dirname(os.path.abspath(__file__))
src=os.path.join(base,'_ocr_rtl')
ar2en=str.maketrans('٠١٢٣٤٥٦٧٨٩','0123456789')
for p in range(1,18):
    path=os.path.join(src,f'اختبار_MMPI_1_-1_p{p:02d}.txt')
    if not os.path.exists(path): continue
    text=open(path,encoding='utf-8').read().translate(ar2en)
    nums=[int(x) for x in re.findall(r'(?<!\d)(\d{1,3})\s*-\s*',text)]
    nums=[n for n in nums if 1<=n<=566]
    if nums: print(p, min(nums), max(nums), len(set(nums)))
