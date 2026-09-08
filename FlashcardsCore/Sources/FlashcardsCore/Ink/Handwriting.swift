import Foundation
import CoreGraphics

/// The characters worth capturing, in the order they are asked for.
///
/// Lowercase first because it is most of what anyone writes, then capitals, digits and the
/// punctuation that actually turns up in notes. Anything not captured is skipped when
/// composing, rather than substituted with something wrong.
public enum HandwritingAlphabet {
    public static let characters: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyz"
        + "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        + "0123456789"
        + ".,'?!:;-()/&+="
    )

    public static var count: Int { characters.count }
}

/// The size of one captured letter, in the coordinate space it was written in.
public struct GlyphMetrics: Sendable, Equatable {
    public var width: CGFloat
    public var height: CGFloat
    /// How far the ink descends below the writing line — the tail of a `g` or `y`.
    public var descender: CGFloat

    public init(width: CGFloat, height: CGFloat, descender: CGFloat = 0) {
        self.width = width
        self.height = height
        self.descender = descender
    }
}

/// Where one letter goes when composing a line of text.
public struct GlyphPlacement: Sendable, Equatable {
    public var character: Character
    /// Which captured sample of that character to use, when several exist.
    public var sampleIndex: Int
    /// Top-left of the glyph, in the composed drawing's coordinates.
    public var origin: CGPoint
    public var scale: CGFloat
    /// Small rotation, in radians, so repeated letters do not look stamped.
    public var rotation: CGFloat

    public init(character: Character, sampleIndex: Int, origin: CGPoint,
                scale: CGFloat, rotation: CGFloat) {
        self.character = character
        self.sampleIndex = sampleIndex
        self.origin = origin
        self.scale = scale
        self.rotation = rotation
    }
}

/// How a letter meets the writing line, which is how its size has to be judged.
///
/// Sizing every letter to one height is what makes composed writing look wrong: it leaves
/// an `o` as tall as an `l` and blows a hyphen up into a dash the height of a capital.
/// Letters are only comparable within their own class.
public enum GlyphClass: Sendable, Hashable, CaseIterable {
    case xHeight
    case ascender
    case descender
    case capital
    case digit
    /// `i`, `j` and punctuation: each mark has its own natural size and no useful peers.
    case ownSize

    public static func of(_ character: Character) -> GlyphClass {
        if "acemnorsuvwxz".contains(character) { return .xHeight }
        if "bdfhklt".contains(character) { return .ascender }
        if "gpqy".contains(character) { return .descender }
        if character.isUppercase { return .capital }
        if character.isNumber { return .digit }
        return .ownSize
    }
}

/// Where a letter meets the writing line, for captures that did not record it.
///
/// Ink alone does not say where the line was: a captured `o` and a captured `g` are both
/// just a shape. Unless the line was noted at capture time it has to come from what the
/// character is — an `o` rests on it, a `g` hangs a tail below it, an apostrophe floats
/// clear above it. Guessing from where the ink happened to land on the canvas does not
/// work, because letters get written wherever there is room.
public enum GlyphRest {
    /// Letters whose body sits on the line with a tail below.
    static let tailed: Set<Character> = ["g", "p", "q", "y"]

    /// How far below the writing line this letter's ink reaches.
    ///
    /// Negative means the ink stops short of the line and floats above it, as a hyphen does.
    public static func estimatedDescender(for character: Character, height: CGFloat,
                                          xHeight: CGFloat, ascenderHeight: CGFloat) -> CGFloat {
        if tailed.contains(character) {
            // The bowl is about one lowercase body; whatever is left is tail.
            return max(0, height - xHeight)
        }
        switch character {
        case "j":
            // Like an `i`, body and dot above the line, then the tail.
            return max(0, height - xHeight * 1.3)
        case "f":
            // A written `f` reaches ascender height above the line and loops below it.
            return max(0, height - ascenderHeight)
        case ",", ";":
            return xHeight * 0.15
        case "(", ")", "/":
            return xHeight * 0.20
        case "\'":
            return -xHeight * 0.60
        case "-", "=", "+":
            return -xHeight * 0.35
        default:
            return 0
        }
    }

