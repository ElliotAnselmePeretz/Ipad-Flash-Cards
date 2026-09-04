import Foundation
import SwiftData
import Observation
import FlashcardsCore

/// Drives one study run: holds the queue, applies grades, writes review logs.
///
/// All scheduling decisions are delegated to `FSRSCardScheduler` in the core package —
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


    /// Everything needed to put the last graded card back exactly as it was. A mistap on
    /// a four-button row is easy and would otherwise reschedule a card for months.
    private struct GradedStep {
        let card: StoredCard
        let previousState: SchedulingState
        let log: StoredReviewLog
        /// Whether grading pushed the card back into this session (an "Again" answer).
        let wasRequeued: Bool
    }

    private var lastStep: GradedStep?

    var canUndo: Bool { lastStep != nil }

    /// Set when a review pushes a card past the leech threshold, so the UI can say so.
    private(set) var leechCount = 0
    private(set) var lastLeechName: String?

    private let deck: StoredDeck
    private let context: ModelContext
    private let scheduler: FSRSCardScheduler
    private var shownAt = Date()

    var currentCard: StoredCard? { queue.first }

    init(deck: StoredDeck, context: ModelContext, settings: RetentionSettings = .default) {
        self.deck = deck
        self.context = context
        self.scheduler = FSRSCardScheduler(settings: settings)
        rebuild()
    }

    /// Rebuilds today's queue from the store.
    func rebuild(now: Date = Date()) {
        // Relationship traversal is deliberately kept OUT of the predicate: CoreData
        // cannot translate a chained optional keypath like `card?.deck?.id` into SQL and
        // throws at fetch time. Filter on stored columns, then narrow in Swift.
        let deckID = deck.id
        let descriptor = FetchDescriptor<StoredCard>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.dueDate)]
        )
        let stored = ((try? context.fetch(descriptor)) ?? []).filter { $0.deck?.id == deckID }
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
        let outcome = scheduler.review(before, grade: grade, now: now)
        let after = outcome.state
        card.scheduling = after
        if outcome.becameLeech {
            card.isLeech = true
            lastLeechName = deck.name
            leechCount += 1
        }
        if outcome.shouldSuspend { card.isSuspended = true }

        let log = StoredReviewLog(
            card: card,
            reviewedAt: now,
            grade: grade,
            intervalBefore: before.intervalDays,
            intervalAfter: after.intervalDays,
            easeAfter: after.easeFactor,
            durationSeconds: now.timeIntervalSince(shownAt),
            attemptDrawing: nil
        )
        context.insert(log)

        completedCount += 1
        queue.removeFirst()

        // A card answered "again" comes back in minutes, so put it back in this session
        // once its short step elapses rather than making the learner restart the deck.
        let requeued = !after.isGraduated || after.dueDate.timeIntervalSince(now) < 600
        if requeued { insertByDueDate(card) }

        lastStep = GradedStep(card: card, previousState: before, log: log,
                              wasRequeued: requeued)

        try? context.save()
        recountBuckets(now: now)
        stage = queue.isEmpty ? .finished : .question
        shownAt = now
    }

    /// Put the last graded card back exactly as it was, ready to be answered again.
    func undoLastGrade() {
        guard let step = lastStep else { return }

        // Take the card out of wherever grading left it before restoring its state.
        if step.wasRequeued, let index = queue.firstIndex(where: { $0.id == step.card.id }) {
            queue.remove(at: index)
        }

        step.card.scheduling = step.previousState
        context.delete(step.log)

        queue.insert(step.card, at: 0)
        completedCount = max(0, completedCount - 1)
        lastStep = nil

        try? context.save()
        recountBuckets(now: Date())
        // Return to the answer, so the learner can simply pick a different button.
        stage = .answer
        shownAt = Date()
    }

    /// Skip without grading — the card stays due.
    func skip() {
        guard !queue.isEmpty else { return }
        let card = queue.removeFirst()
        queue.append(card)
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
        // Same constraint as `rebuild`: date filtering happens in the query, deck
        // matching happens in Swift. One day of reviews is a small set either way.
        let start = dayStart(now: now)
        let deckID = deck.id
        let descriptor = FetchDescriptor<StoredReviewLog>(
            predicate: #Predicate { $0.reviewedAt >= start }
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.card?.deck?.id == deckID }
    }

    private func newCardsStudiedToday(now: Date) -> Int {
        // A log whose "before" interval was zero was that card's first graded look.
        Set(logsToday(now: now).filter { $0.intervalBefore == 0 }.compactMap { $0.card?.id }).count
    }

    private func reviewsCompletedToday(now: Date) -> Int {
        logsToday(now: now).filter { $0.intervalBefore > 0 }.count
    }
}
