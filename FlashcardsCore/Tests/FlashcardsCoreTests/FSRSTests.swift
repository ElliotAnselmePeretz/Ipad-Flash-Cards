import XCTest
@testable import FlashcardsCore

/// Deterministic RNG, so tests can assert on intervals despite interval fuzz.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

final class FSRSTests: XCTestCase {

    let fsrs = FSRSScheduler()

    // MARK: - The forgetting curve

    /// The defining property of FSRS: stability *is* the interval at 90% recall.
    func testRetrievabilityIsExactlyNinetyPercentAtOneStability() {
        let r = fsrs.retrievability(elapsedDays: 10, stability: 10)
        XCTAssertEqual(r, 0.9, accuracy: 0.0001,
                       "by definition R(S, S) must be 0.9")
    }

    func testRetrievabilityIsOneAtZeroElapsed() {
        XCTAssertEqual(fsrs.retrievability(elapsedDays: 0, stability: 5), 1.0, accuracy: 0.0001)
    }

    func testRetrievabilityFallsAsTimePasses() {
        let day1 = fsrs.retrievability(elapsedDays: 1, stability: 10)
        let day10 = fsrs.retrievability(elapsedDays: 10, stability: 10)
        let day100 = fsrs.retrievability(elapsedDays: 100, stability: 10)
        XCTAssertGreaterThan(day1, day10)
        XCTAssertGreaterThan(day10, day100)
        XCTAssertGreaterThan(day100, 0)
    }

    func testMoreStableMemoriesDecaySlower() {
        let weak = fsrs.retrievability(elapsedDays: 30, stability: 10)
        let strong = fsrs.retrievability(elapsedDays: 30, stability: 100)
        XCTAssertGreaterThan(strong, weak)
    }

    // MARK: - Retention target drives interval

    func testIntervalEqualsStabilityAtNinetyPercentRetention() {
        let scheduler = FSRSScheduler(desiredRetention: 0.9)
        XCTAssertEqual(scheduler.interval(forStability: 25), 25, accuracy: 0.01,
                       "asking for 90% should return exactly the stability")
    }

    func testHigherRetentionMeansShorterIntervals() {
        let relaxed = FSRSScheduler(desiredRetention: 0.80).interval(forStability: 50)
        let strict = FSRSScheduler(desiredRetention: 0.95).interval(forStability: 50)
        XCTAssertGreaterThan(relaxed, strict,
                             "wanting to remember more must mean reviewing sooner")
    }

    func testIntervalIsCappedByMaximum() {
        let scheduler = FSRSScheduler(desiredRetention: 0.7, maximumInterval: 365)
        XCTAssertLessThanOrEqual(scheduler.interval(forStability: 100_000), 365)
    }

    // MARK: - First review

    func testInitialStabilityRisesWithGrade() {
        let again = fsrs.initialState(grade: .again).stability
        let hard = fsrs.initialState(grade: .hard).stability
        let good = fsrs.initialState(grade: .good).stability
        let easy = fsrs.initialState(grade: .easy).stability
        XCTAssertLessThan(again, hard)
        XCTAssertLessThan(hard, good)
        XCTAssertLessThan(good, easy)
    }

    func testInitialDifficultyIsHigherForWorseGrades() {
        XCTAssertGreaterThan(fsrs.initialState(grade: .again).difficulty,
                             fsrs.initialState(grade: .easy).difficulty)
    }

    func testDifficultyStaysInRange() {
        for grade in ReviewGrade.allCases {
            let d = fsrs.initialState(grade: grade).difficulty
            XCTAssertGreaterThanOrEqual(d, 1)
            XCTAssertLessThanOrEqual(d, 10)
        }
    }

    // MARK: - Later reviews

    func testSuccessfulReviewIncreasesStability() {
        let state = MemoryState(stability: 10, difficulty: 5)
        let next = fsrs.nextState(state, grade: .good, elapsedDays: 10)
        XCTAssertGreaterThan(next.stability, state.stability)
    }

    func testForgettingNeverIncreasesStability() {
        let state = MemoryState(stability: 40, difficulty: 5)
        let next = fsrs.nextState(state, grade: .again, elapsedDays: 40)
        XCTAssertLessThanOrEqual(next.stability, state.stability,
                                 "failing a card must not make the memory stronger")
    }

    func testEasyGrowsStabilityMoreThanGood() {
        let state = MemoryState(stability: 10, difficulty: 5)
        let good = fsrs.nextState(state, grade: .good, elapsedDays: 10).stability
        let easy = fsrs.nextState(state, grade: .easy, elapsedDays: 10).stability
        XCTAssertGreaterThan(easy, good)
    }

