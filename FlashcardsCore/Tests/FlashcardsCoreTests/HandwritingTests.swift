import XCTest
import CoreGraphics
@testable import FlashcardsCore

final class HandwritingLayoutTests: XCTestCase {

    /// A library where every letter is the same modest size, so positions are predictable.
    private func uniformSamples(_ characters: String = "abcdefghijklmnopqrstuvwxyz ",
                                width: CGFloat = 30, height: CGFloat = 44,
                                variants: Int = 1) -> [Character: [GlyphMetrics]] {
        var samples: [Character: [GlyphMetrics]] = [:]
        for character in characters where character != " " {
            samples[character] = Array(repeating: GlyphMetrics(width: width, height: height),
                                       count: variants)
        }
        return samples
    }

    private var steady: HandwritingLayout {
        HandwritingLayout(bodyHeight: 44, jitter: 0)
    }

    private func rng(_ seed: UInt64 = 7) -> SeededGenerator { SeededGenerator(seed: seed) }

    // MARK: - Composing

    func testEveryLetterIsPlaced() {
        var r = rng()
        let result = steady.layout("abc", samples: uniformSamples(), maxWidth: 1000, using: &r)
        XCTAssertEqual(result.placements.map(\.character), ["a", "b", "c"])
        XCTAssertTrue(result.missing.isEmpty)
    }

    func testLettersRunLeftToRightWithoutOverlapping() {
        var r = rng()
        let result = steady.layout("abc", samples: uniformSamples(), maxWidth: 1000, using: &r)
        let xs = result.placements.map(\.origin.x)
        XCTAssertEqual(xs, xs.sorted())
        XCTAssertGreaterThan(xs[1] - xs[0], 29, "letters should not sit on top of each other")
    }

    func testSpacesSeparateWords() {
        var r = rng()
        let joined = steady.layout("ab", samples: uniformSamples(), maxWidth: 1000, using: &r)
        var r2 = rng()
        let spaced = steady.layout("a b", samples: uniformSamples(), maxWidth: 1000, using: &r2)
        XCTAssertGreaterThan(spaced.placements[1].origin.x, joined.placements[1].origin.x,
                             "a space should push the next word along")
    }

    /// Heights measured from a real capture session, which is where the sizing went wrong.
    private func realSamples() -> [Character: [GlyphMetrics]] {
        let measured: [(Character, CGFloat, CGFloat, CGFloat)] = [
            // character, width, height, descender
            ("o", 42, 41, 0), ("e", 39, 40, 0), ("a", 35, 40, 0), ("c", 38, 38, 0),
            ("n", 29, 37, 0), ("s", 31, 37, 0), ("x", 26, 23, 0), ("u", 30, 28, 0),
            ("l", 7, 51, 0), ("b", 28, 51, 0), ("h", 41, 52, 0), ("d", 23, 60, 0),
            ("g", 29, 55, 18), ("p", 27, 53, 17), ("y", 25, 73, 24),
            ("M", 56, 39, 0), ("T", 70, 59, 0),
            ("-", 30, 6, 0), (".", 12, 17, 0), ("'", 7, 17, 0),
        ]
        var samples: [Character: [GlyphMetrics]] = [:]
        for (character, width, height, descender) in measured {
            samples[character] = [GlyphMetrics(width: width, height: height, descender: descender)]
        }
        return samples
    }

    private func drawnHeight(_ placement: GlyphPlacement,
                             _ samples: [Character: [GlyphMetrics]]) -> CGFloat {
        samples[placement.character]![placement.sampleIndex].height * placement.scale
    }

    func testSmallMarksStaySmall() {
        let samples = realSamples()
        var r = rng()
        let result = steady.layout("o-o", samples: samples, maxWidth: 1000, using: &r)
        let letter = drawnHeight(result.placements[0], samples)
        let hyphen = drawnHeight(result.placements[1], samples)
        XCTAssertLessThan(hyphen, letter * 0.35,
                          "a hyphen must not be blown up to the height of a letter")
    }

    func testTallLettersStayTaller() {
        let samples = realSamples()
        var r = rng()
        let result = steady.layout("ol", samples: samples, maxWidth: 1000, using: &r)
        XCTAssertGreaterThan(drawnHeight(result.placements[1], samples),
                             drawnHeight(result.placements[0], samples) * 1.15,
                             "an 'l' has an ascender and an 'o' does not")
    }

