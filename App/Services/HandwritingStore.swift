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
    /// The letters are the user's own ink, tidied: every stroke is redrawn with evenly
    /// spaced points, softened corners and one constant pen width, then moved to where the
    /// layout put it. Pressure and speed variation from the capture session would otherwise
    /// make the same letter look heavier in one word than the next.
    func compose(_ text: String, maxWidth: CGFloat, bodyHeight: CGFloat? = nil) -> Composition {
        let library = samples()
        let metrics = metrics()
        let bodyHeight = bodyHeight ?? Self.bodyHeight(fitting: text, in: maxWidth, metrics: metrics)
        let layout = HandwritingLayout.tidy(bodyHeight: bodyHeight)
        let result = layout.layout(text, samples: metrics, maxWidth: maxWidth)

        // PencilKit adapts black ink for dark mode on its own, so it is always stored light.
        let ink = PKInk(.pen, color: InkColor.ink.uiColor(for: .light))
        // About the proportion of the medium pen to the letters as they were written, so the
        // composed hand is as heavy as the live one; never so fine it fades on a card.
        // PencilKit's pen washes out below roughly two and a half points: the stroke stops
        // being ink and turns into a grey suggestion of it.
        let penWidth = max(2.4, bodyHeight * 0.11)

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
            let place = CGAffineTransform.identity
                .translatedBy(x: placement.origin.x, y: placement.origin.y)
                .rotated(by: placement.rotation)
                .scaledBy(x: placement.scale, y: placement.scale)
                .translatedBy(x: -bounds.minX, y: -bounds.minY)

            for stroke in source.strokes {
                if let tidy = Self.tidied(stroke, moving: stroke.transform.concatenating(place),
                                          width: penWidth, ink: ink) {
                    strokes.append(tidy)
                }
            }
        }

        return Composition(drawing: PKDrawing(strokes: strokes), missing: result.missing)
    }

    /// How large to write, given how much there is to say.
    ///
    /// A single word on a card can be big; a paragraph has to come down in size or it wraps
    /// every few words and runs off the bottom. This picks the largest lowercase height at
    /// which the text should fit in a card's worth of lines, within sensible limits.
    static func bodyHeight(fitting text: String, in maxWidth: CGFloat,
                           metrics: [Character: [GlyphMetrics]], maxHeight: CGFloat = 760) -> CGFloat {
        // The text's width at a lowercase height of 1, from the actual letters it uses.
        let reference = HandwritingLayout.reference(metrics)
        let layout = HandwritingLayout.tidy(bodyHeight: 1)
        var widthAtOne: CGFloat = 0
        var lines: CGFloat = 1
        for character in text {
            switch character {
            case "\n": lines += 1
            case " ": widthAtOne += layout.wordSpacing
            default:
                if let glyph = metrics[character]?.first {
                    widthAtOne += glyph.width / reference + layout.letterSpacing
                }
            }
        }
        guard widthAtOne > 0 else { return 30 }
        // Height h fills lines(h) = widthAtOne*h/maxWidth lines, each lineSpacing*h tall, and
        // the lot has to fit in maxHeight; explicit line breaks add lines of their own.
        let byArea = sqrt(maxHeight * maxWidth / (widthAtOne * layout.lineSpacing))
        let byLines = maxHeight / ((lines + 1) * layout.lineSpacing)
        // The floor is where letters stop being comfortable to read at arm's length, not
        // where they stop fitting; a card that needs less than this is better scrolled.
        return min(30, max(18, min(byArea, byLines)))
    }

    /// One stroke, redrawn cleanly and moved into place.
    private static func tidied(_ stroke: PKStroke, moving transform: CGAffineTransform,
                               width: CGFloat, ink: PKInk) -> PKStroke? {
        var locations = stroke.path.interpolatedPoints(by: .distance(1.5)).map(\.location)
        if locations.count < 2 {
            // A dot: PencilKit needs two points to draw anything at all.
            let centre = CGPoint(x: stroke.renderBounds.midX, y: stroke.renderBounds.midY)
            locations = [centre, CGPoint(x: centre.x + 0.5, y: centre.y)]
        }
        let smoothed = smooth(locations, radius: 2)

        let points = smoothed.enumerated().map { index, location in
            PKStrokePoint(location: location.applying(transform),
                          timeOffset: TimeInterval(index) * 0.004,
                          size: CGSize(width: width, height: width),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: ink, path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }

    /// A moving average that leaves the ends where they are, so a stroke keeps its start
    /// and finish but loses the shake in between.
    private static func smooth(_ points: [CGPoint], radius: Int) -> [CGPoint] {
        guard points.count > 2 * radius + 1 else { return points }
        return points.indices.map { i in
            guard i >= radius, i < points.count - radius else { return points[i] }
            var sum = CGPoint.zero
            for j in (i - radius)...(i + radius) {
                sum.x += points[j].x
                sum.y += points[j].y
            }
            let n = CGFloat(2 * radius + 1)
            return CGPoint(x: sum.x / n, y: sum.y / n)
        }
    }
}
