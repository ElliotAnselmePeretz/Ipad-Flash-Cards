import Foundation

/// Where a card sits in its learning lifecycle.
public enum LearningPhase: Codable, Sendable, Equatable {
    /// Never studied.
    case new
    /// Working through `learningSteps` at index `step`.
    case learning(step: Int)
    /// Graduated; scheduled in days.
    case review
    /// Was forgotten and is working back through `relearningSteps`.
    case relearning(step: Int)
}

/// Everything the scheduler needs to know about one card, for one profile.
///
/// Deliberately a plain value type with no persistence framework attached, so it can be
/// unit-tested anywhere and stored by whatever the app layer prefers.
public struct SchedulingState: Codable, Sendable, Equatable {
    public var phase: LearningPhase
    /// Current spacing in days. Only meaningful in `.review`.
    public var intervalDays: Double
    /// SM-2 ease factor; higher means the card grows its interval faster.
    public var easeFactor: Double
    /// Consecutive successful reviews since the last lapse.
    public var repetitions: Int
    /// How many times this card has been forgotten after graduating.
    public var lapses: Int
    public var dueDate: Date
    public var lastReviewedAt: Date?

    /// A card that has never been studied, due immediately.
    public static func new(config: SchedulerConfig = .default, now: Date = Date()) -> SchedulingState {
        SchedulingState(
            phase: .new,
            intervalDays: 0,
            easeFactor: config.startingEase,
            repetitions: 0,
            lapses: 0,
            dueDate: now,
            lastReviewedAt: nil
        )
    }

    public init(
        phase: LearningPhase, intervalDays: Double, easeFactor: Double,
        repetitions: Int, lapses: Int, dueDate: Date, lastReviewedAt: Date?
    ) {
        self.phase = phase
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.repetitions = repetitions
        self.lapses = lapses
        self.dueDate = dueDate
        self.lastReviewedAt = lastReviewedAt
    }

    public func isDue(at now: Date) -> Bool { dueDate <= now }

    /// True once the card is being scheduled in days rather than minutes.
    public var isGraduated: Bool {
        switch phase {
        case .review, .relearning: true
        case .new, .learning: false
        }
    }
}
