"""Geometry of the handwriting capture sheet, shared by the generator and the extractor.

One character per labelled cell, so every glyph is identified by position rather than by
guessing where one letter ends and the next begins. Guides are printed in light blue: the
blue channel of a photograph renders them white, so thresholding that channel leaves only
dark ink behind.
"""

ALPHABET = list(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    ".,'?!:;-()/&+="
)

DPI = 300
PAGE_W, PAGE_H = 2480, 3508          # A4 at 300 dpi
MARGIN = 150

# Registration marks: three large squares and one small, so orientation is unambiguous.
MARK_BIG = 56
MARK_SMALL = 30
MARK_INSET = 60

GRID_TOP = 560
GRID_BOTTOM = PAGE_H - 170
COLS, ROWS = 6, 13
GRID_LEFT = MARGIN
GRID_RIGHT = PAGE_W - MARGIN

GUIDE = (140, 200, 242)              # light blue: blue channel 242, invisible to the extractor
GUIDE_TEXT = (95, 165, 220)

# Fractions of cell height for the writing guides.
ASCENDER = 0.22
XHEIGHT = 0.44
BASELINE = 0.72
DESCENDER = 0.92


def cell_size():
    w = (GRID_RIGHT - GRID_LEFT) / COLS
    h = (GRID_BOTTOM - GRID_TOP) / ROWS
    return w, h


def cell_box(index):
    """Pixel box (x0, y0, x1, y1) of the cell holding ALPHABET[index]."""
    w, h = cell_size()
    col, row = index % COLS, index // COLS
    x0 = GRID_LEFT + col * w
    y0 = GRID_TOP + row * h
    return (x0, y0, x0 + w, y0 + h)


def mark_centres():
    """Registration mark centres, clockwise from top-left, with their sizes."""
    return [
        (MARK_INSET + MARK_BIG / 2, MARK_INSET + MARK_BIG / 2, MARK_BIG),
        (PAGE_W - MARK_INSET - MARK_BIG / 2, MARK_INSET + MARK_BIG / 2, MARK_BIG),
        (PAGE_W - MARK_INSET - MARK_SMALL / 2, PAGE_H - MARK_INSET - MARK_SMALL / 2, MARK_SMALL),
        (MARK_INSET + MARK_BIG / 2, PAGE_H - MARK_INSET - MARK_BIG / 2, MARK_BIG),
    ]