    /// The usual height of a plain lowercase letter, and of one with an ascender.
    public static func references(_ heights: [Character: [CGFloat]]) -> (xHeight: CGFloat,
                                                                        ascender: CGFloat) {
        func median(_ characters: Set<Character>) -> CGFloat? {
            let values = heights.filter { characters.contains($0.key) }.values.flatMap { $0 }
            return HandwritingLayout.median(values)
        }
        let x = median(Set("acemnorsuvwxz")) ?? 30
        // `f` is left out: it is the one ascender that also drops below the line.
        let ascender = median(Set("bdhklt")) ?? x * 1.5
        return (max(x, 1), max(ascender, 1))
    }
}

/// Arranges captured letters into lines of text.
///
/// This is what turns a library of single letters into something that reads as writing
/// rather than as a ransom note: letters sit on a common baseline, spacing follows each
/// letter's own width, and every glyph is nudged slightly in size, angle and height so the
/// same letter never appears twice identically. That repetition is the usual giveaway of
/// synthesised handwriting.
public struct HandwritingLayout: Sendable {
    /// Target height of a lowercase letter without ascender or descender.
    public var bodyHeight: CGFloat
    /// Gap between letters, as a fraction of body height.
    public var letterSpacing: CGFloat
    /// Width of a space, as a fraction of body height.
    public var wordSpacing: CGFloat
    /// Distance between baselines, as a multiple of body height.
    public var lineSpacing: CGFloat
    /// How much each glyph may vary, 0 for none.
    public var jitter: CGFloat
    /// How strongly letters of the same class are pulled towards a common size.
    ///
    /// Capturing one letter at a time invites drift — the same hand writes `x` half the
    /// height of `e` across two screens. 0 keeps every letter exactly as written, 1 makes
    /// each class uniform; in between evens out the drift while leaving the variation that
    /// makes writing look written.
    public var evenness: CGFloat

    /// Set from the captured hand rather than picked by eye: the tallest ink above the
    /// writing line runs about 1.45 lowercase heights and the tails below it about 0.51, so
    /// a line occupies close to two. At the old 1.9 the lines actually overlapped, and a
    /// descender landed on the ascender beneath it. This leaves half a lowercase height of
    /// clear paper between one line and the next.
    public init(bodyHeight: CGFloat = 44, letterSpacing: CGFloat = 0.08,
                wordSpacing: CGFloat = 0.6, lineSpacing: CGFloat = 2.5,
                jitter: CGFloat = 1, evenness: CGFloat = 0.75) {
        self.bodyHeight = bodyHeight
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.lineSpacing = lineSpacing
        self.jitter = jitter
        self.evenness = evenness
    }

    /// Even and steady: every letter of a kind the same height, all on one line, nothing
    /// tilted or nudged. This is the neat version of the hand rather than the lively one.
    public static func tidy(bodyHeight: CGFloat = 44) -> HandwritingLayout {
        HandwritingLayout(bodyHeight: bodyHeight, letterSpacing: 0.10, jitter: 0, evenness: 1)
    }

    /// The size everything else is measured against: the usual height of a plain lowercase
    /// letter in this library.
    public static func reference(_ samples: [Character: [GlyphMetrics]]) -> CGFloat {
        let bodies = samples.flatMap { character, list in
            GlyphClass.of(character) == .xHeight ? list.map(\.height) : []
        }
        if let median = Self.median(bodies), median > 0 { return median }
        // Nothing plain and lowercase captured yet: any size beats dividing by zero.
        return Self.median(samples.values.flatMap { $0.map(\.height) }).map { max($0, 1) } ?? 1
    }

    static func classMedians(_ samples: [Character: [GlyphMetrics]]) -> [GlyphClass: CGFloat] {
        var heights: [GlyphClass: [CGFloat]] = [:]
        for (character, list) in samples {
            heights[GlyphClass.of(character), default: []].append(contentsOf: list.map(\.height))
        }
        return heights.compactMapValues { Self.median($0) }
    }

    static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// How much to grow or shrink one captured letter.
    ///
    /// Every letter shares one scale, so the sizes that were written are the sizes that come
    /// out. On top of that, a letter is nudged towards the usual size of its own class, which
    /// absorbs the drift of capturing them one at a time.
    func scale(for character: Character, metrics: GlyphMetrics,
               base: CGFloat, medians: [GlyphClass: CGFloat]) -> CGFloat {
        let glyphClass = GlyphClass.of(character)
        guard glyphClass != .ownSize, metrics.height > 0,
              let median = medians[glyphClass], median > 0
        else { return base }
        return base * pow(median / metrics.height, evenness)
    }