    func testCaptureDriftIsEvenedOut() {
        let samples = realSamples()
        var r = rng()
        // 'x' was written at 23 and 'o' at 41, though both are plain lowercase.
        let result = steady.layout("xo", samples: samples, maxWidth: 1000, using: &r)
        let ratio = drawnHeight(result.placements[1], samples) / drawnHeight(result.placements[0], samples)
        XCTAssertLessThan(ratio, 41.0 / 23.0,
                          "letters of the same class should be pulled towards a common size")
        XCTAssertGreaterThan(ratio, 1.0, "but not flattened into exactly the same size")
    }

    func testEvennessCanBeTurnedOff() {
        let samples = realSamples()
        let asWritten = HandwritingLayout(bodyHeight: 44, jitter: 0, evenness: 0)
        var r = rng()
        let result = asWritten.layout("xo", samples: samples, maxWidth: 1000, using: &r)
        XCTAssertEqual(result.placements[0].scale, result.placements[1].scale, accuracy: 0.0001,
                       "with no evening out, one scale serves the whole library")
    }

    func testLettersSitOnACommonBaseline() {
        let samples = realSamples()
        var r = rng()
        let result = steady.layout("ogl.", samples: samples, maxWidth: 1000, using: &r)
        let baselines = result.placements.map { placement -> CGFloat in
            let metrics = samples[placement.character]![placement.sampleIndex]
            return placement.origin.y + (metrics.height - metrics.descender) * placement.scale
        }
        for baseline in baselines {
            XCTAssertEqual(baseline, baselines[0], accuracy: 0.001,
                           "every letter should rest on the same writing line")
        }
    }

    func testDescendersHangBelowTheLine() {
        let samples = realSamples()
        var r = rng()
        let result = steady.layout("og", samples: samples, maxWidth: 1000, using: &r)
        let bottom = { (placement: GlyphPlacement) -> CGFloat in
            let metrics = samples[placement.character]![placement.sampleIndex]
            return placement.origin.y + metrics.height * placement.scale
        }
        XCTAssertGreaterThan(bottom(result.placements[1]), bottom(result.placements[0]) + 5,
                             "the tail of a 'g' belongs below the line an 'o' sits on")
    }

    // MARK: - Meeting the writing line

    func testALetterThatRestsOnTheLineHasNoDrop() {
        for character in "aoenMT7." {
            XCTAssertEqual(GlyphRest.estimatedDescender(for: character, height: 40,
                                                        xHeight: 37, ascenderHeight: 55), 0,
                           "\(character) sits on the line")
        }
    }

    func testATailedLetterKeepsOneBodyAboveTheLine() {
        let height: CGFloat = 73                      // a real captured 'y'
        let drop = GlyphRest.estimatedDescender(for: "y", height: height,
                                                xHeight: 37, ascenderHeight: 55)
        XCTAssertEqual(height - drop, 37, accuracy: 0.001,
                       "the body of a 'y' is one lowercase height, the rest is tail")
    }

    func testAWrittenFReachesAscenderHeightNotBodyHeight() {
        let drop = GlyphRest.estimatedDescender(for: "f", height: 81,
                                                xHeight: 37, ascenderHeight: 55)
        XCTAssertEqual(81 - drop, 55, accuracy: 0.001, "an 'f' is tall above the line as well as below")
    }

    func testAHyphenFloatsClearOfTheLine() {
        let drop = GlyphRest.estimatedDescender(for: "-", height: 6,
                                                xHeight: 37, ascenderHeight: 55)
        XCTAssertLessThan(drop, 0, "a hyphen's bar never touches the writing line")
    }

    func testTheAscenderReferenceIgnoresF() {
        // 'f' is much taller than the other ascenders because it also drops below the line.
        let heights: [Character: [CGFloat]] = ["a": [37], "o": [37], "e": [37],
                                               "b": [51], "h": [52], "l": [51],
                                               "f": [200]]
        let reference = GlyphRest.references(heights)
        XCTAssertEqual(reference.xHeight, 37, accuracy: 0.001)
        XCTAssertLessThan(reference.ascender, 60, "a tall 'f' must not drag the reference up")
    }

