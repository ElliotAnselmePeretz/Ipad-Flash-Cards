import Foundation

// A dependency-free mirror of the XCTest suite in Tests/, so the scheduler can be
// verified from the command line on a machine that has only the Swift toolchain
// (no Xcode, therefore no XCTest and no working SwiftPM). Once Xcode is installed,
// Tests/FlashcardsCoreTests is the real suite; this stays useful for CI.

var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ label: String, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    if !condition { failures.append("\(label)  (line \(line))") }
}

func expectClose(_ actual: Double, _ expected: Double, _ label: String,
                 accuracy: Double = 0.0001, line: UInt = #line) {
    checks += 1
    if abs(actual - expected) > accuracy {
        failures.append("\(label): expected \(expected), got \(actual)  (line \(line))")
    }
}

/// SplitMix64, so simulations are reproducible across runs and machines.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func section(_ name: String) { print("\n\u{001B}[1m\(name)\u{001B}[0m") }

// MARK: - Fixtures

var deterministic = SchedulerConfig.default
deterministic.intervalFuzzFactor = 0

let scheduler = SM2Scheduler(config: deterministic)
let t0 = Date(timeIntervalSince1970: 1_700_000_000)
func minutes(_ n: Double) -> TimeInterval { n * 60 }
func days(_ n: Double) -> TimeInterval { n * 86_400 }

func graduated(intervalDays: Double = 10, ease: Double = 2.5) -> SchedulingState {
    SchedulingState(phase: .review, intervalDays: intervalDays, easeFactor: ease,
                    repetitions: 3, lapses: 0, dueDate: t0, lastReviewedAt: nil)
}

// MARK: - Learning phase

section("Learning phase")
do {
    let s = scheduler.review(.new(config: deterministic, now: t0), grade: .good, now: t0)
    expect(s.phase == .learning(step: 1), "new + good -> learning step 1")
    expectClose(s.dueDate.timeIntervalSince(t0), minutes(10), "new + good due in 10 min")
    expectClose(s.easeFactor, 2.5, "ease unchanged during learning")

    let easy = scheduler.review(.new(config: deterministic, now: t0), grade: .easy, now: t0)
    expect(easy.phase == .review, "new + easy graduates immediately")
    expectClose(easy.intervalDays, 4, "new + easy uses the 4-day easy interval")

    var g = SchedulingState.new(config: deterministic, now: t0)
    g = scheduler.review(g, grade: .good, now: t0)
    g = scheduler.review(g, grade: .good, now: t0)
    expect(g.phase == .review, "two goods graduate the card")
    expectClose(g.intervalDays, 1, "graduating interval is 1 day")
    expect(g.repetitions == 1, "graduating counts as one repetition")

    var again = SchedulingState.new(config: deterministic, now: t0)
    again = scheduler.review(again, grade: .good, now: t0)
    again = scheduler.review(again, grade: .again, now: t0)
    expect(again.phase == .learning(step: 0), "again resets to first learning step")
    expectClose(again.dueDate.timeIntervalSince(t0), minutes(1), "reset card due in 1 min")

    var hard = SchedulingState.new(config: deterministic, now: t0)
    hard = scheduler.review(hard, grade: .good, now: t0)
    hard = scheduler.review(hard, grade: .hard, now: t0)
    expect(hard.phase == .learning(step: 1), "hard repeats the current learning step")
}

// MARK: - Review phase

section("Review phase")
do {
    let good = scheduler.review(graduated(), grade: .good, now: t0)
    expectClose(good.intervalDays, 25, "good multiplies interval by ease (10 x 2.5)")
    expectClose(good.easeFactor, 2.5, "good leaves ease alone")
    expect(good.repetitions == 4, "good increments repetitions")

    let hard = scheduler.review(graduated(), grade: .hard, now: t0)
    expectClose(hard.intervalDays, 12, "hard uses 1.2x multiplier")
    expectClose(hard.easeFactor, 2.35, "hard drops ease by 0.15")

    let easy = scheduler.review(graduated(), grade: .easy, now: t0)
    expectClose(easy.easeFactor, 2.65, "easy raises ease by 0.15")
    expectClose(easy.intervalDays, 34.45, "easy applies ease and the 1.3 bonus")

    var s = graduated(intervalDays: 1)
    var last = s.intervalDays
    var growthHeld = true
    for _ in 0..<6 {
        s = scheduler.review(s, grade: .good, now: s.dueDate)
        if s.intervalDays <= last { growthHeld = false }
        last = s.intervalDays
    }
    expect(growthHeld, "each success spaces the card further out")
    expect(s.intervalDays > 100, "six good answers reach months, got \(Int(s.intervalDays))d")
}

// MARK: - Lapses

