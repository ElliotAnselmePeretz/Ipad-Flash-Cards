import Foundation
import SwiftData
import FlashcardsCore

/// Bridges the stored decks to the pure planner in the core package.
enum PlanBuilder {

    private static let estimator = MemoryEstimator()

    /// How long a card actually takes this person, measured from their own reviews rather
    /// than assumed. Falls back to a default until there is enough history to mean anything.
    static func measuredSecondsPerCard(for profile: StoredProfile, sampleSize: Int = 100) -> Double {
        let durations = profile.decks
            .filter { $0.deletedAt == nil }
            .flatMap { $0.cards.filter { $0.deletedAt == nil } }
            .flatMap(\.reviewLogs)
            .sorted { $0.reviewedAt > $1.reviewedAt }
            .prefix(sampleSize)
            .map(\.durationSeconds)
            // Ignore cards left on screen while the user did something else.
            .filter { $0 > 0.5 && $0 < 120 }

        guard durations.count >= 10 else { return StudyPlanner.defaultSecondsPerCard }
        return durations.reduce(0, +) / Double(durations.count)
    }

    static func workloads(for profile: StoredProfile, now: Date = Date()) -> [DeckWorkload] {
        profile.decks.filter { $0.deletedAt == nil }.map { deck in
            let cards = deck.cards.filter { $0.deletedAt == nil && !$0.isSuspended }
            let estimate = estimator.estimate(for: cards.map(\.scheduling), now: now)
            let lastReview = cards.compactMap { $0.scheduling.lastReviewedAt }.max()

            return DeckWorkload(
                id: deck.id,
                name: deck.name,
                dueCount: cards.filter { $0.dueDate <= now }.count,
                recallProbability: estimate.isEmpty ? 1 : estimate.recallProbability,
                hasBeenStudied: estimate.consideredCards > 0,
                daysSinceLastReview: lastReview.map { now.timeIntervalSince($0) / 86_400 }
            )
        }
    }

    static func planner(for profile: StoredProfile, settings: StudyPlanSettings) -> StudyPlanner {
        StudyPlanner(settings: settings, secondsPerCard: measuredSecondsPerCard(for: profile))
    }
}
