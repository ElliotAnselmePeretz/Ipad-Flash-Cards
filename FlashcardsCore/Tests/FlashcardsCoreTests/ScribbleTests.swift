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

    private func line(from: CGPoint, to: CGPoint, steps: Int = 20) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    // MARK: - Detection

    func testADenseZigZagIsAScribble() {
        XCTAssertTrue(detector.isScribble(scribble(), duration: 0.35))
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
        XCTAssertTrue(detector.isScribble(scribble(), duration: 0.35))
        XCTAssertFalse(detector.isScribble(scribble(), duration: 2.5),
                       "a shape drawn carefully is drawing, not deleting")
    }

    func testAStrokeWithNoTimingIsRefused() {
        XCTAssertFalse(detector.isScribble(scribble(), duration: nil),
                       "without timing, deleting would be a guess")
    }

    func testZeroDurationIsRefused() {
        XCTAssertFalse(detector.isScribble(scribble(), duration: 0))
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
        XCTAssertFalse(strict.isScribble(scribble(), duration: 0.3), "a stricter detector should refuse more")
    }
}