section("Lapses and relearning")
do {
    let lapsed = scheduler.review(graduated(intervalDays: 30), grade: .again, now: t0)
    expect(lapsed.phase == .relearning(step: 0), "again sends a review card to relearning")
    expect(lapsed.lapses == 1, "lapse counter increments")
    expect(lapsed.repetitions == 0, "lapse resets repetitions")
    expectClose(lapsed.easeFactor, 2.3, "lapse drops ease by 0.20")
    expectClose(lapsed.intervalDays, 1, "lapse resets the interval to the floor")
    expectClose(lapsed.dueDate.timeIntervalSince(t0), minutes(10), "relearning step is 10 min")

    let recovered = scheduler.review(lapsed, grade: .good, now: t0)
    expect(recovered.phase == .review, "good after relearning returns to review")
    expectClose(recovered.intervalDays, 1, "recovered card restarts at 1 day")

    var floor = graduated(ease: 1.4)
    for _ in 0..<10 {
        floor = scheduler.review(floor, grade: .again, now: floor.dueDate)
        floor = scheduler.review(floor, grade: .good, now: floor.dueDate)
    }
    expect(floor.easeFactor >= deterministic.minimumEase, "ease never falls below 1.3")

    let capped = scheduler.review(graduated(intervalDays: 30_000), grade: .easy, now: t0)
    expect(capped.intervalDays <= deterministic.maximumInterval, "interval respects the ceiling")
}

// MARK: - Fuzz

section("Interval fuzz")
do {
    let fuzzy = SM2Scheduler(config: .default)
    var seen = Set<Double>()
    var inBounds = true
    for _ in 0..<200 {
        let s = fuzzy.review(graduated(), grade: .good, now: t0)
        if s.intervalDays < 25 * 0.95 - 0.0001 || s.intervalDays > 25 * 1.05 + 0.0001 { inBounds = false }
        seen.insert(s.intervalDays)
    }
    expect(inBounds, "fuzzed intervals stay within +/-5%")
    expect(seen.count > 1, "fuzz actually varies the interval")

    let short = fuzzy.review(graduated(intervalDays: 1), grade: .hard, now: t0)
    expectClose(short.intervalDays, 1.2, "intervals under 2 days are left exact")
}

// MARK: - Queue

section("Review queue")
do {
    let profileID = UUID()
    let deck = Deck(profileID: profileID, name: "Test", newCardsPerDay: 20, maximumReviewsPerDay: 200)

    func card(_ phase: LearningPhase, due: Date, created: Date = t0, deckID: UUID? = nil, profile: UUID? = nil) -> Card {
        var state = SchedulingState.new(now: t0)
        state.phase = phase
        state.dueDate = due
        state.intervalDays = phase == .review ? 5 : 0
        return Card(deckID: deckID ?? deck.id, profileID: profile ?? profileID,
                    scheduling: state, createdAt: created)
    }

    let ordered = ReviewQueue(deck: deck).build(from: [
        card(.new, due: t0),
        card(.review, due: t0.addingTimeInterval(-100)),
        card(.learning(step: 0), due: t0.addingTimeInterval(-10)),
    ], now: t0)
    expect(ordered.count == 3, "all three due cards are queued")
    expect(ordered.first?.scheduling.phase == .learning(step: 0), "learning cards come first")
    expect(ordered.last?.scheduling.phase == .new, "new cards come last")

    let future = ReviewQueue(deck: deck).build(from: [
        card(.review, due: t0.addingTimeInterval(86_400)),
        card(.learning(step: 0), due: t0.addingTimeInterval(600)),
    ], now: t0)
    expect(future.isEmpty, "cards due in the future are excluded")

    // Copy the deck so the id (and therefore the cards' deckID) is preserved.
    var limited = deck; limited.newCardsPerDay = 3
    let manyNew = (0..<10).map { i in card(.new, due: t0, created: t0.addingTimeInterval(Double(i))) }
    expect(ReviewQueue(deck: limited).build(from: manyNew, now: t0).count == 3, "new-card daily limit is respected")

    var partial = deck; partial.newCardsPerDay = 5
    expect(ReviewQueue(deck: partial, newCardsStudiedToday: 4).build(from: manyNew, now: t0).count == 1,
           "new limit accounts for cards already studied today")

    var capped = deck; capped.maximumReviewsPerDay = 2
    let reviews = (0..<5).map { i in card(.review, due: t0.addingTimeInterval(Double(-i))) }
    let learning = (0..<3).map { _ in card(.learning(step: 0), due: t0) }
    let mixed = ReviewQueue(deck: capped).build(from: reviews + learning, now: t0)
    expect(mixed.filter { $0.scheduling.phase == .review }.count == 2, "review daily cap is respected")
    expect(mixed.count == 5, "learning cards bypass the review cap")

    let mine = card(.new, due: t0)
    let theirs = card(.new, due: t0, profile: UUID())
    let elsewhere = card(.new, due: t0, deckID: UUID())
    let scoped = ReviewQueue(deck: deck).build(from: [mine, theirs, elsewhere], now: t0)
    expect(scoped.map(\.id) == [mine.id], "other profiles and decks are excluded")

    var deleted = card(.new, due: t0)
    deleted.deletedAt = t0
    expect(ReviewQueue(deck: deck).build(from: [deleted], now: t0).isEmpty, "soft-deleted cards are excluded")

    let counts = ReviewQueue(deck: deck).counts(from: [
        card(.new, due: t0), card(.new, due: t0),
        card(.review, due: t0), card(.relearning(step: 0), due: t0),
    ], now: t0)
    expect(counts.new == 2 && counts.review == 1 && counts.learning == 1 && counts.total == 4,
           "counts break down by bucket (got new=\(counts.new) review=\(counts.review) learning=\(counts.learning))")

    let recent = card(.review, due: t0.addingTimeInterval(-60))
    let ancient = card(.review, due: t0.addingTimeInterval(-86_400))
    expect(ReviewQueue(deck: deck).build(from: [recent, ancient], now: t0).map(\.id) == [ancient.id, recent.id],
           "most overdue reviews come first")
}