    func testHardGrowsStabilityLessThanGood() {
        let state = MemoryState(stability: 10, difficulty: 5)
        let hard = fsrs.nextState(state, grade: .hard, elapsedDays: 10).stability
        let good = fsrs.nextState(state, grade: .good, elapsedDays: 10).stability
        XCTAssertLessThan(hard, good)
    }

    /// The spacing effect: a review that was nearly forgotten teaches more than one done
    /// straight away. This is the property SM-2 misses entirely.
    func testReviewingLaterGrowsStabilityMoreThanReviewingEarly() {
        let state = MemoryState(stability: 20, difficulty: 5)
        let early = fsrs.nextState(state, grade: .good, elapsedDays: 1).stability
        let onTime = fsrs.nextState(state, grade: .good, elapsedDays: 20).stability
        XCTAssertGreaterThan(onTime, early,
                             "reviewing at the edge of forgetting should teach more")
    }

    func testHarderCardsGainStabilityMoreSlowly() {
        let easyCard = MemoryState(stability: 10, difficulty: 2)
        let hardCard = MemoryState(stability: 10, difficulty: 9)
        let easyGain = fsrs.nextState(easyCard, grade: .good, elapsedDays: 10).stability
        let hardGain = fsrs.nextState(hardCard, grade: .good, elapsedDays: 10).stability
        XCTAssertGreaterThan(easyGain, hardGain)
    }

    func testGoodAnswersPullDifficultyDownAndAgainPushesItUp() {
        let state = MemoryState(stability: 10, difficulty: 5)
        XCTAssertLessThan(fsrs.nextState(state, grade: .easy, elapsedDays: 10).difficulty, 5)
        XCTAssertGreaterThan(fsrs.nextState(state, grade: .again, elapsedDays: 10).difficulty, 5)
    }

    func testStabilityNeverGoesToZero() {
        var state = MemoryState(stability: 0.5, difficulty: 10)
        for _ in 0..<20 {
            state = fsrs.nextState(state, grade: .again, elapsedDays: 1)
            XCTAssertGreaterThan(state.stability, 0)
        }
    }
}

final class FSRSCardSchedulerTests: XCTestCase {

    let scheduler = FSRSCardScheduler()
    var deterministic = SeededGenerator(seed: 99)

    private func newCard(now: Date) -> SchedulingState { .new(now: now) }

    func testNewCardGoesThroughLearningSteps() {
        let now = Date()
        let out = scheduler.review(newCard(now: now), grade: .good, now: now, using: &deterministic)
        XCTAssertEqual(out.state.phase, .learning(step: 1))
        XCTAssertEqual(out.state.dueDate.timeIntervalSince(now), 600, accuracy: 1)
    }

    func testNewCardAnsweredEasyGraduatesUsingTheMemoryModel() {
        let now = Date()
        let out = scheduler.review(newCard(now: now), grade: .easy, now: now, using: &deterministic)
        XCTAssertEqual(out.state.phase, .review)
        XCTAssertNotNil(out.state.memory)
        XCTAssertGreaterThan(out.state.intervalDays, 1)
    }

    func testMemoryStateIsRecordedFromTheFirstAnswer() {
        let now = Date()
        let out = scheduler.review(newCard(now: now), grade: .good, now: now, using: &deterministic)
        XCTAssertNotNil(out.state.memory, "even a learning-step answer is evidence")
        XCTAssertGreaterThan(out.state.memory?.stability ?? 0, 0)
    }

    func testIntervalsGrowAcrossSuccessfulReviews() {
        var state = newCard(now: Date())
        var now = Date()
        var previous = 0.0
        for _ in 0..<6 {
            state = scheduler.review(state, grade: .good, now: now, using: &deterministic).state
            now = state.dueDate
            if state.phase == .review {
                XCTAssertGreaterThan(state.intervalDays, previous)
                previous = state.intervalDays
            }
        }
        XCTAssertGreaterThan(previous, 5)
    }

    func testLapseSendsCardToRelearningAndCountsIt() {
        var state = newCard(now: Date())
        state = scheduler.review(state, grade: .easy, now: Date(), using: &deterministic).state
        let out = scheduler.review(state, grade: .again, now: state.dueDate, using: &deterministic)
        XCTAssertEqual(out.state.phase, .relearning(step: 0))
        XCTAssertEqual(out.state.lapses, 1)
        XCTAssertEqual(out.state.repetitions, 0)
    }

    // MARK: - Leeches

