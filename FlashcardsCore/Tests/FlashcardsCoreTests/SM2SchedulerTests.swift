import XCTest
@testable import FlashcardsCore

/// Fuzz is disabled so intervals are exact and assertions can be strict.
private let deterministic: SchedulerConfig = {
    var c = SchedulerConfig.default
    c.intervalFuzzFactor = 0
    return c
}()

final class SM2SchedulerTests: XCTestCase {
    let scheduler = SM2Scheduler(config: deterministic)
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func minutes(_ n: Double) -> TimeInterval { n * 60 }
    private func days(_ n: Double) -> TimeInterval { n * 86_400 }

    // MARK: - Learning

    func testNewCardAnsweredGoodMovesToSecondLearningStep() {
        let s = scheduler.review(.new(config: deterministic, now: t0), grade: .good, now: t0)
        XCTAssertEqual(s.phase, .learning(step: 1))
        XCTAssertEqual(s.dueDate.timeIntervalSince(t0), minutes(10), accuracy: 0.001)
        XCTAssertEqual(s.easeFactor, 2.5, accuracy: 0.0001, "ease must not move during learning")
    }

    func testNewCardAnsweredEasyGraduatesImmediately() {
        let s = scheduler.review(.new(config: deterministic, now: t0), grade: .easy, now: t0)
        XCTAssertEqual(s.phase, .review)
        XCTAssertEqual(s.intervalDays, 4, accuracy: 0.0001)
        XCTAssertEqual(s.dueDate.timeIntervalSince(t0), days(4), accuracy: 0.001)
    }

    func testCompletingAllLearningStepsGraduatesToOneDay() {
        var s = SchedulingState.new(config: deterministic, now: t0)
        s = scheduler.review(s, grade: .good, now: t0)          // -> step 1
        s = scheduler.review(s, grade: .good, now: t0)          // -> graduates
        XCTAssertEqual(s.phase, .review)
        XCTAssertEqual(s.intervalDays, 1, accuracy: 0.0001)
        XCTAssertEqual(s.repetitions, 1)
    }

    func testAgainDuringLearningResetsToFirstStep() {
        var s = SchedulingState.new(config: deterministic, now: t0)
        s = scheduler.review(s, grade: .good, now: t0)          // -> step 1
        s = scheduler.review(s, grade: .again, now: t0)
        XCTAssertEqual(s.phase, .learning(step: 0))
        XCTAssertEqual(s.dueDate.timeIntervalSince(t0), minutes(1), accuracy: 0.001)
    }

    func testHardDuringLearningRepeatsSameStep() {
        var s = SchedulingState.new(config: deterministic, now: t0)
        s = scheduler.review(s, grade: .good, now: t0)          // -> step 1
        s = scheduler.review(s, grade: .hard, now: t0)
        XCTAssertEqual(s.phase, .learning(step: 1))
    }

    // MARK: - Review

    private func graduatedCard(intervalDays: Double = 10, ease: Double = 2.5) -> SchedulingState {
        SchedulingState(
            phase: .review, intervalDays: intervalDays, easeFactor: ease,
            repetitions: 3, lapses: 0, dueDate: t0, lastReviewedAt: nil
        )
    }

    func testGoodMultipliesIntervalByEase() {
        let s = scheduler.review(graduatedCard(), grade: .good, now: t0)
        XCTAssertEqual(s.intervalDays, 25, accuracy: 0.0001)     // 10 * 2.5
        XCTAssertEqual(s.easeFactor, 2.5, accuracy: 0.0001)
        XCTAssertEqual(s.repetitions, 4)
    }

    func testHardUsesHardMultiplierAndDropsEase() {
        let s = scheduler.review(graduatedCard(), grade: .hard, now: t0)
        XCTAssertEqual(s.intervalDays, 12, accuracy: 0.0001)     // 10 * 1.2
        XCTAssertEqual(s.easeFactor, 2.35, accuracy: 0.0001)     // 2.5 - 0.15
    }