    public struct Result: Sendable, Equatable {
        public var placements: [GlyphPlacement]
        public var size: CGSize
        /// Characters with no captured sample, so the caller can say what was skipped.
        public var missing: Set<Character>
    }

    /// Lays `text` out using whatever glyphs are available.
    ///
    /// `samples` maps a character to the metrics of each captured sample of it. A character
    /// with no samples is skipped and reported rather than guessed at.
    public func layout<G: RandomNumberGenerator>(
        _ text: String,
        samples: [Character: [GlyphMetrics]],
        maxWidth: CGFloat,
        using rng: inout G
    ) -> Result {
        var placements: [GlyphPlacement] = []
        var missing: Set<Character> = []

        let base = bodyHeight / Self.reference(samples)
        let medians = Self.classMedians(samples)

        let space = bodyHeight * wordSpacing
        let gap = bodyHeight * letterSpacing
        let lineHeight = bodyHeight * lineSpacing
        // Room above the first line for capitals and ascenders, and below the last for tails.
        let ascent = bodyHeight * 1.8
        let descent = bodyHeight

        var pen = CGPoint(x: 0, y: ascent)      // y is the writing line, not the top of the ink
        var widest: CGFloat = 0

        // A line break in the text is a line break on the page; within a paragraph, break
        // on words so a line never splits one in half.
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
        if paragraphIndex > 0 { pen = CGPoint(x: 0, y: pen.y + lineHeight) }
        for (wordIndex, word) in paragraph.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            let wordWidth = width(of: String(word), samples: samples,
                                  gap: gap, base: base, medians: medians)

            if wordIndex > 0 {
                if pen.x + space + wordWidth > maxWidth, pen.x > 0 {
                    pen = CGPoint(x: 0, y: pen.y + lineHeight)
                } else {
                    pen.x += space
                }
            }

            for character in word {
                guard let variants = samples[character], !variants.isEmpty else {
                    missing.insert(character)
                    continue
                }

                let index = variants.count == 1 ? 0 : Int.random(in: 0..<variants.count, using: &rng)
                let metrics = variants[index]
                let scale = scale(for: character, metrics: metrics, base: base, medians: medians)
                let drawnWidth = metrics.width * scale

                if pen.x + drawnWidth > maxWidth, pen.x > 0 {
                    pen = CGPoint(x: 0, y: pen.y + lineHeight)
                }

                let wobble = jitter == 0 ? (scale: CGFloat(1), rotation: CGFloat(0), lift: CGFloat(0))
                    : (scale: 1 + CGFloat.random(in: -0.05...0.05, using: &rng) * jitter,
                       rotation: CGFloat.random(in: -0.035...0.035, using: &rng) * jitter,
                       lift: CGFloat.random(in: -0.04...0.04, using: &rng) * jitter * bodyHeight)

                // Sit the letter on the writing line: what shows above it is everything but
                // the tail. Aligning tops instead would hang a comma level with a capital.
                let finalScale = scale * wobble.scale
                let aboveLine = (metrics.height - metrics.descender) * finalScale

                placements.append(GlyphPlacement(
                    character: character,
                    sampleIndex: index,
                    origin: CGPoint(x: pen.x, y: pen.y - aboveLine + wobble.lift),
                    scale: finalScale,
                    rotation: wobble.rotation
                ))

                pen.x += drawnWidth + gap
                widest = max(widest, pen.x)
            }
        }
        }

        return Result(
            placements: placements,
            size: CGSize(width: min(max(widest, 1), maxWidth), height: pen.y + descent),
            missing: missing
        )
    }

    /// Convenience for callers that do not care about determinism.
    public func layout(_ text: String, samples: [Character: [GlyphMetrics]],
                       maxWidth: CGFloat) -> Result {
        var rng = SystemRandomNumberGenerator()
        return layout(text, samples: samples, maxWidth: maxWidth, using: &rng)
    }

    /// Width of a word, used to decide where lines break.
    func width(of word: String, samples: [Character: [GlyphMetrics]], gap: CGFloat,
               base: CGFloat, medians: [GlyphClass: CGFloat]) -> CGFloat {
        var total: CGFloat = 0
        for character in word {
            guard let variants = samples[character], let metrics = variants.first else { continue }
            total += metrics.width * scale(for: character, metrics: metrics,
                                           base: base, medians: medians) + gap
        }
        return max(0, total - gap)
    }
}