    func testCardBecomesALeechAtTheThreshold() {
        var state = SchedulingState.new()
        state.phase = .review
        state.lapses = 7
        state.memory = MemoryState(stability: 5, difficulty: 5)

        let out = scheduler.review(state, grade: .again, now: Date(), using: &deterministic)
        XCTAssertEqual(out.state.lapses, 8)
        XCTAssertTrue(out.becameLeech, "eight lapses is Anki's default leech threshold")
        XCTAssertTrue(out.shouldSuspend, "the default action is to suspend")
    }

    func testNotALeechBeforeTheThreshold() {
        var state = SchedulingState.new()
        state.phase = .review
        state.lapses = 3
        state.memory = MemoryState(stability: 5, difficulty: 5)
        let out = scheduler.review(state, grade: .again, now: Date(), using: &deterministic)
        XCTAssertFalse(out.becameLeech)
    }

    func testLeechIsFlaggedAgainEveryHalfThreshold() {
        func lapsing(from lapses: Int) -> Bool {
            var state = SchedulingState.new()
            state.phase = .review
            state.lapses = lapses
            state.memory = MemoryState(stability: 5, difficulty: 5)
            var rng = SeededGenerator(seed: 1)
            return scheduler.review(state, grade: .again, now: Date(), using: &rng).becameLeech
        }
        XCTAssertTrue(lapsing(from: 7), "8th lapse")
        XCTAssertFalse(lapsing(from: 8), "9th")
        XCTAssertTrue(lapsing(from: 11), "12th — threshold plus half")
        XCTAssertTrue(lapsing(from: 15), "16th")
    }

    func testFlagOnlyLeechActionDoesNotSuspend() {
        var settings = RetentionSettings.default
        settings.leechAction = .flagOnly
        let lenient = FSRSCardScheduler(settings: settings)

        var state = SchedulingState.new()
        state.phase = .review
        state.lapses = 7
        state.memory = MemoryState(stability: 5, difficulty: 5)

        var rng = SeededGenerator(seed: 2)
        let out = lenient.review(state, grade: .again, now: Date(), using: &rng)
        XCTAssertTrue(out.becameLeech)
        XCTAssertFalse(out.shouldSuspend)
    }

    // MARK: - Retention setting

    func testLowerRetentionProducesLongerIntervals() {
        var strictSettings = RetentionSettings.default
        strictSettings.desiredRetention = 0.95
        strictSettings.intervalFuzzFactor = 0
        var relaxedSettings = RetentionSettings.default
        relaxedSettings.desiredRetention = 0.80
        relaxedSettings.intervalFuzzFactor = 0

        var state = SchedulingState.new()
        state.phase = .review
        state.memory = MemoryState(stability: 30, difficulty: 5)
        state.lastReviewedAt = Date().addingTimeInterval(-30 * 86_400)

        var r1 = SeededGenerator(seed: 3), r2 = SeededGenerator(seed: 3)
        let strict = FSRSCardScheduler(settings: strictSettings)
            .review(state, grade: .good, now: Date(), using: &r1).state.intervalDays
        let relaxed = FSRSCardScheduler(settings: relaxedSettings)
            .review(state, grade: .good, now: Date(), using: &r2).state.intervalDays

        XCTAssertGreaterThan(relaxed, strict,
                             "accepting more forgetting should mean fewer, longer-spaced reviews")
    }
}

final class SuspensionAndLearnAheadTests: XCTestCase {

    private func makeDeck() -> Deck { Deck(profileID: UUID(), name: "D") }

    func testSuspendedCardsAreExcludedFromTheQueue() {
        let deck = makeDeck()
        var suspended = Card(deckID: deck.id, profileID: deck.profileID)
        suspended.scheduling.isSuspended = true
        let normal = Card(deckID: deck.id, profileID: deck.profileID)

        let queue = ReviewQueue(deck: deck).build(from: [suspended, normal], now: Date())
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.id, normal.id)
    }

    func testLearningCardIsPulledForwardWhenNothingElseIsDue() {
        let deck = makeDeck()
        let now = Date()
        var soon = Card(deckID: deck.id, profileID: deck.profileID)
        soon.scheduling.phase = .learning(step: 0)
        soon.scheduling.dueDate = now.addingTimeInterval(300)   // five minutes out

        let queue = ReviewQueue(deck: deck).build(from: [soon], now: now)
        XCTAssertEqual(queue.count, 1, "a card due in five minutes should not end the session")
    }

    func testLearningCardBeyondTheLimitIsNotPulledForward() {
        let deck = makeDeck()
        let now = Date()
        var later = Card(deckID: deck.id, profileID: deck.profileID)
        later.scheduling.phase = .learning(step: 0)
        later.scheduling.dueDate = now.addingTimeInterval(3_600)   // an hour out

        let queue = ReviewQueue(deck: deck).build(from: [later], now: now)
        XCTAssertTrue(queue.isEmpty)
    }

    func testDueCardsTakePrecedenceOverPullingLearningForward() {
        let deck = makeDeck()
        let now = Date()
        var due = Card(deckID: deck.id, profileID: deck.profileID)
        due.scheduling.phase = .review
        due.scheduling.dueDate = now.addingTimeInterval(-60)
        var ahead = Card(deckID: deck.id, profileID: deck.profileID)
        ahead.scheduling.phase = .learning(step: 0)
        ahead.scheduling.dueDate = now.addingTimeInterval(300)

        let queue = ReviewQueue(deck: deck).build(from: [due, ahead], now: now)
        XCTAssertEqual(queue.first?.id, due.id, "don't show a card early while one is overdue")
    }
}

