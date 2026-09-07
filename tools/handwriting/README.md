# Handwriting sample sheet

Renders text in a real person's handwriting, from one sheet of captured letters.

The app has its own capture screen (`Menu → Your handwriting`) which stores glyphs on the
iPad. This is the paper route: fill in a sheet, photograph it, and compose text on the Mac.

```bash
python3 make_sheet.py sheet.png sheet.pdf     # the blank sheet: 76 labelled cells
python3 extract.py photo.jpg glyphs/          # photo -> labelled glyph library
python3 render.py glyphs/ "some text" out.png 900
```

## How it holds together

Every character sits in its own labelled cell, so a glyph is identified by **where** it is
rather than by guessing where one letter stops and the next begins. Segmenting free
handwriting splits `i`, `j` and `t` in the wrong places; this cannot.

Guides and labels print in light blue. In a photograph's blue channel they read as white,
so thresholding that channel leaves only the pen behind — no need to erase the ruling.

Four registration marks, three large and one small, give both a perspective correction and
an unambiguous orientation, so a hand-held photo works and the sheet can be the wrong way
up. Extraction then removes faint ringing around strokes (`_hysteresis`) and detached
flecks (`_drop_specks`), which otherwise inflate a glyph's bounding box and open a visible
gap in the composed line.

Because every cell carries the same printed guides, relative letter sizes come out right
for free: an `o` stays smaller than an `l` without measuring anything.

## Checking a change

`selftest.py` fills a sheet with a handwriting font, degrades it into a simulated
photograph — perspective, uneven light, blur, noise, JPEG — at all four orientations, and
checks the extracted glyph metrics against the clean extraction.
