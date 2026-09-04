import Foundation

/// What to do with a card you keep forgetting.
public enum LeechAction: String, Codable, Sendable, CaseIterable {
    /// Take it out of the rotation until you rewrite it.
    case suspend
    /// Flag it but keep showing it.
    case flagOnly
}

/// Settings that decide how hard the app works to stop you forgetting.
public struct RetentionSettings: Codable, Sendable, Equatable {
    /// Probability of recall you are aiming for at review time. Higher means more reviews
    /// and less forgetting; lower means fewer reviews and more. Anki's default is 0.90.
    public var desiredRetention: Double
    public var learningSteps: [TimeInterval]
    public var relearningSteps: [TimeInterval]
    public var maximumInterval: Double
    /// Lapses before a card is called a leech. Anki's default is 8.
    public var leechThreshold: Int
    public var leechAction: LeechAction
    /// Learning cards may be shown this early if nothing else is waiting, so a short step
    /// doesn't strand you staring at a timer. Anki uses 20 minutes.
    public var learnAheadLimit: TimeInterval
    public var newCardsPerDay: Int
    public var maximumReviewsPerDay: Int
    /// Random spread applied to intervals so cards learned together don't stay clumped.
    public var intervalFuzzFactor: Double

    public static let `default` = RetentionSettings(
        desiredRetention: 0.90,
        learningSteps: [60, 600],
        relearningSteps: [600],
        maximumInterval: 36_500,
        leechThreshold: 8,
        leechAction: .suspend,
        learnAheadLimit: 1_200,
        newCardsPerDay: 20,
        maximumReviewsPerDay: 200,
        intervalFuzzFactor: 0.05
    )

    public init(
        desiredRetention: Double, learningSteps: [TimeInterval], relearningSteps: [TimeInterval],
        maximumInterval: Double, leechThreshold: Int, leechAction: LeechAction,
        learnAheadLimit: TimeInterval, newCardsPerDay: Int, maximumReviewsPerDay: Int,
        intervalFuzzFactor: Double
    ) {
        self.desiredRetention = desiredRetention
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.maximumInterval = maximumInterval
        self.leechThreshold = leechThreshold
        self.leechAction = leechAction
        self.learnAheadLimit = learnAheadLimit
        self.newCardsPerDay = newCardsPerDay
        self.maximumReviewsPerDay = maximumReviewsPerDay
        self.intervalFuzzFactor = intervalFuzzFactor
    }
}

/// What the app should do as a consequence of a review, beyond rescheduling.
public struct ReviewOutcome: Sendable, Equatable {
    public var state: SchedulingState
    /// True when this review pushed the card over the leech threshold.
    public var becameLeech: Bool
    /// True when the card should be taken out of rotation.
    public var shouldSuspend: Bool
}

private let secondsPerDay: TimeInterval = 86_400

/// Schedules cards with FSRS, wrapped in the short learning steps Anki keeps for brand-new
/// and just-failed cards.
///
/// FSRS decides the long intervals; the steps exist because a card seen for the first time
/// needs to be seen again in minutes, not days, and no memory model can conjure that from
/// a single data point.
public struct FSRSCardScheduler: Sendable {
    public let settings: RetentionSettings
    public let fsrs: FSRSScheduler

    public init(settings: RetentionSettings = .default) {
        self.settings = settings
        self.fsrs = FSRSScheduler(
            desiredRetention: settings.desiredRetention,
            maximumInterval: settings.maximumInterval
        )
    }

    public func review(_ state: SchedulingState, grade: ReviewGrade, now: Date = Date()) -> ReviewOutcome {
        var rng = SystemRandomNumberGenerator()
        return review(state, grade: grade, now: now, using: &rng)
    }