final class MemoryEstimateTests: XCTestCase {

    let estimator = MemoryEstimator()

    private func studied(stability: Double, daysAgo: Double, now: Date) -> SchedulingState {
        var state = SchedulingState.new(now: now)
        state.phase = .review
        state.memory = MemoryState(stability: stability, difficulty: 5)
        state.lastReviewedAt = now.addingTimeInterval(-daysAgo * 86_400)
        return state
    }

    func testAFreshlyStudiedCardIsAlmostFullyRemembered() {
        let now = Date()
        let r = estimator.recallProbability(for: studied(stability: 10, daysAgo: 0, now: now), now: now)
        XCTAssertEqual(r ?? 0, 1.0, accuracy: 0.01)
    }

    func testRecallIsNinetyPercentAtExactlyOneStability() {
        let now = Date()
        let r = estimator.recallProbability(for: studied(stability: 10, daysAgo: 10, now: now), now: now)
        XCTAssertEqual(r ?? 0, 0.9, accuracy: 0.01)
    }

    func testRecallFallsAsTimePasses() {
        let now = Date()
        let recent = estimator.recallProbability(for: studied(stability: 10, daysAgo: 1, now: now), now: now) ?? 0
        let old = estimator.recallProbability(for: studied(stability: 10, daysAgo: 60, now: now), now: now) ?? 0
        XCTAssertGreaterThan(recent, old)
    }

    func testStrongerMemoriesDecaySlower() {
        let now = Date()
        let weak = estimator.recallProbability(for: studied(stability: 5, daysAgo: 30, now: now), now: now) ?? 0
        let strong = estimator.recallProbability(for: studied(stability: 200, daysAgo: 30, now: now), now: now) ?? 0
        XCTAssertGreaterThan(strong, weak)
    }

    func testUnstudiedCardsHaveNoEstimateAndAreCountedSeparately() {
        let now = Date()
        XCTAssertNil(estimator.recallProbability(for: .new(now: now), now: now))

        let estimate = estimator.estimate(for: [.new(now: now), studied(stability: 10, daysAgo: 0, now: now)], now: now)
        XCTAssertEqual(estimate.consideredCards, 1)
        XCTAssertEqual(estimate.unseenCards, 1)
        XCTAssertEqual(estimate.recallProbability, 1.0, accuracy: 0.01,
                       "a never-seen card must not drag the figure down")
    }

    func testDeckEstimateIsTheAverageAcrossCards() {
        let now = Date()
        let states = [
            studied(stability: 10, daysAgo: 10, now: now),   // 0.90
            studied(stability: 10, daysAgo: 10, now: now),   // 0.90
        ]
        XCTAssertEqual(estimator.estimate(for: states, now: now).recallProbability,
                       0.9, accuracy: 0.01)
    }

    func testEmptyDeckReportsNothingRatherThanZeroPercent() {
        let estimate = estimator.estimate(for: [])
        XCTAssertTrue(estimate.isEmpty)
        XCTAssertEqual(estimate.summary, "Not studied yet")
    }

    func testSummaryDescribesTheNumber() {
        XCTAssertEqual(MemoryEstimate(recallProbability: 0.95, consideredCards: 1, unseenCards: 0).summary, "Solid")
        XCTAssertEqual(MemoryEstimate(recallProbability: 0.60, consideredCards: 1, unseenCards: 0).summary, "Slipping")
        XCTAssertEqual(MemoryEstimate(recallProbability: 0.10, consideredCards: 1, unseenCards: 0).summary, "Mostly forgotten")
    }

    func testSuspendedCardsStillCountTowardWhatYouHaveForgotten() {
        let now = Date()
        var suspended = studied(stability: 2, daysAgo: 90, now: now)
        suspended.isSuspended = true
        let estimate = estimator.estimate(for: [suspended], now: now)
        XCTAssertEqual(estimate.consideredCards, 1)
        XCTAssertLessThan(estimate.recallProbability, 0.5)
    }
}
