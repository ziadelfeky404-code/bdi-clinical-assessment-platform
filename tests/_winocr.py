import os, sys
from winrt.windows.globalization import Language
from winrt.windows.media.ocr import OcrEngine
from winrt.windows.storage import StorageFile, FileAccessMode
from winrt.windows.graphics.imaging import BitmapDecoder

base = os.path.dirname(os.path.abspath(__file__))
pages = os.path.join(base, '_pages_all')
out = os.path.join(base, '_ocr_fast')
os.makedirs(out, exist_ok=True)

engine = OcrEngine.try_create_from_language(Language('ar-SA'))
if engine is None:
    raise RuntimeError('Arabic OCR engine unavailable')

targets = sys.argv[1:]
files = [os.path.join(pages, t) for t in targets] if targets else [
    os.path.join(pages, f) for f in sorted(os.listdir(pages)) if f.endswith('.png')
]

for path in files:
    name = os.path.basename(path)
    dest = os.path.join(out, os.path.splitext(name)[0] + '.txt')
    if os.path.exists(dest) and os.path.getsize(dest) > 3:
        continue
    try:
        storage = StorageFile.get_file_from_path_async(path).get()
        stream = storage.open_async(FileAccessMode.READ).get()
        decoder = BitmapDecoder.create_async(stream).get()
        bitmap = decoder.get_software_bitmap_async().get()
        result = engine.recognize_async(bitmap).get()
        text = result.text
        with open(dest, 'w', encoding='utf-8') as f:
            f.write(text)
        print(f'{name}: {len(text)} chars', flush=True)
    except Exception as e:
        print(f'{name}: ERROR {e}', flush=True)
    finally:
        try:
            stream.close()
        except Exception:
            pass