    func testEasyAppliesBonusAndRaisesEase() {
        let s = scheduler.review(graduatedCard(), grade: .easy, now: t0)
        XCTAssertEqual(s.easeFactor, 2.65, accuracy: 0.0001)     // 2.5 + 0.15
        XCTAssertEqual(s.intervalDays, 34.45, accuracy: 0.0001)  // 10 * 2.65 * 1.3
    }

    func testIntervalsGrowAcrossSuccessfulReviews() {
        var s = graduatedCard(intervalDays: 1)
        var last = s.intervalDays
        for _ in 0..<6 {
            s = scheduler.review(s, grade: .good, now: s.dueDate)
            XCTAssertGreaterThan(s.intervalDays, last, "each success must space the card further out")
            last = s.intervalDays
        }
        XCTAssertGreaterThan(s.intervalDays, 100, "six good answers should reach months")
    }

    // MARK: - Lapses

    func testAgainOnReviewCardLapsesIntoRelearning() {
        let s = scheduler.review(graduatedCard(intervalDays: 30), grade: .again, now: t0)
        XCTAssertEqual(s.phase, .relearning(step: 0))
        XCTAssertEqual(s.lapses, 1)
        XCTAssertEqual(s.repetitions, 0)
        XCTAssertEqual(s.easeFactor, 2.3, accuracy: 0.0001)      // 2.5 - 0.20
        XCTAssertEqual(s.intervalDays, 1, accuracy: 0.0001, "interval resets to the floor")
        XCTAssertEqual(s.dueDate.timeIntervalSince(t0), minutes(10), accuracy: 0.001)
    }

    func testGoodAfterRelearningReturnsToReview() {
        var s = scheduler.review(graduatedCard(intervalDays: 30), grade: .again, now: t0)
        s = scheduler.review(s, grade: .good, now: t0)
        XCTAssertEqual(s.phase, .review)
        XCTAssertEqual(s.intervalDays, 1, accuracy: 0.0001)
    }

    func testEaseNeverFallsBelowMinimum() {
        var s = graduatedCard(ease: 1.4)
        for _ in 0..<10 {
            s = scheduler.review(s, grade: .again, now: s.dueDate)
            s = scheduler.review(s, grade: .good, now: s.dueDate)
        }
        XCTAssertGreaterThanOrEqual(s.easeFactor, deterministic.minimumEase)
    }

    func testIntervalNeverExceedsMaximum() {
        var s = graduatedCard(intervalDays: 30_000)
        s = scheduler.review(s, grade: .easy, now: t0)
        XCTAssertLessThanOrEqual(s.intervalDays, deterministic.maximumInterval)
    }

    // MARK: - Fuzz

    func testFuzzKeepsIntervalsWithinConfiguredSpread() {
        let fuzzy = SM2Scheduler(config: .default)   // 5% fuzz
        var seen = Set<Double>()
        for _ in 0..<200 {
            let s = fuzzy.review(graduatedCard(), grade: .good, now: t0)
            XCTAssertGreaterThanOrEqual(s.intervalDays, 25 * 0.95 - 0.0001)
            XCTAssertLessThanOrEqual(s.intervalDays, 25 * 1.05 + 0.0001)
            seen.insert(s.intervalDays)
        }
        XCTAssertGreaterThan(seen.count, 1, "fuzz should actually vary the interval")
    }

    func testShortIntervalsAreNotFuzzed() {
        let fuzzy = SM2Scheduler(config: .default)
        let s = fuzzy.review(.new(now: t0), grade: .good, now: t0)
        _ = s
        let graduated = fuzzy.review(graduatedCard(intervalDays: 1), grade: .hard, now: t0)
        XCTAssertEqual(graduated.intervalDays, 1.2, accuracy: 0.0001, "under 2 days stays exact")
    }
}
