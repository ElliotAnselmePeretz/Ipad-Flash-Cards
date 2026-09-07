"""Turn a filled-in capture sheet into a library of labelled glyphs.

The sheet's registration marks give a perspective correction, so a hand-held photograph
works as well as a clean export. Ink is found in the blue channel, where the light blue
guides read as white and only the pen survives.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sheet as S


def _page_component(rgb, scale_w=900):
    """The page as a boolean mask, grown from the centre so a dark desk is left out."""
    small = rgb.resize((scale_w, int(rgb.height * scale_w / rgb.width)), Image.BILINEAR)
    a = np.asarray(small).astype(np.int16)
    bright = a.min(axis=2) > 110

    seen = np.zeros_like(bright)
    h, w = bright.shape
    band = slice(h // 2 - 8, h // 2 + 8)
    seen[band, :] = bright[band, :]
    while True:
        grown = seen.copy()
        grown[1:, :] |= seen[:-1, :]
        grown[:-1, :] |= seen[1:, :]
        grown[:, 1:] |= seen[:, :-1]
        grown[:, :-1] |= seen[:, 1:]
        grown &= bright
        if grown.sum() == seen.sum():
            break
        seen = grown
    return seen, rgb.width / scale_w


def _page_quad(rgb):
    """The four page corners, clockwise from top-left, found as extremes of x+y and x-y.

    Ink and the registration marks are holes inside the page, so they never sit at an
    extreme; only the paper's own outline does.
    """
    mask, k = _page_component(rgb)
    ys, xs = np.nonzero(mask)
    if len(xs) < 1000:
        return None
    s, d = xs + ys, xs - ys
    picks = [np.argmin(s), np.argmax(d), np.argmax(s), np.argmin(d)]
    return [(float(xs[i] * k), float(ys[i] * k)) for i in picks]


def _homography(target, source):
    """3x3 matrix taking target points to source points, as PIL's transform samples."""
    m, b = [], []
    for (tx, ty), (sx, sy) in zip(target, source):
        m.append([tx, ty, 1, 0, 0, 0, -sx * tx, -sx * ty])
        m.append([0, 0, 0, tx, ty, 1, -sy * tx, -sy * ty])
        b += [sx, sy]
    c = np.linalg.solve(np.array(m, float), np.array(b, float))
    return np.array([[c[0], c[1], c[2]], [c[3], c[4], c[5]], [c[6], c[7], 1.0]])


def _corner_blobs(page):
    """Dark blob centroid and area near each expected registration mark."""
    out = []
    for cx, cy, _ in S.mark_centres():
        r = 140
        # Clamped to the page: cropping past the edge would pad with black and swamp the blob.
        box = (max(0, int(cx - r)), max(0, int(cy - r)),
               min(page.width, int(cx + r)), min(page.height, int(cy + r)))
        patch = np.asarray(page.crop(box).convert("L")).astype(np.int16)
        dark = patch < max(70, int(np.percentile(patch, 90)) - 110)
        ys, xs = np.nonzero(dark)
        if len(xs) < 15:
            out.append(None)
            continue
        out.append((box[0] + xs.mean(), box[1] + ys.mean(), int(dark.sum())))
    return out


def _warp(rgb, matrix):
    coeffs = (matrix / matrix[2, 2]).flatten()[:8]
    return rgb.transform((S.PAGE_W, S.PAGE_H), Image.PERSPECTIVE, coeffs, Image.BICUBIC,
                         fillcolor=(255, 255, 255))


def deskew(rgb):
    """Warp a photograph of the sheet back onto the canonical page."""
    quad = _page_quad(rgb)
    if quad is None:
        return rgb.resize((S.PAGE_W, S.PAGE_H), Image.LANCZOS), False

    canonical = [(0, 0), (S.PAGE_W, 0), (S.PAGE_W, S.PAGE_H), (0, S.PAGE_H)]
    best = None
    for turn in range(4):
        order = quad[turn:] + quad[:turn]
        h1 = _homography(canonical, order)
        trial = _warp(rgb, h1)
        blobs = _corner_blobs(trial)
        if any(b is None for b in blobs):
            continue
        areas = [b[2] for b in blobs]
        # Three large marks and one small: the small one is the bottom-right corner.
        if areas.index(min(areas)) != 2:
            continue
        ratio = min(areas) / max(areas)
        if best is None or ratio < best[0]:
            best = (ratio, h1, trial, blobs)

    if best is None:
        return _warp(rgb, _homography(canonical, quad)), False

    _, h1, trial, blobs = best
    targets = [(c[0], c[1]) for c in S.mark_centres()]
    h2 = _homography(targets, [(b[0], b[1]) for b in blobs])
    return _warp(rgb, h1 @ h2), True


