import Foundation
import SwiftData
import Observation
import FlashcardsCore

/// Drives one study run: holds the queue, applies grades, writes review logs.
///
/// All scheduling decisions are delegated to `SM2Scheduler` in the core package —
/// this type only deals with persistence and presentation state.
@Observable
final class StudySession {
    enum Stage {
        case question   // answer hidden; learner is writing
        case answer     // answer revealed; grade buttons shown
        case finished
    }

    private(set) var queue: [StoredCard] = []
    private(set) var counts = QueueCounts()
    private(set) var stage: Stage = .question
    private(set) var completedCount = 0

    /// The learner's handwritten attempt at the current card.
    var attemptDrawing: Data?

    private let deck: StoredDeck
    private let context: ModelContext
    private let scheduler: SM2Scheduler
    private var shownAt = Date()

    var currentCard: StoredCard? { queue.first }

    init(deck: StoredDeck, context: ModelContext, config: SchedulerConfig = .default) {
        self.deck = deck
        self.context = context
        self.scheduler = SM2Scheduler(config: config)
        rebuild()
    }

    /// Rebuilds today's queue from the store.
    func rebuild(now: Date = Date()) {
        let deckID = deck.id
        let descriptor = FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.deck?.id == deckID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        let stored = (try? context.fetch(descriptor)) ?? []
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })

        let builder = ReviewQueue(
            deck: deck.core,
            newCardsStudiedToday: newCardsStudiedToday(now: now),
            reviewsCompletedToday: reviewsCompletedToday(now: now)
        )
        let ordered = builder.build(from: stored.map(\.core), now: now)

        queue = ordered.compactMap { byID[$0.id] }
        counts = builder.counts(from: stored.map(\.core), now: now)
        stage = queue.isEmpty ? .finished : .question
        shownAt = now
    }

    func revealAnswer() {
        guard stage == .question else { return }
        stage = .answer
    }

    /// Grade the current card, persist the result, and advance.
    func grade(_ grade: ReviewGrade, now: Date = Date()) {
        guard let card = currentCard else { return }

        let before = card.scheduling
        let after = scheduler.review(before, grade: grade, now: now)
        card.scheduling = after

        context.insert(StoredReviewLog(
            card: card,
            reviewedAt: now,
            grade: grade,
            intervalBefore: before.intervalDays,
            intervalAfter: after.intervalDays,
            easeAfter: after.easeFactor,
            durationSeconds: now.timeIntervalSince(shownAt),
            attemptDrawing: attemptDrawing
        ))

        completedCount += 1
        attemptDrawing = nil
        queue.removeFirst()

        // A card answered "again" comes back in minutes, so put it back in this session
        // once its short step elapses rather than making the learner restart the deck.
        if !after.isGraduated || after.dueDate.timeIntervalSince(now) < 600 {
            insertByDueDate(card)
        }

        try? context.save()
        recountBuckets(now: now)
        stage = queue.isEmpty ? .finished : .question
        shownAt = now
    }

    /// Skip without grading — the card stays due.
    func skip() {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        queue.append(card)
        attemptDrawing = nil
        stage = .question
        shownAt = Date()
    }

    private func insertByDueDate(_ card: StoredCard) {
        let due = card.scheduling.dueDate
        if let index = queue.firstIndex(where: { $0.scheduling.dueDate > due }) {
            queue.insert(card, at: index)
        } else {
            queue.append(card)
        }
    }

    private func recountBuckets(now: Date) {
        let cards = queue.map(\.core)
        counts = QueueCounts(
            learning: cards.filter {
                switch $0.scheduling.phase { case .learning, .relearning: true; default: false }
            }.count,
            review: cards.filter { $0.scheduling.phase == .review }.count,
            new: cards.filter { $0.scheduling.phase == .new }.count
        )
    }

    // MARK: - Daily limits

    /// Start of the learner's day, honouring the profile's rollover hour so a 1am
    /// session still counts as the previous day.
    private func dayStart(now: Date) -> Date {
        let hour = deck.profile?.dayStartHour ?? 4
        let calendar = Calendar.current
        let todayAtHour = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        return todayAtHour <= now ? todayAtHour : calendar.date(byAdding: .day, value: -1, to: todayAtHour) ?? now
    }

    private func logsToday(now: Date) -> [StoredReviewLog] {
        let start = dayStart(now: now)
        let deckID = deck.id
        let descriptor = FetchDescriptor<StoredReviewLog>(
            predicate: #Predicate { $0.reviewedAt >= start && $0.card?.deck?.id == deckID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func newCardsStudiedToday(now: Date) -> Int {
        // A log whose "before" interval was zero was that card's first graded look.
        Set(logsToday(now: now).filter { $0.intervalBefore == 0 }.compactMap { $0.card?.id }).count
    }

    private func reviewsCompletedToday(now: Date) -> Int {
        logsToday(now: now).filter { $0.intervalBefore > 0 }.count
    }
}
