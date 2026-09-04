import Foundation

/// The two numbers FSRS keeps about a memory, in place of SM-2's single ease factor.
public struct MemoryState: Codable, Sendable, Equatable {
    /// Days until recall probability falls to 90%. This *is* the interval at 90% retention.
    public var stability: Double
    /// How hard this card is for you, 1...10. Higher means stability grows more slowly.
    public var difficulty: Double

    public init(stability: Double, difficulty: Double) {
        self.stability = stability
        self.difficulty = difficulty
    }
}

/// FSRS-4.5 — the Free Spaced Repetition Scheduler, which Anki adopted as its default
/// because it predicts forgetting better than SM-2 and so wastes fewer reviews.
///
/// The essential difference: SM-2 multiplies an interval by an ease factor and never asks
/// how likely you are to actually remember. FSRS models memory explicitly — stability and
/// difficulty — and schedules the day your recall probability falls to whatever retention
/// you asked for. Ask for 90% and you get intervals that keep you at roughly 90%.
public struct FSRSScheduler: Sendable {

    /// Fitted defaults from the FSRS project. These are population averages; Anki
    /// re-fits them per user once there is enough review history to learn from.
    public static let defaultWeights: [Double] = [
        0.4, 0.6, 2.4, 5.8,      // w0...w3  initial stability for again/hard/good/easy
        4.93, 0.94,              // w4, w5   initial difficulty
        0.86, 0.01,              // w6, w7   difficulty update and mean reversion
        1.49, 0.14, 0.94,        // w8...w10 stability after a successful review
        2.18, 0.05, 0.34, 1.26,  // w11...w14 stability after forgetting
        0.29, 2.61               // w15, w16 hard penalty, easy bonus
    ]

    /// Fixed in FSRS-4.5: the forgetting curve is a power function, not an exponential.
    /// FACTOR is chosen so that R(S, S) is exactly 0.9.
    private static let decay: Double = -0.5
    private static let factor: Double = 19.0 / 81.0

    public var weights: [Double]
    /// The probability of recall you want at review time. Anki's default is 0.90.
    public var desiredRetention: Double
    public var maximumInterval: Double
    public var minimumInterval: Double

    public init(
        weights: [Double] = FSRSScheduler.defaultWeights,
        desiredRetention: Double = 0.90,
        maximumInterval: Double = 36_500,
        minimumInterval: Double = 1
    ) {
        self.weights = weights.count == 17 ? weights : FSRSScheduler.defaultWeights
        self.desiredRetention = min(max(desiredRetention, 0.70), 0.99)
        self.maximumInterval = maximumInterval
        self.minimumInterval = minimumInterval
    }

    private func w(_ i: Int) -> Double { weights[i] }

    // MARK: - The forgetting curve

    /// Probability of recalling a card `elapsedDays` after its last review.
    public func retrievability(elapsedDays: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + Self.factor * elapsedDays / stability, Self.decay)
    }

    /// The interval at which recall probability equals `desiredRetention`.
    public func interval(forStability stability: Double) -> Double {
        let raw = (stability / Self.factor) * (pow(desiredRetention, 1 / Self.decay) - 1)
        return min(max(raw, minimumInterval), maximumInterval)
    }

    // MARK: - First review

    public func initialState(grade: ReviewGrade) -> MemoryState {
        MemoryState(
            stability: max(w(gradeIndex(grade)), 0.1),
            difficulty: clampDifficulty(initialDifficulty(grade))
        )
    }

    private func gradeIndex(_ grade: ReviewGrade) -> Int {
        switch grade {
        case .again: 0
        case .hard: 1
        case .good: 2
        case .easy: 3
        }
    }

    /// FSRS grades run 1...4; the formulas are written in terms of that.
    private func g(_ grade: ReviewGrade) -> Double { Double(gradeIndex(grade) + 1) }

    private func initialDifficulty(_ grade: ReviewGrade) -> Double {
        w(4) - (g(grade) - 3) * w(5)
    }

    private func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: - Subsequent reviews

    /// Difficulty drifts with each answer and is pulled gently back toward the difficulty
    /// a "good" first answer would have given, so one bad day cannot brand a card forever.
    public func nextDifficulty(_ difficulty: Double, grade: ReviewGrade) -> Double {
        let drifted = difficulty - w(6) * (g(grade) - 3)
        let reverted = w(7) * initialDifficulty(.good) + (1 - w(7)) * drifted
        return clampDifficulty(reverted)
    }

    /// Stability after a successful recall. The gain shrinks as stability and difficulty
    /// rise, and grows the closer you were to forgetting — reviewing early teaches little.
    public func stabilityAfterRecall(
        stability: Double, difficulty: Double, retrievability: Double, grade: ReviewGrade
    ) -> Double {
        let hardPenalty = grade == .hard ? w(15) : 1
        let easyBonus = grade == .easy ? w(16) : 1
        let gain = exp(w(8))
            * (11 - difficulty)
            * pow(stability, -w(9))
            * (exp(w(10) * (1 - retrievability)) - 1)
            * hardPenalty
            * easyBonus
        return stability * (1 + gain)
    }

    /// Stability after forgetting. Never allowed to exceed the stability the card already
    /// had: failing a card must not make it stronger.
    public func stabilityAfterLapse(
        stability: Double, difficulty: Double, retrievability: Double
    ) -> Double {
        let value = w(11)
            * pow(difficulty, -w(12))
            * (pow(stability + 1, w(13)) - 1)
            * exp(w(14) * (1 - retrievability))
        return min(max(value, 0.1), stability)
    }

    /// Apply a grade and return the new memory state.
    public func nextState(_ state: MemoryState?, grade: ReviewGrade, elapsedDays: Double) -> MemoryState {
        guard let state else { return initialState(grade: grade) }

        let r = retrievability(elapsedDays: max(0, elapsedDays), stability: state.stability)
        let difficulty = nextDifficulty(state.difficulty, grade: grade)

        let stability: Double
        if grade == .again {
            stability = stabilityAfterLapse(
                stability: state.stability, difficulty: state.difficulty, retrievability: r
            )
        } else {
            stability = stabilityAfterRecall(
                stability: state.stability, difficulty: state.difficulty,
                retrievability: r, grade: grade
            )
        }

        return MemoryState(stability: max(stability, 0.1), difficulty: difficulty)
    }
}