def ink_mask(page):
    """Ink as a 0-255 array: dark marks in the blue channel, with lighting flattened out."""
    blue = page.split()[2]
    background = blue.filter(ImageFilter.GaussianBlur(60))
    b = np.asarray(blue).astype(np.int16)
    bg = np.asarray(background).astype(np.int16)
    delta = np.clip(bg - b - 28, 0, 255)
    return (np.clip(delta * 3, 0, 255)).astype(np.uint8)


def _components(mask):
    """4-connected component labels, walking the ink pixels only."""
    labels = np.zeros(mask.shape, np.int32)
    parent = [0]

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    ys, xs = np.nonzero(mask)
    for y, x in zip(ys.tolist(), xs.tolist()):
        up = labels[y - 1, x] if y else 0
        left = labels[y, x - 1] if x else 0
        if up and left:
            a, b = find(up), find(left)
            parent[max(a, b)] = min(a, b)
            labels[y, x] = min(a, b)
        elif up or left:
            labels[y, x] = find(up or left)
        else:
            parent.append(len(parent))
            labels[y, x] = len(parent) - 1

    lookup = np.array([find(i) for i in range(len(parent))], np.int32)
    return lookup[labels]


def _drop_specks(mask):
    """Remove flecks far smaller than the real ink: photo noise and guide-line crumbs.

    Kept relative rather than absolute so a light pen is treated the same as a heavy one,
    with a floor so the dot of an 'i' always survives.
    """
    labels = _components(mask)
    areas = np.bincount(labels.ravel())
    if len(areas) < 2:
        return mask
    areas[0] = 0
    floor = max(40, 0.03 * areas.max())
    keep = np.zeros(len(areas), bool)
    keep[areas >= floor] = True
    keep[0] = False
    return keep[labels]


def _hysteresis(cell, strong_level=170, weak_level=55):
    """Keep faint pixels only where they join confident ink.

    A photograph rings faintly around every dark stroke, and some of that ringing lands on
    the printed guide lines. Growing outwards from confident ink keeps soft stroke edges
    while leaving those detached smudges behind.
    """
    weak = cell > weak_level
    seen = cell > strong_level
    if not seen.any():
        return seen
    while True:
        grown = seen.copy()
        grown[1:, :] |= seen[:-1, :]
        grown[:-1, :] |= seen[1:, :]
        grown[:, 1:] |= seen[:, :-1]
        grown[:, :-1] |= seen[:, 1:]
        grown &= weak
        if grown.sum() == seen.sum():
            return seen
        seen = grown


def extract(image_path, out_dir):
    rgb = Image.open(image_path).convert("RGB")
    page, registered = deskew(rgb)
    mask = ink_mask(page)

    os.makedirs(out_dir, exist_ok=True)
    page.save(os.path.join(out_dir, "_page.png"))

    w, h = S.cell_size()
    unit = (S.BASELINE - S.XHEIGHT) * h          # baseline to x-height: the size reference
    glyphs, missing = {}, []

    for i, ch in enumerate(S.ALPHABET):
        x0, y0, x1, y1 = S.cell_box(i)
        # Keep clear of the printed border and the character label.
        cx0, cy0 = int(x0 + 12), int(y0 + 8)
        cx1, cy1 = int(x1 - 12), int(y1 - 8)
        cell = mask[cy0:cy1, cx0:cx1].copy()
        cell[: int(0.20 * h), : 90] = 0           # the label's corner, in case of bleed-through

        if (cell > 170).sum() < 40:
            missing.append(ch)
            continue
        keep = _drop_specks(_hysteresis(cell))
        if not keep.any():
            missing.append(ch)
            continue
        cell = np.where(keep, cell, 0).astype(np.uint8)
        ys, xs = np.nonzero(keep)
        pad = 6
        gx0, gx1 = max(0, xs.min() - pad), min(cell.shape[1], xs.max() + 1 + pad)
        gy0, gy1 = max(0, ys.min() - pad), min(cell.shape[0], ys.max() + 1 + pad)
        glyph = cell[gy0:gy1, gx0:gx1]

        name = f"{i:02d}_{ord(ch):04x}.png"
        Image.fromarray(glyph, "L").save(os.path.join(out_dir, name))

        baseline_in_cell = S.BASELINE * h - (cy0 - y0)
        glyphs[ch] = {
            "file": name,
            "width": int(gx1 - gx0),
            "height": int(gy1 - gy0),
            # Where the glyph's top sits relative to the writing line, in units.
            "top_over_baseline": (gy0 - baseline_in_cell) / unit,
            "unit": 1.0,
        }

    meta = {
        "unit_px": unit,
        "registered": registered,
        "glyphs": glyphs,
        "missing": missing,
    }
    with open(os.path.join(out_dir, "glyphs.json"), "w") as f:
        json.dump(meta, f, indent=1)

    print(f"registered={registered} captured={len(glyphs)}/{len(S.ALPHABET)}")
    if missing:
        print("missing: " + " ".join(missing))
    return meta


if __name__ == "__main__":
    extract(sys.argv[1], sys.argv[2])
