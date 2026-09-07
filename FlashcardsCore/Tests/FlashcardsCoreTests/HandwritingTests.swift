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

    func testGlyphsAreScaledToACommonBodyHeight() {
        var samples = uniformSamples()
        samples["a"] = [GlyphMetrics(width: 60, height: 88)]   // captured twice as large
        var r = rng()
        let result = steady.layout("ab", samples: samples, maxWidth: 1000, using: &r)
        XCTAssertEqual(result.placements[0].scale, 0.5, accuracy: 0.001)
        XCTAssertEqual(result.placements[1].scale, 1.0, accuracy: 0.001,
                       "letters captured at different sizes must end up the same size")
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
