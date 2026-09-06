import Foundation

/// One sitting: a time of day, the decks to cover, and how long it should take.
public struct PlannedSession: Sendable, Equatable, Identifiable {
    public var id: UUID
    /// Hour and minute, local time.
    public var hour: Int
    public var minute: Int
    public var deckIDs: [UUID]
    public var cardCount: Int
    public var estimatedSeconds: Double

    public var estimatedMinutes: Int { max(1, Int((estimatedSeconds / 60).rounded())) }

    public var label: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(h)\(suffix)" : String(format: "%d:%02d%@", h, minute, suffix)
    }

    public init(id: UUID = UUID(), hour: Int, minute: Int, deckIDs: [UUID],
                cardCount: Int, estimatedSeconds: Double) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.deckIDs = deckIDs
        self.cardCount = cardCount
        self.estimatedSeconds = estimatedSeconds
    }
}

public struct StudyPlan: Sendable, Equatable {
    public var sessions: [PlannedSession]
    /// Cards that did not fit inside the day's sessions.
    public var deferredCards: Int

    public var totalCards: Int { sessions.reduce(0) { $0 + $1.cardCount } }
    public var totalSeconds: Double { sessions.reduce(0) { $0 + $1.estimatedSeconds } }
    public var totalMinutes: Int { max(0, Int((totalSeconds / 60).rounded())) }
    public var isEmpty: Bool { sessions.isEmpty }

    public init(sessions: [PlannedSession], deferredCards: Int = 0) {
        self.sessions = sessions
        self.deferredCards = deferredCards
    }
}

/// When during the day you are willing to study.
public struct StudySlot: Codable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String { "\(hour):\(minute)" }
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Morning and evening: two sittings a day, far enough apart that the second is not a
    /// re-run of the first.
    public static let defaults = [StudySlot(hour: 8), StudySlot(hour: 20)]
}

public struct StudyPlanSettings: Codable, Sendable, Equatable {
    public var isEnabled: Bool
    /// Decks the plan covers. Empty means every deck.
    public var deckIDs: [UUID]
    public var slots: [StudySlot]
    /// The longest a single sitting should be. The research is clear that spacing matters
    /// and session length does not, so this exists to keep study alongside other work
    /// rather than because some number is optimal.
    public var maximumSessionMinutes: Int
    /// Days without touching a deck before the app says something.
    public var nudgeAfterDays: Int
    /// Recall level below which a deck is considered to be slipping away.
    public var nudgeBelowRecall: Double

    public static let `default` = StudyPlanSettings(
        isEnabled: false,
        deckIDs: [],
        slots: StudySlot.defaults,
        maximumSessionMinutes: 15,
        nudgeAfterDays: 3,
        nudgeBelowRecall: 0.75
    )

    public init(isEnabled: Bool, deckIDs: [UUID], slots: [StudySlot],
                maximumSessionMinutes: Int, nudgeAfterDays: Int, nudgeBelowRecall: Double) {
        self.isEnabled = isEnabled
        self.deckIDs = deckIDs
        self.slots = slots
        self.maximumSessionMinutes = maximumSessionMinutes
        self.nudgeAfterDays = nudgeAfterDays
        self.nudgeBelowRecall = nudgeBelowRecall
    }
}

/// What the planner needs to know about a deck.
public struct DeckWorkload: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var dueCount: Int
    /// Expected recall right now, used to decide which decks go first.
    public var recallProbability: Double
    public var hasBeenStudied: Bool
    public var daysSinceLastReview: Double?

    public init(id: UUID, name: String, dueCount: Int, recallProbability: Double,
                hasBeenStudied: Bool, daysSinceLastReview: Double?) {
        self.id = id
        self.name = name
        self.dueCount = dueCount
        self.recallProbability = recallProbability
        self.hasBeenStudied = hasBeenStudied
        self.daysSinceLastReview = daysSinceLastReview
    }
}

/// Turns "these decks are due" into "study at these times, for this long".
///
/// The research on distributed practice says two things that matter here: any spacing
/// beats none, and sessions should be spread across the day rather than massed. It does
/// not say how long a session should be. So the planner spreads the day's work across the
/// slots you chose, caps each sitting so it fits alongside everything else, and puts the
/// decks you are closest to forgetting first.
public struct StudyPlanner: Sendable {
    public let settings: StudyPlanSettings
    /// How long a card actually takes you, measured from review history where possible.
    public let secondsPerCard: Double

    public static let defaultSecondsPerCard: Double = 8

    public init(settings: StudyPlanSettings = .default,
                secondsPerCard: Double = StudyPlanner.defaultSecondsPerCard) {
        self.settings = settings
        // Guard against a wild estimate from a handful of reviews.
        self.secondsPerCard = min(max(secondsPerCard, 2), 60)
    }

    public func plan(for workloads: [DeckWorkload], now: Date = Date()) -> StudyPlan {
        let included = settings.deckIDs.isEmpty
            ? workloads
            : workloads.filter { settings.deckIDs.contains($0.id) }

        // Weakest memory first: those are the cards about to be lost.
        let ordered = included
            .filter { $0.dueCount > 0 }
            .sorted { a, b in
                if a.recallProbability != b.recallProbability {
                    return a.recallProbability < b.recallProbability
                }
                return a.dueCount > b.dueCount
            }

        let totalDue = ordered.reduce(0) { $0 + $1.dueCount }
        guard totalDue > 0, !settings.slots.isEmpty else {
            return StudyPlan(sessions: [], deferredCards: 0)
        }

        let slots = settings.slots.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        let capacityPerSession = max(1, Int(Double(settings.maximumSessionMinutes) * 60 / secondsPerCard))

        // Spread evenly, but never more than a sitting can hold.
        let evenShare = Int(ceil(Double(totalDue) / Double(slots.count)))
        let perSession = min(evenShare, capacityPerSession)

        var remaining = ordered.map { (id: $0.id, count: $0.dueCount) }
        var sessions: [PlannedSession] = []

        for slot in slots {
            var budget = perSession
            var deckIDs: [UUID] = []
            var cards = 0

            for index in remaining.indices where budget > 0 {
                guard remaining[index].count > 0 else { continue }
                let take = min(budget, remaining[index].count)
                remaining[index].count -= take
                budget -= take
                cards += take
                deckIDs.append(remaining[index].id)
            }

            if cards > 0 {
                sessions.append(PlannedSession(
                    hour: slot.hour, minute: slot.minute,
                    deckIDs: deckIDs, cardCount: cards,
                    estimatedSeconds: Double(cards) * secondsPerCard
                ))
            }
        }

        let deferred = remaining.reduce(0) { $0 + $1.count }
        return StudyPlan(sessions: sessions, deferredCards: deferred)
    }

    /// Decks that have gone quiet: either untouched for too long, or predicted to have
    /// decayed below the level you said you cared about.
    public func decksNeedingAttention(_ workloads: [DeckWorkload]) -> [DeckWorkload] {
        workloads.filter { deck in
            guard deck.hasBeenStudied else { return false }
            if let days = deck.daysSinceLastReview, days >= Double(settings.nudgeAfterDays) {
                return true
            }
            return deck.recallProbability < settings.nudgeBelowRecall
        }
        .sorted { $0.recallProbability < $1.recallProbability }
    }
}
