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

    public init(bodyHeight: CGFloat = 44, letterSpacing: CGFloat = 0.06,
                wordSpacing: CGFloat = 0.42, lineSpacing: CGFloat = 1.9,
                jitter: CGFloat = 1) {
        self.bodyHeight = bodyHeight
        self.letterSpacing = letterSpacing
        self.wordSpacing = wordSpacing
        self.lineSpacing = lineSpacing
        self.jitter = jitter
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

        let space = bodyHeight * wordSpacing
        let gap = bodyHeight * letterSpacing
        let lineHeight = bodyHeight * lineSpacing

        var pen = CGPoint(x: 0, y: 0)
        var widest: CGFloat = 0

        // Break on words so a line never splits one in half.
        for (wordIndex, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            let wordWidth = width(of: String(word), samples: samples, gap: gap)

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
                let scale = bodyHeight / max(metrics.height, 1)
                let drawnWidth = metrics.width * scale

                if pen.x + drawnWidth > maxWidth, pen.x > 0 {
                    pen = CGPoint(x: 0, y: pen.y + lineHeight)
                }

                let wobble = jitter == 0 ? (scale: CGFloat(1), rotation: CGFloat(0), lift: CGFloat(0))
                    : (scale: 1 + CGFloat.random(in: -0.05...0.05, using: &rng) * jitter,
                       rotation: CGFloat.random(in: -0.035...0.035, using: &rng) * jitter,
                       lift: CGFloat.random(in: -0.04...0.04, using: &rng) * jitter * bodyHeight)

                placements.append(GlyphPlacement(
                    character: character,
                    sampleIndex: index,
                    origin: CGPoint(x: pen.x, y: pen.y + wobble.lift),
                    scale: scale * wobble.scale,
                    rotation: wobble.rotation
                ))

                pen.x += drawnWidth + gap
                widest = max(widest, pen.x)
            }
        }

        return Result(
            placements: placements,
            size: CGSize(width: min(max(widest, 1), maxWidth), height: pen.y + lineHeight),
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
    func width(of word: String, samples: [Character: [GlyphMetrics]], gap: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for character in word {
            guard let variants = samples[character], let metrics = variants.first else { continue }
            total += metrics.width * (bodyHeight / max(metrics.height, 1)) + gap
        }
        return max(0, total - gap)
    }
}
