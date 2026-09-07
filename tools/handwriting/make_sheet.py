"""Draw the capture sheet: 76 labelled cells to write one character in each."""
import sys
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from sheet import *  # noqa: F401,F403
import sheet as S

FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
FONT_BOLD = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def dashed(d, x0, y, x1, colour, width=2, on=14, off=14):
    x = x0
    while x < x1:
        d.line([(x, y), (min(x + on, x1), y)], fill=colour, width=width)
        x += on + off


def main(out_png, out_pdf):
    img = Image.new("RGB", (S.PAGE_W, S.PAGE_H), "white")
    d = ImageDraw.Draw(img)

    for cx, cy, size in S.mark_centres():
        d.rectangle([cx - size / 2, cy - size / 2, cx + size / 2, cy + size / 2], fill="black")

    title = ImageFont.truetype(FONT_BOLD, 62)
    body = ImageFont.truetype(FONT, 36)
    label_font = ImageFont.truetype(FONT_BOLD, 40)

    d.text((S.MARGIN, 200), "Handwriting sample", font=title, fill=S.GUIDE_TEXT)
    lines = [
        "Write each character once, in its own box, sitting on the solid line.",
        "Use a black or dark pen. The blue guides disappear automatically.",
        "Fill the box comfortably — roughly from the dotted line to the solid one for small letters.",
        "Then photograph the whole sheet, flat and square on, and send it back.",
    ]
    y = 290
    for line in lines:
        d.text((S.MARGIN, y), line, font=body, fill=S.GUIDE_TEXT)
        y += 52

    w, h = S.cell_size()
    for i, ch in enumerate(S.ALPHABET):
        x0, y0, x1, y1 = S.cell_box(i)
        d.rectangle([x0, y0, x1, y1], outline=S.GUIDE, width=2)

        inset = 24
        # The ascender guide starts past the label so the two do not run into each other.
        for frac, style, left in ((S.ASCENDER, "faint", x0 + 96), (S.XHEIGHT, "dashed", x0 + inset),
                                  (S.BASELINE, "solid", x0 + inset), (S.DESCENDER, "faint", x0 + inset)):
            yy = y0 + frac * h
            if style == "solid":
                d.line([(left, yy), (x1 - inset, yy)], fill=S.GUIDE, width=4)
            elif style == "dashed":
                dashed(d, left, yy, x1 - inset, S.GUIDE, width=2)
            else:
                dashed(d, left, yy, x1 - inset, S.GUIDE, width=2, on=4, off=22)

        shown = {" ": "space"}.get(ch, ch)
        d.text((x0 + 16, y0 + 10), shown, font=label_font, fill=S.GUIDE_TEXT)

    img.save(out_png, dpi=(S.DPI, S.DPI))
    img.save(out_pdf, "PDF", resolution=S.DPI)
    print(f"{out_png}\n{out_pdf}\n{len(S.ALPHABET)} cells")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
