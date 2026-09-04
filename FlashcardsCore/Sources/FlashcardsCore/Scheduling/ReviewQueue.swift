import Foundation

/// What the study screen shows above the card: how much is left in each bucket.
public struct QueueCounts: Sendable, Equatable {
    public var learning: Int
    public var review: Int
    public var new: Int
    public var total: Int { learning + review + new }
    public var isEmpty: Bool { total == 0 }

    public init(learning: Int = 0, review: Int = 0, new: Int = 0) {
        self.learning = learning
        self.review = review
        self.new = new
    }
}

/// Assembles the day's study queue: which cards, in what order, respecting daily limits.
///
/// Pure and stateless — hand it the cards and it hands back an order.
public struct ReviewQueue: Sendable {
    public let deck: Deck
    public let newCardsStudiedToday: Int
    public let reviewsCompletedToday: Int

    public init(deck: Deck, newCardsStudiedToday: Int = 0, reviewsCompletedToday: Int = 0) {
        self.deck = deck
        self.newCardsStudiedToday = newCardsStudiedToday
        self.reviewsCompletedToday = reviewsCompletedToday
    }

    /// Cards to study now, in the order they should appear.
    ///
    /// Learning cards come first because their intervals are measured in minutes and go
    /// stale fastest; then reviews, oldest-due first; then new cards, up to the daily cap.
    public func build(from cards: [Card], now: Date = Date()) -> [Card] {
        let live = cards.filter { !$0.isDeleted && $0.profileID == deck.profileID && $0.deckID == deck.id }

        let learning = live
            .filter { isLearning($0) && $0.scheduling.isDue(at: now) }
            .sorted { $0.scheduling.dueDate < $1.scheduling.dueDate }

        let reviewBudget = max(0, deck.maximumReviewsPerDay - reviewsCompletedToday)
        let review = live
            .filter { $0.scheduling.phase == .review && $0.scheduling.isDue(at: now) }
            .sorted { $0.scheduling.dueDate < $1.scheduling.dueDate }
            .prefix(reviewBudget)

        let newBudget = max(0, deck.newCardsPerDay - newCardsStudiedToday)
        let fresh = live
            .filter { $0.scheduling.phase == .new }
            .sorted { $0.createdAt < $1.createdAt }
            .prefix(newBudget)

        return learning + Array(review) + Array(fresh)
    }

    public func counts(from cards: [Card], now: Date = Date()) -> QueueCounts {
        let queue = build(from: cards, now: now)
        return QueueCounts(
            learning: queue.filter { isLearning($0) }.count,
            review: queue.filter { $0.scheduling.phase == .review }.count,
            new: queue.filter { $0.scheduling.phase == .new }.count
        )
    }

    private func isLearning(_ card: Card) -> Bool {
        switch card.scheduling.phase {
        case .learning, .relearning: true
        case .new, .review: false
        }
    }
}
