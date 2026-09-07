import XCTest
import CoreGraphics
@testable import FlashcardsCore

final class ScribbleDetectorTests: XCTestCase {

    let detector = ScribbleDetector()

    /// A dense zig-zag over the same ground: what crossing something out looks like.
    private func scribble(width: CGFloat = 120, passes: Int = 8, y: CGFloat = 100) -> [CGPoint] {
        var points: [CGPoint] = []
        for pass in 0..<passes {
            let forward = pass % 2 == 0
            for step in stride(from: 0.0, through: 1.0, by: 0.1) {
                let t = forward ? step : 1 - step
                points.append(CGPoint(x: width * t, y: y + CGFloat(pass) * 2))
            }
        }
        return points
    }

    /// Ink already on the page, lying under the scribble's path.
    private func word(y: CGFloat = 108) -> [CGPoint] {
        (0...60).map { CGPoint(x: CGFloat($0) * 2, y: y) }
    }

    private func line(from: CGPoint, to: CGPoint, steps: Int = 20) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    // MARK: - Detection

    func testADenseZigZagIsAScribble() {
        XCTAssertTrue(detector.isScribble(scribble(), duration: 0.3, over: [word()]))
    }

    func testAStraightLineIsNot() {
        XCTAssertFalse(detector.isScribble(line(from: .zero, to: CGPoint(x: 300, y: 0)), duration: 0.3))
    }

    func testASingleCurveIsNot() {
        let arc = (0...40).map { i -> CGPoint in
            let t = CGFloat(i) / 40 * .pi
            return CGPoint(x: cos(t) * 100 + 100, y: sin(t) * 100)
        }
        XCTAssertFalse(detector.isScribble(arc, duration: 0.3))
    }