    func testReferencesSurviveAnEmptyLibrary() {
        let reference = GlyphRest.references([:])
        XCTAssertGreaterThan(reference.xHeight, 0)
        XCTAssertGreaterThan(reference.ascender, 0)
    }

    // MARK: - Tidy

    func testTidyMakesLettersOfAKindTheSameHeight() {
        let samples = realSamples()
        var r = rng()
        let result = HandwritingLayout.tidy().layout("xo", samples: samples, maxWidth: 1000, using: &r)
        XCTAssertEqual(drawnHeight(result.placements[0], samples),
                       drawnHeight(result.placements[1], samples), accuracy: 0.01,
                       "two plain lowercase letters come out exactly the same height")
    }

    func testTidyKeepsTallLettersTall() {
        let samples = realSamples()
        var r = rng()
        let result = HandwritingLayout.tidy().layout("ol", samples: samples, maxWidth: 1000, using: &r)
        XCTAssertGreaterThan(drawnHeight(result.placements[1], samples),
                             drawnHeight(result.placements[0], samples) * 1.15)
    }

    func testTidyDoesNotTiltOrNudge() {
        var r = rng()
        let result = HandwritingLayout.tidy().layout("aaa", samples: uniformSamples(), maxWidth: 1000, using: &r)
        XCTAssertEqual(Set(result.placements.map(\.rotation)), [0])
        XCTAssertEqual(Set(result.placements.map(\.origin.y)).count, 1)
    }

    // MARK: - Alignment

    func testCentredLinesSitInTheMiddleOfTheWidth() {
        var layout = HandwritingLayout(bodyHeight: 44, jitter: 0)
        layout.alignment = .centered
        var r = rng()
        let result = layout.layout("ab", samples: uniformSamples(), maxWidth: 1000, using: &r)
        let left = result.placements[0].origin.x
        let right = result.placements[1].origin.x + 30 * result.placements[1].scale
        XCTAssertEqual(left, 1000 - right, accuracy: 0.5, "equal margins either side")
        XCTAssertGreaterThan(left, 400)
    }

    func testEachWrappedLineIsCentredOnItsOwn() {
        var layout = HandwritingLayout(bodyHeight: 44, jitter: 0)
        layout.alignment = .centered
        var r = rng()
        let result = layout.layout("aaaa a", samples: uniformSamples(), maxWidth: 160, using: &r)
        let lastLine = result.placements.filter { $0.origin.y == result.placements.last!.origin.y }
        XCTAssertEqual(lastLine.count, 1)
        XCTAssertEqual(lastLine[0].origin.x, (160 - 30) / 2, accuracy: 0.5,
                       "a short last line is centred, not left behind at the margin")
    }

    func testLeadingIsStillTheDefault() {
        var r = rng()
        let result = steady.layout("ab", samples: uniformSamples(), maxWidth: 1000, using: &r)
        XCTAssertEqual(result.placements[0].origin.x, 0)
    }

    // MARK: - Line breaks

    func testANewlineStartsANewLine() {
        var r = rng()
        let result = steady.layout("ab\ncd", samples: uniformSamples(), maxWidth: 1000, using: &r)
        let ys = result.placements.map(\.origin.y)
        XCTAssertEqual(ys[0], ys[1])
        XCTAssertGreaterThan(ys[2], ys[0], "text after a line break sits on the next line")
        XCTAssertEqual(ys[2], ys[3])
        XCTAssertEqual(result.placements[2].origin.x, 0, "and starts back at the margin")
        XCTAssertTrue(result.missing.isEmpty, "a newline is not a missing letter")
    }

    // MARK: - Wrapping

    func testTextWrapsWithinTheGivenWidth() {
        var r = rng()
        let result = steady.layout("aaaa aaaa aaaa", samples: uniformSamples(),
                                   maxWidth: 120, using: &r)
        let lines = Set(result.placements.map(\.origin.y))
        XCTAssertGreaterThan(lines.count, 1, "long text should use more than one line")
        XCTAssertLessThanOrEqual(result.size.width, 120)
    }

    func testAWordIsNotSplitAcrossLines() {
        var r = rng()
        let result = steady.layout("aa aaaaaa", samples: uniformSamples(), maxWidth: 200, using: &r)
        let second = result.placements.dropFirst(2)
        let ys = Set(second.map(\.origin.y))
        XCTAssertEqual(ys.count, 1, "the second word should stay on one line")
    }

