"""Compose text out of captured glyphs.

Letters sit on a shared baseline at their true relative sizes — the sheet's printed guides
mean an 'o' stays smaller than an 'l' without measuring anything. Each glyph is nudged in
size, angle and height so repeated letters never look stamped.
"""
import json
import os
import random
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


class Handwriting:
    def __init__(self, glyph_dir):
        self.dir = glyph_dir
        with open(os.path.join(glyph_dir, "glyphs.json")) as f:
            self.meta = json.load(f)
        self.unit_px = self.meta["unit_px"]
        self._cache = {}

    def has(self, ch):
        return ch in self.meta["glyphs"]

    def _image(self, ch):
        if ch not in self._cache:
            self._cache[ch] = Image.open(os.path.join(self.dir, self.meta["glyphs"][ch]["file"])).convert("L")
        return self._cache[ch]

    def missing_in(self, text):
        return sorted({c for c in text if not c.isspace() and not self.has(c)})

    def render(self, text, x_height=38, max_width=1000, line_gap=2.6,
               ink=(38, 34, 30), background=None, margin=24, seed=None):
        scale = x_height / self.unit_px
        space = 0.62 * x_height
        tracking = 0.10 * x_height
        rng = random.Random(seed if seed is not None else text)

        def advance(ch):
            g = self.meta["glyphs"][ch]
            return g["width"] * scale + tracking

        # Break into lines without splitting words.
        words, lines, current, width_so_far = text.split(), [], [], 0.0
        for word in words:
            drawn = [c for c in word if self.has(c)]
            w = sum(advance(c) for c in drawn)
            step = w if not current else w + space
            if current and width_so_far + step > max_width:
                lines.append(current)
                current, width_so_far = [word], w
            else:
                current.append(word)
                width_so_far += step
        if current:
            lines.append(current)

        line_height = line_gap * x_height
        # A generous canvas: ascenders and descenders live outside the x-height band.
        height = int(margin * 2 + line_height * len(lines) + x_height * 2)
        width = int(margin * 2 + max_width)
        canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))

        for row, line in enumerate(lines):
            pen = float(margin)
            baseline = margin + x_height * 1.4 + row * line_height
            for w_index, word in enumerate(line):
                if w_index:
                    pen += space * rng.uniform(0.88, 1.14)
                for ch in word:
                    if not self.has(ch):
                        continue
                    g = self.meta["glyphs"][ch]
                    s = scale * rng.uniform(0.96, 1.05)
                    gw, gh = max(1, int(g["width"] * s)), max(1, int(g["height"] * s))
                    stamp = self._image(ch).resize((gw, gh), Image.LANCZOS)
                    stamp = stamp.rotate(rng.uniform(-2.0, 2.0), Image.BICUBIC,
                                         expand=True, fillcolor=0)
                    top = baseline + g["top_over_baseline"] * x_height + rng.uniform(-0.05, 0.05) * x_height
                    tinted = Image.new("RGBA", stamp.size, ink + (0,))
                    tinted.putalpha(stamp)
                    canvas.alpha_composite(tinted, (int(pen), int(top)))
                    pen += g["width"] * s + tracking * rng.uniform(0.7, 1.4)

        canvas = canvas.crop(canvas.getbbox() or (0, 0, width, height))
        if background:
            paper = Image.new("RGBA", canvas.size, background)
            paper.alpha_composite(canvas)
            canvas = paper
        return canvas


if __name__ == "__main__":
    glyph_dir, text, out = sys.argv[1], sys.argv[2], sys.argv[3]
    width = int(sys.argv[4]) if len(sys.argv) > 4 else 1000
    hw = Handwriting(glyph_dir)
    missing = hw.missing_in(text)
    if missing:
        print("not captured, skipped: " + " ".join(missing))
    img = hw.render(text, max_width=width, background=(253, 250, 244, 255))
    img.save(out)
    print(f"{out} {img.size}")