    /// The case that matters: handwriting must survive.
    func testTheLetterWIsNotAScribble() {
        // Four strokes down-up-down-up across a normal letter width, written once.
        let w = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 40), CGPoint(x: 20, y: 5),
                 CGPoint(x: 30, y: 40), CGPoint(x: 40, y: 0)]
        let dense = w.flatMap { p in [p, p, p] }   // sampled finely, as a real stroke would be
        XCTAssertFalse(detector.isScribble(dense, duration: 0.3))
    }

    func testTheLetterMIsNotAScribble() {
        let m = [CGPoint(x: 0, y: 40), CGPoint(x: 0, y: 0), CGPoint(x: 15, y: 25),
                 CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 40)]
        XCTAssertFalse(detector.isScribble(m, duration: 0.4))
    }

    func testACursiveWordIsNotAScribble() {
        // Wavy but travelling steadily rightwards, the way writing does.
        let word = (0...80).map { i -> CGPoint in
            let x = CGFloat(i) * 4
            return CGPoint(x: x, y: sin(CGFloat(i) / 2) * 12)
        }
        XCTAssertFalse(detector.isScribble(word, duration: 1.2),
                       "writing moves across the page; a scribble stays put")
    }

    func testATinyScratchIsIgnored() {
        XCTAssertFalse(detector.isScribble(scribble(width: 8, passes: 6), duration: 0.2),
                       "a flick of the pen should not delete anything")
    }

    func testTooFewPointsIsNotAScribble() {
        XCTAssertFalse(detector.isScribble([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)], duration: 0.2))
    }

    func testEmptyInputIsSafe() {
        XCTAssertFalse(detector.isScribble([], duration: 0.2))
    }

    // MARK: - Speed

    /// The change that matters: the same shape, drawn slowly, is deliberate work.
    func testTheSameShapeDrawnSlowlyIsNotAScribble() {
        XCTAssertTrue(detector.isScribble(scribble(), duration: 0.3, over: [word()]))
        XCTAssertFalse(detector.isScribble(scribble(), duration: 2.5, over: [word()]),
                       "a shape drawn carefully is drawing, not deleting")
    }

    func testAStrokeWithNoTimingIsRefused() {
        XCTAssertFalse(detector.isScribble(scribble(), duration: nil, over: [word()]),
                       "without timing, deleting would be a guess")
    }

    func testZeroDurationIsRefused() {
        XCTAssertFalse(detector.isScribble(scribble(), duration: 0, over: [word()]))
    }

    // MARK: - Shape

    func testATallNarrowShapeIsNotAScribble() {
        // Dense and reversing, but square-ish rather than a band: a tangle, not a crossing out.
        var points: [CGPoint] = []
        for pass in 0..<8 {
            for step in stride(from: 0.0, through: 1.0, by: 0.1) {
                let t = pass % 2 == 0 ? step : 1 - step
                points.append(CGPoint(x: 60 * t, y: 60 * Double(pass) / 8))
            }
        }
        XCTAssertFalse(detector.isScribble(points, duration: 0.3))
    }

    // MARK: - Overlap

    /// The signal that actually means "delete this": going back and forth over ink that
    /// is already there. Writing lands on blank paper.
    func testAScribbleOverNothingIsNotADeletion() {
        XCTAssertFalse(detector.isScribble(scribble(), duration: 0.35, over: []),
                       "there is nothing to cross out on blank paper")
    }

    func testAScribbleAwayFromExistingInkIsNotADeletion() {
        let elsewhere = [word(y: 900)]
        XCTAssertFalse(detector.isScribble(scribble(), duration: 0.35, over: elsewhere))
    }

    func testAScribbleOverInkIsADeletion() {
        XCTAssertTrue(detector.isScribble(scribble(), duration: 0.3, over: [word()]))
    }

    func testMostOfAScratchOutLiesOnTopOfTheWord() {
        XCTAssertGreaterThan(detector.overlap(of: scribble(passes: 6), over: [word()]), 0.55)
    }

    func testAStrokeOnBlankPaperOverlapsNothing() {
        let elsewhere = line(from: CGPoint(x: 0, y: 900), to: CGPoint(x: 200, y: 900))
        XCTAssertEqual(detector.overlap(of: elsewhere, over: [word()]), 0)
    }

    func testASingleStrokeThroughAWordIsNotEnough() {
        // Crossing out means going back over something, not passing through once.
        let throughOnce = line(from: CGPoint(x: 0, y: 108), to: CGPoint(x: 120, y: 108), steps: 40)
        XCTAssertFalse(detector.isScribble(throughOnce, duration: 0.2, over: [word()]),
                       "one pass is a strikethrough, not a scratch-out")
    }

    func testOverlapIsZeroWithNothingOnThePage() {
        XCTAssertEqual(detector.overlap(of: scribble(), over: []), 0)
    }

    /// Because overlap carries the evidence, fewer passes are needed than before.
    func testAShortScratchOverAWordStillCounts() {
        XCTAssertTrue(detector.isScribble(scribble(passes: 5), duration: 0.25, over: [word()]),
                      "a few quick passes over a word should be enough")
    }

    // MARK: - Less scribbling when clearly on top of something

    /// The point of the change: two quick passes over a word should be enough.
    func testTwoPassesOverAWordIsEnough() {
        let quick = scribble(passes: 2)
        XCTAssertTrue(detector.isScribble(quick, duration: 0.12, over: [word()]),
                      "crossing something out is two strokes, not eight")
    }

    /// Taken from measured strokes: ordinary writing runs about 250 points per second and
    /// a density near 2, while scratch-outs run about 650 and a density near 3.
    func testWritingPaceOverExistingInkIsNotDeletion() {
        let ordinary = line(from: CGPoint(x: 0, y: 108), to: CGPoint(x: 60, y: 130), steps: 30)
        XCTAssertFalse(detector.isScribble(ordinary, duration: 0.25, over: [word()]),
                       "letters sit close together, so writing often overlaps; it is not deleting")
    }

    func testThreePassesOverAWordIsEnough() {
        XCTAssertTrue(detector.isScribble(scribble(passes: 3), duration: 0.2, over: [word()]))
    }

    /// The relaxation applies only on top of ink. On blank paper nothing is relaxed.
    func testTwoPassesOnBlankPaperDeletesNothing() {
        XCTAssertFalse(detector.isScribble(scribble(passes: 2), duration: 0.12, over: []))
    }

    func testTwoPassesAwayFromInkDeletesNothing() {
        XCTAssertFalse(detector.isScribble(scribble(passes: 2), duration: 0.12, over: [word(y: 900)]))
    }

    /// Drawing over your own work slowly is still drawing.
    func testSlowlyGoingOverExistingInkIsNotDeletion() {
        XCTAssertFalse(detector.isScribble(scribble(passes: 3), duration: 4.0, over: [word()]),
                       "deliberate work on top of a drawing must survive")
    }

    func testStrongOverlapPathIsNamedWhenItRefuses() {
        let tiny = detector.measure(scribble(width: 10, passes: 2), duration: 0.1, over: [word(y: 100)])
        XCTAssertFalse(tiny.isScribble)
        XCTAssertTrue(tiny.rejectedBy?.contains("strong") ?? false,
                      "a stroke over ink should be judged by the relaxed rules")
    }

    // MARK: - Measurement

    func testMeasurementAgreesWithTheDecision() {
        let fast = detector.measure(scribble(), duration: 0.3, over: [word()])
        XCTAssertTrue(fast.isScribble)
        XCTAssertNil(fast.rejectedBy)

        let slow = detector.measure(scribble(), duration: 2.5, over: [word()])
        XCTAssertFalse(slow.isScribble)
        XCTAssertEqual(slow.rejectedBy, "speed")
    }

    func testMeasurementNamesTheRuleThatRefused() {
        let straight = detector.measure(line(from: .zero, to: CGPoint(x: 400, y: 0)),
                                        duration: 0.3, over: [word()])
        XCTAssertFalse(straight.isScribble)
        XCTAssertEqual(straight.rejectedBy, "density")
    }

    func testMeasurementReportsRealNumbers() {
        let m = detector.measure(scribble(), duration: 0.5, over: [word()])
        XCTAssertGreaterThan(m.length, 0)
        XCTAssertGreaterThan(m.speed, 0)
        XCTAssertGreaterThan(m.reversals, 0)
        XCTAssertEqual(m.duration, 0.5, accuracy: 0.0001)
    }

    // MARK: - What gets deleted

    func testStrokesUnderTheScribbleAreCrossed() {
        let target = line(from: CGPoint(x: 10, y: 105), to: CGPoint(x: 100, y: 105))
        let crossed = detector.strokesCrossed(by: scribble(), candidates: [target])
        XCTAssertEqual(crossed, [0])
    }

    func testStrokesElsewhereAreLeftAlone() {
        let faraway = line(from: CGPoint(x: 600, y: 600), to: CGPoint(x: 700, y: 600))
        XCTAssertTrue(detector.strokesCrossed(by: scribble(), candidates: [faraway]).isEmpty)
    }

    func testOnlyTheCrossedStrokesGo() {
        let under = line(from: CGPoint(x: 10, y: 105), to: CGPoint(x: 100, y: 105))
        let above = line(from: CGPoint(x: 10, y: 400), to: CGPoint(x: 100, y: 400))
        let crossed = detector.strokesCrossed(by: scribble(), candidates: [under, above])
        XCTAssertEqual(crossed, [0])
    }

    func testNearMissesAreNotDeleted() {
        // Just outside the tolerance, below the scribble's band.
        let near = line(from: CGPoint(x: 10, y: 200), to: CGPoint(x: 100, y: 200))
        XCTAssertTrue(detector.strokesCrossed(by: scribble(), candidates: [near], tolerance: 10).isEmpty)
    }

    func testEmptyCandidateIsSkipped() {
        XCTAssertTrue(detector.strokesCrossed(by: scribble(), candidates: [[]]).isEmpty)
    }

    func testSensitivityIsAdjustable() {
        let strict = ScribbleDetector(minimumReversals: 40, minimumDensity: 20, minimumLength: 60)
        XCTAssertFalse(strict.isScribble(scribble(), duration: 0.3, over: [word()]), "a stricter detector should refuse more")
    }
}
