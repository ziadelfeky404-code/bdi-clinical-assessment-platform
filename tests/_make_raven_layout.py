"""Generate layout metadata for the Raven drag-and-drop runner.

The figures are never redrawn: the browser crops the original booklet scans
with CSS background-position, so every shape and colour stays byte-identical.
"""
from pathlib import Path
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAVEN = ROOT / "assets" / "raven"


def smooth(values, window=31):
    return np.convolve(values, np.ones(window) / window, mode="same")


def content_span(darkness, low, high, width, min_frac, max_frac):
    band = darkness[int(low):int(high)]
    profile = smooth(band.sum(axis=0))
    if profile.max() <= 0:
        return int(width * min_frac), int(width * max_frac)
    first = int(np.where(profile > profile.max() * 0.10)[0][0])
    last = int(np.where(profile > profile.max() * 0.10)[0][-1]) + 1
    first = max(first, int(width * min_frac))
    last = min(last, int(width * max_frac))
    if last <= first:
        first, last = int(width * min_frac), int(width * max_frac)
    return first, last


def analyse(name):
    source = RAVEN / f"{name}.jpeg"
    image = Image.open(source).convert("RGB")
    rotated = image.width > image.height
    if rotated:
        image = image.rotate(90, expand=True)
    width, height = image.size
    dark = np.array(image.convert("L")) < 170

    # The matrix occupies the upper half; the answer figures sit below it.
    my0, my1 = int(height * 0.17), int(height * 0.58)
    mx0, mx1 = content_span(dark, my0, my1, width, 0.04, 0.88)

    cell_w = (mx1 - mx0) / 3
    cell_h = (my1 - my0) / 3
    densities = []
    for row in range(3):
        for col in range(3):
            y0 = int(my0 + row * cell_h)
            y1 = int(my0 + (row + 1) * cell_h)
            x0 = int(mx0 + col * cell_w)
            x1 = int(mx0 + (col + 1) * cell_w)
            densities.append(int(dark[y0:y1, x0:x1].sum()))
    row, col = divmod(int(np.argmin(densities)), 3)
    inset = 0.06
    missing = [
        round((mx0 + col * cell_w + cell_w * inset) / width, 5),
        round((my0 + row * cell_h + cell_h * inset) / height, 5),
        round(cell_w * (1 - 2 * inset) / width, 5),
        round(cell_h * (1 - 2 * inset) / height, 5),
    ]

    oy0, oy1 = int(height * 0.55), int(height * 0.89)
    ox0, ox1 = content_span(dark, oy0, oy1, width, 0.02, 0.92)
    columns = 3 if name[0] in "AB" else 4
    option_w = (ox1 - ox0) / columns
    option_h = (oy1 - oy0) / 2
    option_inset = 0.04
    options = []
    for index in range(columns * 2):
        r, c = divmod(index, columns)
        options.append([
            round((ox0 + c * option_w + option_w * option_inset) / width, 5),
            round((oy0 + r * option_h + option_h * option_inset) / height, 5),
            round(option_w * (1 - 2 * option_inset) / width, 5),
            round(option_h * (1 - 2 * option_inset) / height, 5),
        ])

    return {
        "imageUrl": f"assets/raven/{name}-rotated.jpeg" if rotated else f"assets/raven/{name}.jpeg",
        "missing": missing,
        "options": options,
    }


def main():
    if (RAVEN / "E12-rotated.jpeg").exists():
        pass
    else:
        Image.open(RAVEN / "E12.jpeg").convert("RGB").rotate(90, expand=True).save(
            RAVEN / "E12-rotated.jpeg", quality=95, subsampling=0
        )

    layout = {}
    for index in range(1, 13):
        for letter in "ABCDE":
            name = f"{letter}{index:02d}"
            layout[name] = analyse(name)

    (RAVEN / "raven_layout.json").write_text(
        json.dumps(layout, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Wrote layout for {len(layout)} matrices")


if __name__ == "__main__":
    main()
