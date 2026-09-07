"""Exercise the whole pipeline without asking anyone to write 76 characters.

Fills a sheet with a handwriting font, degrades it into a plausible photograph, and checks
that the glyphs extracted from every orientation match the ones extracted from the clean
sheet. Counting captured glyphs is not enough on its own: an upside-down page still drops
ink into most cells, so the metrics are what actually prove the labels are right.
"""
import os
import random
import shutil
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet as S
import extract as E
import make_sheet

HAND_FONT = "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf"


def fill(src, out):
    img = Image.open(src).convert("RGB")
    d = ImageDraw.Draw(img)
    _, h = S.cell_size()
    font = ImageFont.truetype(HAND_FONT, 150)
    rng = random.Random(7)
    for i, ch in enumerate(S.ALPHABET):
        x0, y0, _, _ = S.cell_box(i)
        d.text((x0 + 120 + rng.uniform(-10, 10), y0 + S.BASELINE * h + rng.uniform(-4, 4)),
               ch, font=font, fill=(28, 26, 32), anchor="ls")
    img.save(out)


def photograph(src, out):
    """A sheet on a dark desk, off axis, unevenly lit, slightly soft, JPEG compressed."""
    page = Image.open(src).convert("RGB")
    W, H = 1700, 2300
    desk = (74, 68, 62)
    dst = [(190, 150), (1520, 260), (1430, 2150), (120, 2010)]
    corners = [(0, 0), (page.width, 0), (page.width, page.height), (0, page.height)]
    matrix = E._homography(dst, corners)
    coeffs = (matrix / matrix[2, 2]).flatten()[:8]

    warped = page.transform((W, H), Image.PERSPECTIVE, coeffs, Image.BICUBIC, fillcolor=desk)
    mask = Image.new("L", page.size, 255).transform((W, H), Image.PERSPECTIVE, coeffs,
                                                    Image.BICUBIC, fillcolor=0)
    scene = Image.new("RGB", (W, H), desk)
    scene.paste(warped, (0, 0), mask)

    a = np.asarray(scene).astype(np.float32)
    yy, xx = np.mgrid[0:H, 0:W]
    a *= (0.68 + 0.32 * np.exp(-(((xx - 400) / 1500.0) ** 2 + ((yy - 500) / 1900.0) ** 2)))[:, :, None]
    a += np.random.default_rng(3).normal(0, 3.5, a.shape)
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(0.7)).save(out, quality=72)


def main():
    work = tempfile.mkdtemp(prefix="handwriting-selftest-")
    try:
        blank = os.path.join(work, "sheet.png")
        make_sheet.main(blank, os.path.join(work, "sheet.pdf"))

        filled = os.path.join(work, "filled.png")
        fill(blank, filled)
        base = E.extract(filled, os.path.join(work, "clean"))
        failures = []
        if base["missing"]:
            failures.append(f"clean sheet missing {''.join(base['missing'])}")

        photo = os.path.join(work, "photo.jpg")
        photograph(filled, photo)
        for turn in (0, 90, 180, 270):
            path = photo
            if turn:
                path = os.path.join(work, f"photo_{turn}.jpg")
                Image.open(photo).rotate(turn, expand=True).save(path, quality=72)
            got = E.extract(path, os.path.join(work, f"turn{turn}"))
            if not got["registered"]:
                failures.append(f"{turn}deg: registration marks not found")
            if got["missing"]:
                failures.append(f"{turn}deg: missing {''.join(got['missing'])}")
                continue
            dw = max(abs(got["glyphs"][c]["width"] - base["glyphs"][c]["width"]) for c in base["glyphs"])
            dh = max(abs(got["glyphs"][c]["height"] - base["glyphs"][c]["height"]) for c in base["glyphs"])
            dt = max(abs(got["glyphs"][c]["top_over_baseline"] - base["glyphs"][c]["top_over_baseline"])
                     for c in base["glyphs"])
            print(f"  {turn:3d}deg  dw={dw} dh={dh} dtop={dt:.3f}")
            if dw > 8 or dh > 14 or dt > 0.3:
                failures.append(f"{turn}deg: glyphs drift from the clean sheet (dw={dw} dh={dh} dtop={dt:.2f})")

        if failures:
            print("FAILED")
            for f in failures:
                print("  - " + f)
            return 1
        print("OK: 76 glyphs recovered from every orientation")
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
