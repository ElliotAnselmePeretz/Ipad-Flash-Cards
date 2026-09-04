import Foundation

/// Tunable knobs for `SM2Scheduler`. Defaults match Anki's out-of-the-box behaviour.
public struct SchedulerConfig: Codable, Sendable, Equatable {
    /// Delays for a brand-new card before it graduates into the review pool.
    public var learningSteps: [TimeInterval]
    /// Delays a lapsed card walks through before returning to the review pool.
    public var relearningSteps: [TimeInterval]
    /// Interval, in days, given when a card graduates from the learning steps.
    public var graduatingInterval: Double
    /// Interval, in days, given when a new card is answered `.easy` outright.
    public var easyInterval: Double
    /// Starting ease factor for a new card.
    public var startingEase: Double
    public var minimumEase: Double
    public var maximumEase: Double
    /// Ease adjustments applied per grade on a review card.
    public var lapseEasePenalty: Double
    public var hardEasePenalty: Double
    public var easyEaseBonus: Double
    /// Interval multipliers.
    public var hardMultiplier: Double
    public var easyBonus: Double
    /// Fraction of the previous interval a lapsed card keeps. 0 means start over.
    public var lapseIntervalMultiplier: Double
    public var minimumInterval: Double
    public var maximumInterval: Double
    /// Random spread applied to intervals so cards don't clump on the same day.
    public var intervalFuzzFactor: Double

    public static let `default` = SchedulerConfig(
        learningSteps: [60, 600],
        relearningSteps: [600],
        graduatingInterval: 1,
        easyInterval: 4,
        startingEase: 2.5,
        minimumEase: 1.3,
        maximumEase: 5.0,
        lapseEasePenalty: 0.20,
        hardEasePenalty: 0.15,
        easyEaseBonus: 0.15,
        hardMultiplier: 1.2,
        easyBonus: 1.3,
        lapseIntervalMultiplier: 0.0,
        minimumInterval: 1,
        maximumInterval: 36500,
        intervalFuzzFactor: 0.05
    )

    public init(
        learningSteps: [TimeInterval], relearningSteps: [TimeInterval],
        graduatingInterval: Double, easyInterval: Double,
        startingEase: Double, minimumEase: Double, maximumEase: Double,
        lapseEasePenalty: Double, hardEasePenalty: Double, easyEaseBonus: Double,
        hardMultiplier: Double, easyBonus: Double,
        lapseIntervalMultiplier: Double,
        minimumInterval: Double, maximumInterval: Double,
        intervalFuzzFactor: Double
    ) {
        self.learningSteps = learningSteps
        self.relearningSteps = relearningSteps
        self.graduatingInterval = graduatingInterval
        self.easyInterval = easyInterval
        self.startingEase = startingEase
        self.minimumEase = minimumEase
        self.maximumEase = maximumEase
        self.lapseEasePenalty = lapseEasePenalty
        self.hardEasePenalty = hardEasePenalty
        self.easyEaseBonus = easyEaseBonus
        self.hardMultiplier = hardMultiplier
        self.easyBonus = easyBonus
        self.lapseIntervalMultiplier = lapseIntervalMultiplier
        self.minimumInterval = minimumInterval
        self.maximumInterval = maximumInterval
        self.intervalFuzzFactor = intervalFuzzFactor
    }
}