    /// Measured from the captured hand: ink reaches about 1.45 lowercase heights above the
    /// writing line and 0.51 below it, so lines set less than two apart collide.
    func testLinesDoNotCollide() {
        let layout = HandwritingLayout(bodyHeight: 44, jitter: 0)
        XCTAssertGreaterThan(layout.lineSpacing, 1.45 + 0.51,
                             "a descender must not land on the ascender beneath it")
    }

    func testLinesAreSpacedApart() {
        var r = rng()
        let result = steady.layout("aaaa aaaa", samples: uniformSamples(), maxWidth: 120, using: &r)
        let ys = Set(result.placements.map(\.origin.y)).sorted()
        XCTAssertGreaterThan(ys[1] - ys[0], 44, "lines must not overlap")
    }

    // MARK: - Missing letters

    func testUncapturedCharactersAreReportedNotGuessed() {
        var r = rng()
        let result = steady.layout("a€b", samples: uniformSamples(), maxWidth: 1000, using: &r)
        XCTAssertEqual(result.placements.map(\.character), ["a", "b"])
        XCTAssertEqual(result.missing, ["€"])
    }

    func testTextWithNoCapturedLettersPlacesNothing() {
        var r = rng()
        let result = steady.layout("€€", samples: [:], maxWidth: 500, using: &r)
        XCTAssertTrue(result.placements.isEmpty)
        XCTAssertEqual(result.missing, ["€"])
    }

    func testEmptyTextIsSafe() {
        var r = rng()
        let result = steady.layout("", samples: uniformSamples(), maxWidth: 500, using: &r)
        XCTAssertTrue(result.placements.isEmpty)
    }

    // MARK: - Variation

    /// Identical repeated letters are what makes synthesised writing look fake.
    func testRepeatedLettersAreNotIdentical() {
        var r = rng()
        let lively = HandwritingLayout(bodyHeight: 44, jitter: 1)
        let result = lively.layout("aaaaaa", samples: uniformSamples(), maxWidth: 2000, using: &r)
        let scales = Set(result.placements.map { round($0.scale * 1000) })
        let rotations = Set(result.placements.map { round($0.rotation * 1000) })
        XCTAssertGreaterThan(scales.count, 1, "every 'a' should not be exactly the same size")
        XCTAssertGreaterThan(rotations.count, 1, "nor sit at exactly the same angle")
    }

    func testJitterCanBeTurnedOff() {
        var r = rng()
        let result = steady.layout("aaa", samples: uniformSamples(), maxWidth: 2000, using: &r)
        XCTAssertEqual(Set(result.placements.map(\.rotation)), [0])
        XCTAssertEqual(Set(result.placements.map(\.scale)).count, 1)
    }

    func testSeveralCapturedSamplesGetUsed() {
        var r = rng(11)
        let lively = HandwritingLayout(bodyHeight: 44, jitter: 1)
        let result = lively.layout(String(repeating: "a", count: 40),
                                   samples: uniformSamples(variants: 3),
                                   maxWidth: 5000, using: &r)
        XCTAssertGreaterThan(Set(result.placements.map(\.sampleIndex)).count, 1,
                             "captured variants should all be drawn on")
    }

    func testTheSameSeedGivesTheSameResult() {
        var a = rng(3), b = rng(3)
        let lively = HandwritingLayout(bodyHeight: 44, jitter: 1)
        let first = lively.layout("hello there", samples: uniformSamples(), maxWidth: 400, using: &a)
        let second = lively.layout("hello there", samples: uniformSamples(), maxWidth: 400, using: &b)
        XCTAssertEqual(first, second)
    }

    // MARK: - Alphabet

    func testTheAlphabetCoversWhatNotesActuallyContain() {
        let set = Set(HandwritingAlphabet.characters)
        for character in "abcxyzABCXYZ0189.,'?!:;-()/&+=" {
            XCTAssertTrue(set.contains(character), "\(character) should be captured")
        }
        XCTAssertFalse(set.contains(" "), "a space is not written")
    }

    func testAlphabetHasNoDuplicates() {
        XCTAssertEqual(Set(HandwritingAlphabet.characters).count, HandwritingAlphabet.count)
    }
}
