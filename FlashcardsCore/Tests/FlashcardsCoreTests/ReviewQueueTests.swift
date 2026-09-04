import XCTest
@testable import FlashcardsCore

final class ReviewQueueTests: XCTestCase {
    let profileID = UUID()
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDeck(newPerDay: Int = 20, maxReviews: Int = 200) -> Deck {
        Deck(profileID: profileID, name: "Test", newCardsPerDay: newPerDay, maximumReviewsPerDay: maxReviews)
    }

    private func card(in deck: Deck, phase: LearningPhase, due: Date, created: Date? = nil) -> Card {
        var state = SchedulingState.new(now: t0)
        state.phase = phase
        state.dueDate = due
        state.intervalDays = phase == .review ? 5 : 0
        return Card(deckID: deck.id, profileID: profileID, scheduling: state, createdAt: created ?? t0)
    }

    func testLearningCardsComeBeforeReviewsAndNew() {
        let deck = makeDeck()
        let cards = [
            card(in: deck, phase: .new, due: t0),
            card(in: deck, phase: .review, due: t0.addingTimeInterval(-100)),
            card(in: deck, phase: .learning(step: 0), due: t0.addingTimeInterval(-10)),
        ]
        let queue = ReviewQueue(deck: deck).build(from: cards, now: t0)
        XCTAssertEqual(queue.count, 3)
        XCTAssertEqual(queue[0].scheduling.phase, .learning(step: 0))
        XCTAssertEqual(queue[1].scheduling.phase, .review)
        XCTAssertEqual(queue[2].scheduling.phase, .new)
    }

    func testCardsDueInTheFutureAreExcluded() {
        let deck = makeDeck()
        let cards = [
            card(in: deck, phase: .review, due: t0.addingTimeInterval(86_400)),
            card(in: deck, phase: .learning(step: 0), due: t0.addingTimeInterval(600)),
        ]
        XCTAssertTrue(ReviewQueue(deck: deck).build(from: cards, now: t0).isEmpty)
    }

    func testNewCardLimitIsRespected() {
        let deck = makeDeck(newPerDay: 3)
        let cards = (0..<10).map { i in
            card(in: deck, phase: .new, due: t0, created: t0.addingTimeInterval(Double(i)))
        }
        XCTAssertEqual(ReviewQueue(deck: deck).build(from: cards, now: t0).count, 3)
    }

    func testNewCardLimitAccountsForCardsAlreadyStudiedToday() {
        let deck = makeDeck(newPerDay: 5)
        let cards = (0..<10).map { _ in card(in: deck, phase: .new, due: t0) }
        let queue = ReviewQueue(deck: deck, newCardsStudiedToday: 4).build(from: cards, now: t0)
        XCTAssertEqual(queue.count, 1)
    }

    func testReviewLimitIsRespectedButLearningIsNot() {
        let deck = makeDeck(maxReviews: 2)
        let reviews = (0..<5).map { i in
            card(in: deck, phase: .review, due: t0.addingTimeInterval(Double(-i)))
        }
        let learning = (0..<3).map { _ in card(in: deck, phase: .learning(step: 0), due: t0) }
        let queue = ReviewQueue(deck: deck).build(from: reviews + learning, now: t0)
        XCTAssertEqual(queue.filter { $0.scheduling.phase == .review }.count, 2)
        XCTAssertEqual(queue.count, 5, "learning cards bypass the review cap")
    }

    func testOtherProfilesAndDecksAreExcluded() {
        let deck = makeDeck()
        let mine = card(in: deck, phase: .new, due: t0)
        var theirs = card(in: deck, phase: .new, due: t0)
        theirs.profileID = UUID()
        var otherDeck = card(in: deck, phase: .new, due: t0)
        otherDeck.deckID = UUID()

        let queue = ReviewQueue(deck: deck).build(from: [mine, theirs, otherDeck], now: t0)
        XCTAssertEqual(queue.map(\.id), [mine.id])
    }

    func testDeletedCardsAreExcluded() {
        let deck = makeDeck()
        var deleted = card(in: deck, phase: .new, due: t0)
        deleted.deletedAt = t0
        XCTAssertTrue(ReviewQueue(deck: deck).build(from: [deleted], now: t0).isEmpty)
    }

    func testCountsBreakDownByBucket() {
        let deck = makeDeck()
        let cards = [
            card(in: deck, phase: .new, due: t0),
            card(in: deck, phase: .new, due: t0),
            card(in: deck, phase: .review, due: t0),
            card(in: deck, phase: .relearning(step: 0), due: t0),
        ]
        let counts = ReviewQueue(deck: deck).counts(from: cards, now: t0)
        XCTAssertEqual(counts.new, 2)
        XCTAssertEqual(counts.review, 1)
        XCTAssertEqual(counts.learning, 1)
        XCTAssertEqual(counts.total, 4)
    }

    func testOverdueReviewsComeFirst() {
        let deck = makeDeck()
        let recent = card(in: deck, phase: .review, due: t0.addingTimeInterval(-60))
        let ancient = card(in: deck, phase: .review, due: t0.addingTimeInterval(-86_400))
        let queue = ReviewQueue(deck: deck).build(from: [recent, ancient], now: t0)
        XCTAssertEqual(queue.map(\.id), [ancient.id, recent.id])
    }
}
