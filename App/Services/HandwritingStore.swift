import Foundation
import SwiftUI
import SwiftData
import PencilKit
import FlashcardsCore

/// Reads and writes the captured letter library, and composes text from it.
struct HandwritingStore {
    let context: ModelContext

    // MARK: - Reading

    func glyphs() -> [StoredGlyph] {
        (try? context.fetch(FetchDescriptor<StoredGlyph>())) ?? []
    }

    func samples() -> [Character: [StoredGlyph]] {
        Dictionary(grouping: glyphs().filter { !$0.character.isEmpty }) {
            Character($0.character)
        }
        .mapValues { $0.sorted { $0.sampleIndex < $1.sampleIndex } }
    }

    /// Letter sizes, with each one's position against the writing line resolved.
    ///
    /// Letters captured before the line was recorded only know their own shape, so where they
    /// meet the line is worked out from the character itself.
    func metrics() -> [Character: [GlyphMetrics]] {
        let library = samples()
        var heights: [Character: [CGFloat]] = [:]
        for (character, list) in library {
            heights[character] = list.map { CGFloat($0.height) }
        }
        let reference = GlyphRest.references(heights)

        return library.reduce(into: [:]) { result, entry in
            let (character, list) = entry
            result[character] = list.map { glyph in
                let descender = glyph.baselineRecorded
                    ? CGFloat(glyph.descender)
                    : GlyphRest.estimatedDescender(for: character, height: CGFloat(glyph.height),
                                                   xHeight: reference.xHeight,
                                                   ascenderHeight: reference.ascender)
                return GlyphMetrics(width: glyph.width, height: glyph.height, descender: descender)
            }
        }
    }

    /// Characters still to capture, in the order they should be asked for.
    func remaining() -> [Character] {
        let have = Set(samples().keys)
        return HandwritingAlphabet.characters.filter { !have.contains($0) }
    }

    var isReady: Bool { remaining().isEmpty }

    func capturedCount() -> Int { samples().keys.count }

    // MARK: - Writing

    func save(_ drawing: PKDrawing, for character: Character, baseline: CGFloat) {
        let bounds = drawing.bounds
        guard !bounds.isEmpty, !drawing.strokes.isEmpty else { return }

        let existing = samples()[character]?.count ?? 0
        let glyph = StoredGlyph(
            character: character,
            sampleIndex: existing,
            drawing: drawing.dataRepresentation(),
            width: bounds.width,
            height: bounds.height,
            descender: bounds.maxY - baseline,
            baselineRecorded: true
        )
        context.insert(glyph)
        try? context.save()
    }

    func deleteAll() {
        for glyph in glyphs() { context.delete(glyph) }
        try? context.save()
    }

    // MARK: - Composing

    struct Composition {
        var drawing: PKDrawing
        var missing: Set<Character>
    }

    /// Writes `text` out in the captured hand.
    ///
    /// Each placement is drawn by taking the stored strokes for that letter, moving them to
    /// the origin, then applying the scale, rotation and position the layout decided. The
    /// letters are the user's own ink, not an approximation of it.
    func compose(_ text: String, maxWidth: CGFloat, bodyHeight: CGFloat = 44) -> Composition {
        let library = samples()
        let layout = HandwritingLayout(bodyHeight: bodyHeight)
        let result = layout.layout(text, samples: metrics(), maxWidth: maxWidth)

        var strokes: [PKStroke] = []
        for placement in result.placements {
            guard let variants = library[placement.character],
                  placement.sampleIndex < variants.count,
                  let source = try? PKDrawing(data: variants[placement.sampleIndex].drawing)
            else { continue }

            let bounds = source.bounds
            guard !bounds.isEmpty else { continue }

            // Normalise to the origin, then place: without this every letter would carry
            // wherever it happened to be written on the capture canvas.
            var transform = CGAffineTransform.identity
                .translatedBy(x: placement.origin.x, y: placement.origin.y)
                .rotated(by: placement.rotation)
                .scaledBy(x: placement.scale, y: placement.scale)
                .translatedBy(x: -bounds.minX, y: -bounds.minY)

            let moved = source.transformed(using: transform)
            strokes.append(contentsOf: moved.strokes)
            _ = transform
        }

        return Composition(drawing: PKDrawing(strokes: strokes), missing: result.missing)
    }
}