// MARK: - Simulation

section("End-to-end simulation")
do {
    // 200 simulated learners rather than one, so the assertions describe the algorithm's
    // behaviour rather than the luck of a single seed.
    var reviewCounts: [Int] = []
    var finalIntervals: [Double] = []
    var totalLapses = 0
    let oneYear = t0.addingTimeInterval(days(365))

    for seed in 0..<200 {
        var rng = SeededRNG(seed: UInt64(seed) &* 0x9E3779B97F4A7C15 &+ 12345)
        var s = SchedulingState.new(config: deterministic, now: t0)
        var reviewCount = 0
        var clock = t0

        while clock < oneYear && reviewCount < 1000 {
            clock = max(s.dueDate, clock)
            guard clock < oneYear else { break }
            // Slips are common on a card just met, rare on one held for weeks.
            let failureChance = max(0.05, 0.45 / Double(s.repetitions + 1))
            let grade: ReviewGrade = Double.random(in: 0..<1, using: &rng) < failureChance ? .again : .good
            s = scheduler.review(s, grade: grade, now: clock)
            reviewCount += 1
        }
        reviewCounts.append(reviewCount)
        finalIntervals.append(s.intervalDays)
        totalLapses += s.lapses
    }

    let meanReviews = Double(reviewCounts.reduce(0, +)) / 200
    let meanInterval = finalIntervals.reduce(0, +) / 200
    let worstReviews = reviewCounts.max() ?? 0
    print("  200 learners, one year each:")
    print("    reviews per card   mean \(String(format: "%.1f", meanReviews))  worst \(worstReviews)")
    print("    final interval     mean \(Int(meanInterval))d")
    print("    lapses             \(totalLapses) across the cohort")

    expect(totalLapses > 0, "the cohort must actually experience lapses, or the test proves nothing")
    expect(meanReviews < 30, "average card shouldn't need many reviews per year (got \(String(format: "%.1f", meanReviews)))")
    expect(worstReviews < 200, "even the unluckiest learner shouldn't thrash (got \(worstReviews))")
    expect(meanInterval > 20, "average card should end up spaced weeks out (got \(Int(meanInterval))d)")
    expect(finalIntervals.allSatisfy { $0 >= deterministic.minimumInterval }, "no card ends below the interval floor")

    // Sanity check the shape of the curve: a perfect learner should need very few reviews.
    var perfect = SchedulingState.new(config: deterministic, now: t0)
    var perfectCount = 0
    var pClock = t0
    while pClock < oneYear && perfectCount < 1000 {
        pClock = max(perfect.dueDate, pClock)
        guard pClock < oneYear else { break }
        perfect = scheduler.review(perfect, grade: .good, now: pClock)
        perfectCount += 1
    }
    print("  one card, one year, never forgotten -> \(perfectCount) reviews, final interval \(Int(perfect.intervalDays))d")
    expect(perfectCount <= 10, "a never-forgotten card should need a handful of reviews (got \(perfectCount))")
    expect(perfect.intervalDays > 100, "a never-forgotten card should reach months")
}

// MARK: - Report

print("")
if failures.isEmpty {
    print("\u{001B}[32m✓ all \(checks) checks passed\u{001B}[0m")
    exit(0)
} else {
    print("\u{001B}[31m✗ \(failures.count) of \(checks) checks failed\u{001B}[0m")
    for f in failures { print("  - \(f)") }
    exit(1)
}
