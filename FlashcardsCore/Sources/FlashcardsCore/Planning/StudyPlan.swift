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
    /// The goal this plan is working towards, if any.
    public var goal: StudyGoal?

    public var totalCards: Int { sessions.reduce(0) { $0 + $1.cardCount } }
    public var totalSeconds: Double { sessions.reduce(0) { $0 + $1.estimatedSeconds } }
    public var totalMinutes: Int { max(0, Int((totalSeconds / 60).rounded())) }
    public var isEmpty: Bool { sessions.isEmpty }

    public init(sessions: [PlannedSession], deferredCards: Int = 0, goal: StudyGoal? = nil) {
        self.sessions = sessions
        self.deferredCards = deferredCards
        self.goal = goal
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

/// Something you are working towards: a test, a mock, an interview.
///
/// A date changes what matters. Without one, the plan simply keeps everything from
/// decaying. With one, the decks that test covers come first, and they come first more
/// insistently the closer it gets.
public struct StudyGoal: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var date: Date
    /// Decks this goal covers. Empty means it applies to nothing in particular.
    public var deckIDs: [UUID]

    public init(id: UUID = UUID(), name: String, date: Date, deckIDs: [UUID]) {
        self.id = id
        self.name = name
        self.date = date
        self.deckIDs = deckIDs
    }

    public func daysAway(from now: Date = Date()) -> Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let target = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: start, to: target).day ?? 0
    }

    public func isUpcoming(from now: Date = Date()) -> Bool { daysAway(from: now) >= 0 }

    /// Reads as a person would say it.
    public func countdown(from now: Date = Date()) -> String {
        let days = daysAway(from: now)
        switch days {
        case ..<0: return "passed"
        case 0: return "today"
        case 1: return "tomorrow"
        case 2...13: return "in \(days) days"
        default: return "in \(days / 7) ^[week](inflect: true)".replacingOccurrences(of: "^[week](inflect: true)", with: days / 7 == 1 ? "week" : "weeks")
        }
    }
}

public struct StudyPlanSettings: Codable, Sendable, Equatable {
    /// Settings saved before goals existed decode with an empty list rather than failing,
    /// so an update never silently discards someone's plan.
    private enum CodingKeys: String, CodingKey {
        case isEnabled, deckIDs, goals, slots, maximumSessionMinutes, nudgeAfterDays, nudgeBelowRecall
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        deckIDs = try c.decodeIfPresent([UUID].self, forKey: .deckIDs) ?? []
        goals = try c.decodeIfPresent([StudyGoal].self, forKey: .goals) ?? []
        slots = try c.decodeIfPresent([StudySlot].self, forKey: .slots) ?? StudySlot.defaults
        maximumSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .maximumSessionMinutes) ?? 15
        nudgeAfterDays = try c.decodeIfPresent(Int.self, forKey: .nudgeAfterDays) ?? 3
        nudgeBelowRecall = try c.decodeIfPresent(Double.self, forKey: .nudgeBelowRecall) ?? 0.75
    }

    public var isEnabled: Bool
    /// Decks the plan covers. Empty means every deck.
    public var deckIDs: [UUID]
    /// Tests and deadlines coming up.
    public var goals: [StudyGoal]
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
        goals: [],
        slots: StudySlot.defaults,
        maximumSessionMinutes: 15,
        nudgeAfterDays: 3,
        nudgeBelowRecall: 0.75
    )

    public init(isEnabled: Bool, deckIDs: [UUID], goals: [StudyGoal] = [], slots: [StudySlot],
                maximumSessionMinutes: Int, nudgeAfterDays: Int, nudgeBelowRecall: Double) {
        self.isEnabled = isEnabled
        self.deckIDs = deckIDs
        self.goals = goals
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

    /// The next thing being worked towards, if there is one.
    public func nextGoal(now: Date = Date()) -> StudyGoal? {
        settings.goals
            .filter { $0.isUpcoming(from: now) }
            .min { $0.date < $1.date }
    }

    public func plan(for workloads: [DeckWorkload], now: Date = Date()) -> StudyPlan {
        let included = settings.deckIDs.isEmpty
            ? workloads
            : workloads.filter { settings.deckIDs.contains($0.id) }

        let goal = nextGoal(now: now)
        let goalDecks = Set(goal?.deckIDs ?? [])

        // Decks the next test covers come first, whatever their state. Within each group,
        // weakest memory first: those are the cards about to be lost.
        let ordered = included
            .filter { $0.dueCount > 0 }
            .sorted { a, b in
                let aForGoal = goalDecks.contains(a.id)
                let bForGoal = goalDecks.contains(b.id)
                if aForGoal != bForGoal { return aForGoal }
                if a.recallProbability != b.recallProbability {
                    return a.recallProbability < b.recallProbability
                }
                return a.dueCount > b.dueCount
            }

        let totalDue = ordered.reduce(0) { $0 + $1.dueCount }
        guard totalDue > 0, !settings.slots.isEmpty else {
            return StudyPlan(sessions: [], deferredCards: 0, goal: goal)
        }

        let slots = settings.slots.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        // A test close at hand justifies longer sittings; a distant one does not. The cap
        // stretches by up to half again in the last week, and not at all before that.
        let urgencyMultiplier: Double = {
            guard let days = goal?.daysAway(from: now), days >= 0, days <= 7 else { return 1 }
            return 1 + (Double(7 - days) / 7) * 0.5
        }()
        let effectiveMinutes = Double(settings.maximumSessionMinutes) * urgencyMultiplier
        let capacityPerSession = max(1, Int(effectiveMinutes * 60 / secondsPerCard))

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
        return StudyPlan(sessions: sessions, deferredCards: deferred, goal: goal)
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
