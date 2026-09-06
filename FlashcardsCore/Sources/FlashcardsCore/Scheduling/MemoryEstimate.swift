import Foundation

/// How much of a deck you would remember if you were tested right now.
///
/// This is not a guess dressed up as a number. FSRS already models each card's memory as
/// stability and difficulty, and its forgetting curve gives the probability of recalling
/// a card after a given gap. Averaging that probability across a deck's cards *is* the
/// expected fraction you would get right — practice, difficulty and elapsed time are all
/// already inside it.
public struct MemoryEstimate: Sendable, Equatable {
    /// Expected proportion recalled right now, 0...1.
    public var recallProbability: Double
    /// Cards that went into the estimate.
    public var consideredCards: Int
    /// Cards never studied, which are excluded: you cannot forget what you never learned.
    public var unseenCards: Int

    public var percentage: Int { Int((recallProbability * 100).rounded()) }

    public var isEmpty: Bool { consideredCards == 0 }

    public init(recallProbability: Double, consideredCards: Int, unseenCards: Int) {
        self.recallProbability = recallProbability
        self.consideredCards = consideredCards
        self.unseenCards = unseenCards
    }

    /// A plain-language reading, so the bar means something without a manual.
    public var summary: String {
        if isEmpty { return "Not studied yet" }
        switch percentage {
        case 90...: return "Solid"
        case 75..<90: return "Holding"
        case 55..<75: return "Slipping"
        case 30..<55: return "Fading"
        default: return "Mostly forgotten"
        }
    }
}

public struct MemoryEstimator: Sendable {
    public let fsrs: FSRSScheduler

    public init(fsrs: FSRSScheduler = FSRSScheduler()) {
        self.fsrs = fsrs
    }

    /// Estimated recall for one card at `now`.
    public func recallProbability(for state: SchedulingState, now: Date = Date()) -> Double? {
        guard let memory = state.memory, let last = state.lastReviewedAt else { return nil }
        let elapsedDays = max(0, now.timeIntervalSince(last) / 86_400)
        return fsrs.retrievability(elapsedDays: elapsedDays, stability: memory.stability)
    }

    /// Estimated recall across many cards.
    ///
    /// Suspended cards still count: forgetting them is exactly what the number should
    /// reflect. Never-studied cards do not, because they would drag the figure toward zero
    /// for a reason that has nothing to do with forgetting.
    public func estimate(for states: [SchedulingState], now: Date = Date()) -> MemoryEstimate {
        var total = 0.0
        var counted = 0
        var unseen = 0

        for state in states {
            if let r = recallProbability(for: state, now: now) {
                total += r
                counted += 1
            } else {
                unseen += 1
            }
        }

        guard counted > 0 else {
            return MemoryEstimate(recallProbability: 0, consideredCards: 0, unseenCards: unseen)
        }
        return MemoryEstimate(
            recallProbability: total / Double(counted),
            consideredCards: counted,
            unseenCards: unseen
        )
    }
}