    public func review<G: RandomNumberGenerator>(
        _ state: SchedulingState, grade: ReviewGrade, now: Date, using rng: inout G
    ) -> ReviewOutcome {
        var next = state

        let elapsedDays = state.lastReviewedAt.map {
            max(0, now.timeIntervalSince($0) / secondsPerDay)
        } ?? 0

        // The memory model is updated on every answer, including during learning steps:
        // those answers are evidence too.
        next.memory = fsrs.nextState(state.memory, grade: grade, elapsedDays: elapsedDays)
        next.lastReviewedAt = now

        var becameLeech = false

        switch state.phase {
        case .new:
            applyLearningStep(&next, currentStep: 0, steps: settings.learningSteps, grade: grade, now: now, using: &rng)
        case .learning(let step):
            applyLearningStep(&next, currentStep: step, steps: settings.learningSteps, grade: grade, now: now, using: &rng)
        case .review:
            if grade == .again {
                next.lapses += 1
                next.repetitions = 0
                becameLeech = isNewLeech(lapses: next.lapses)
                if let first = settings.relearningSteps.first {
                    next.phase = .relearning(step: 0)
                    next.dueDate = now.addingTimeInterval(first)
                    next.intervalDays = fsrs.interval(forStability: next.memory?.stability ?? 1)
                } else {
                    next.phase = .review
                    scheduleFromMemory(&next, now: now, using: &rng)
                }
            } else {
                next.repetitions += 1
                next.phase = .review
                scheduleFromMemory(&next, now: now, using: &rng)
            }
        case .relearning(let step):
            applyRelearningStep(&next, currentStep: step, grade: grade, now: now, using: &rng)
        }

        let shouldSuspend = becameLeech && settings.leechAction == .suspend
        return ReviewOutcome(state: next, becameLeech: becameLeech, shouldSuspend: shouldSuspend)
    }

    /// A card is flagged the first time it hits the threshold, then again every half
    /// threshold after that — the same cadence Anki uses, so warnings don't become noise.
    private func isNewLeech(lapses: Int) -> Bool {
        let threshold = settings.leechThreshold
        guard threshold > 0, lapses >= threshold else { return false }
        if lapses == threshold { return true }
        let step = max(1, threshold / 2)
        return (lapses - threshold) % step == 0
    }

    // MARK: - Steps

    private func applyLearningStep<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, currentStep: Int, steps: [TimeInterval],
        grade: ReviewGrade, now: Date, using rng: inout G
    ) {
        guard !steps.isEmpty else {
            state.phase = .review
            state.repetitions += 1
            scheduleFromMemory(&state, now: now, using: &rng)
            return
        }

        switch grade {
        case .again:
            state.phase = .learning(step: 0)
            state.repetitions = 0
            state.dueDate = now.addingTimeInterval(steps[0])
        case .hard:
            let step = min(currentStep, steps.count - 1)
            state.phase = .learning(step: step)
            state.dueDate = now.addingTimeInterval(steps[step])
        case .good:
            let nextStep = currentStep + 1
            if nextStep >= steps.count {
                state.phase = .review
                state.repetitions += 1
                scheduleFromMemory(&state, now: now, using: &rng)
            } else {
                state.phase = .learning(step: nextStep)
                state.dueDate = now.addingTimeInterval(steps[nextStep])
            }
        case .easy:
            state.phase = .review
            state.repetitions += 1
            scheduleFromMemory(&state, now: now, using: &rng)
        }
    }

    private func applyRelearningStep<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, currentStep: Int,
        grade: ReviewGrade, now: Date, using rng: inout G
    ) {
        let steps = settings.relearningSteps
        guard !steps.isEmpty else {
            state.phase = .review
            scheduleFromMemory(&state, now: now, using: &rng)
            return
        }

        switch grade {
        case .again:
            state.phase = .relearning(step: 0)
            state.dueDate = now.addingTimeInterval(steps[0])
        case .hard:
            let step = min(currentStep, steps.count - 1)
            state.phase = .relearning(step: step)
            state.dueDate = now.addingTimeInterval(steps[step])
        case .good, .easy:
            let nextStep = currentStep + 1
            if grade == .easy || nextStep >= steps.count {
                state.phase = .review
                state.repetitions += 1
                scheduleFromMemory(&state, now: now, using: &rng)
            } else {
                state.phase = .relearning(step: nextStep)
                state.dueDate = now.addingTimeInterval(steps[nextStep])
            }
        }
    }

    /// Turns the memory model's stability into an actual due date.
    private func scheduleFromMemory<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, now: Date, using rng: inout G
    ) {
        let stability = state.memory?.stability ?? 1
        let days = fuzz(fsrs.interval(forStability: stability), using: &rng)
        state.intervalDays = days
        state.dueDate = now.addingTimeInterval(days * secondsPerDay)
    }

    private func fuzz<G: RandomNumberGenerator>(_ days: Double, using rng: inout G) -> Double {
        guard settings.intervalFuzzFactor > 0, days >= 2.5 else { return days }
        let delta = days * settings.intervalFuzzFactor
        let low = max(1, days - delta)
        let high = min(settings.maximumInterval, days + delta)
        guard high > low else { return days }
        return Double.random(in: low...high, using: &rng)
    }
}
