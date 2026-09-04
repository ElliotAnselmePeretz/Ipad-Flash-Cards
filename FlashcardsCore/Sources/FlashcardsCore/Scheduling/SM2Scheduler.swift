import Foundation

private let secondsPerDay: TimeInterval = 86_400

/// The SM-2 variant Anki used for roughly fifteen years: learning steps for new cards,
/// an ease factor that drifts with your answers, and relearning steps after a lapse.
///
/// Every method is pure — state in, state out — so the whole algorithm is testable
/// without a database, a UI, or a clock.
public struct SM2Scheduler: Sendable {
    public let config: SchedulerConfig

    public init(config: SchedulerConfig = .default) {
        self.config = config
    }

    /// Apply a grade to a card and return its new scheduling state.
    public func review(_ state: SchedulingState, grade: ReviewGrade, now: Date = Date()) -> SchedulingState {
        var rng = SystemRandomNumberGenerator()
        return review(state, grade: grade, now: now, using: &rng)
    }

    /// Seedable variant, so tests can assert on exact intervals despite interval fuzz.
    public func review<G: RandomNumberGenerator>(
        _ state: SchedulingState, grade: ReviewGrade, now: Date, using rng: inout G
    ) -> SchedulingState {
        var next = state
        next.lastReviewedAt = now

        switch state.phase {
        case .new:
            applyLearningStep(to: &next, currentStep: 0, steps: config.learningSteps, grade: grade, now: now, using: &rng)
        case .learning(let step):
            applyLearningStep(to: &next, currentStep: step, steps: config.learningSteps, grade: grade, now: now, using: &rng)
        case .review:
            applyReview(to: &next, grade: grade, now: now, using: &rng)
        case .relearning(let step):
            applyRelearningStep(to: &next, currentStep: step, grade: grade, now: now, using: &rng)
        }

        next.easeFactor = clampEase(next.easeFactor)
        return next
    }

    // MARK: - Learning

    private func applyLearningStep<G: RandomNumberGenerator>(
        to state: inout SchedulingState, currentStep: Int, steps: [TimeInterval],
        grade: ReviewGrade, now: Date, using rng: inout G
    ) {
        // Ease is deliberately left alone while a card is still in learning; Anki does the same.
        guard !steps.isEmpty else {
            graduate(&state, intervalDays: grade == .easy ? config.easyInterval : config.graduatingInterval, now: now, using: &rng)
            return
        }

        switch grade {
        case .again:
            state.phase = .learning(step: 0)
            state.repetitions = 0
            state.dueDate = now.addingTimeInterval(steps[0])
        case .hard:
            // Repeat the current step rather than advancing.
            let step = min(currentStep, steps.count - 1)
            state.phase = .learning(step: step)
            state.dueDate = now.addingTimeInterval(steps[step])
        case .good:
            let nextStep = currentStep + 1
            if nextStep >= steps.count {
                graduate(&state, intervalDays: config.graduatingInterval, now: now, using: &rng)
            } else {
                state.phase = .learning(step: nextStep)
                state.dueDate = now.addingTimeInterval(steps[nextStep])
            }
        case .easy:
            graduate(&state, intervalDays: config.easyInterval, now: now, using: &rng)
        }
    }

    private func graduate<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, intervalDays: Double, now: Date, using rng: inout G
    ) {
        state.phase = .review
        state.repetitions += 1
        setInterval(&state, days: intervalDays, now: now, using: &rng)
    }

    // MARK: - Review

    private func applyReview<G: RandomNumberGenerator>(
        to state: inout SchedulingState, grade: ReviewGrade, now: Date, using rng: inout G
    ) {
        if grade.isFailure {
            lapse(&state, now: now, using: &rng)
            return
        }

        state.repetitions += 1
        let previous = max(state.intervalDays, config.minimumInterval)

        switch grade {
        case .hard:
            state.easeFactor -= config.hardEasePenalty
            setInterval(&state, days: previous * config.hardMultiplier, now: now, using: &rng)
        case .good:
            setInterval(&state, days: previous * state.easeFactor, now: now, using: &rng)
        case .easy:
            state.easeFactor += config.easyEaseBonus
            setInterval(&state, days: previous * clampEase(state.easeFactor) * config.easyBonus, now: now, using: &rng)
        case .again:
            break // handled above
        }
    }

    private func lapse<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, now: Date, using rng: inout G
    ) {
        state.lapses += 1
        state.repetitions = 0
        state.easeFactor -= config.lapseEasePenalty

        // The interval the card will return to once it finishes relearning.
        let postLapse = max(config.minimumInterval, state.intervalDays * config.lapseIntervalMultiplier)
        state.intervalDays = min(postLapse, config.maximumInterval)

        if let first = config.relearningSteps.first {
            state.phase = .relearning(step: 0)
            state.dueDate = now.addingTimeInterval(first)
        } else {
            state.phase = .review
            state.dueDate = now.addingTimeInterval(state.intervalDays * secondsPerDay)
        }
    }

    // MARK: - Relearning

    private func applyRelearningStep<G: RandomNumberGenerator>(
        to state: inout SchedulingState, currentStep: Int,
        grade: ReviewGrade, now: Date, using rng: inout G
    ) {
        let steps = config.relearningSteps
        guard !steps.isEmpty else {
            returnToReview(&state, now: now, using: &rng)
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
        case .good:
            let nextStep = currentStep + 1
            if nextStep >= steps.count {
                returnToReview(&state, now: now, using: &rng)
            } else {
                state.phase = .relearning(step: nextStep)
                state.dueDate = now.addingTimeInterval(steps[nextStep])
            }
        case .easy:
            returnToReview(&state, now: now, using: &rng)
        }
    }

    private func returnToReview<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, now: Date, using rng: inout G
    ) {
        state.phase = .review
        state.repetitions += 1
        setInterval(&state, days: max(state.intervalDays, config.minimumInterval), now: now, using: &rng)
    }

    // MARK: - Helpers

    private func setInterval<G: RandomNumberGenerator>(
        _ state: inout SchedulingState, days: Double, now: Date, using rng: inout G
    ) {
        let clamped = min(max(days, config.minimumInterval), config.maximumInterval)
        let final = fuzz(clamped, using: &rng)
        state.intervalDays = final
        state.dueDate = now.addingTimeInterval(final * secondsPerDay)
    }

    /// Spreads intervals slightly so a big batch of cards learned together doesn't all
    /// come due on the same day forever. Short intervals are left exact.
    private func fuzz<G: RandomNumberGenerator>(_ days: Double, using rng: inout G) -> Double {
        guard config.intervalFuzzFactor > 0, days >= 2 else { return days }
        let delta = days * config.intervalFuzzFactor
        let low = max(config.minimumInterval, days - delta)
        let high = min(config.maximumInterval, days + delta)
        guard high > low else { return days }
        return Double.random(in: low...high, using: &rng)
    }

    private func clampEase(_ ease: Double) -> Double {
        min(max(ease, config.minimumEase), config.maximumEase)
    }
}
