import XCTest
@testable import FlashcardsCore

final class StudyPlannerTests: XCTestCase {

    private func deck(_ name: String, due: Int, recall: Double = 0.8,
                      studied: Bool = true, daysSince: Double? = 1) -> DeckWorkload {
        DeckWorkload(id: UUID(), name: name, dueCount: due, recallProbability: recall,
                     hasBeenStudied: studied, daysSinceLastReview: daysSince)
    }

    private func settings(slots: [StudySlot] = StudySlot.defaults,
                          maxMinutes: Int = 15,
                          deckIDs: [UUID] = []) -> StudyPlanSettings {
        var s = StudyPlanSettings.default
        s.isEnabled = true
        s.slots = slots
        s.maximumSessionMinutes = maxMinutes
        s.deckIDs = deckIDs
        return s
    }

    // MARK: - Spreading the work

    func testWorkIsSplitAcrossTheChosenTimes() {
        let planner = StudyPlanner(settings: settings(), secondsPerCard: 8)
        let plan = planner.plan(for: [deck("A", due: 40)])
        XCTAssertEqual(plan.sessions.count, 2, "two slots should produce two sittings")
        XCTAssertEqual(plan.totalCards, 40)
        XCTAssertEqual(plan.sessions[0].cardCount, 20)
        XCTAssertEqual(plan.sessions[1].cardCount, 20)
    }

    func testSessionsAreOrderedThroughTheDay() {
        let planner = StudyPlanner(settings: settings(slots: [
            StudySlot(hour: 21), StudySlot(hour: 7, minute: 30)
        ]), secondsPerCard: 8)
        let plan = planner.plan(for: [deck("A", due: 10)])
        XCTAssertEqual(plan.sessions.first?.hour, 7)
        XCTAssertEqual(plan.sessions.last?.hour, 21)
    }

    func testASittingIsCappedSoStudyFitsAroundOtherWork() {
        // 15 minutes at 8s a card is about 112 cards; 400 due must not become one sitting.
        let planner = StudyPlanner(settings: settings(maxMinutes: 15), secondsPerCard: 8)
        let plan = planner.plan(for: [deck("A", due: 400)])
        for session in plan.sessions {
            XCTAssertLessThanOrEqual(session.estimatedMinutes, 15)
        }
        XCTAssertGreaterThan(plan.deferredCards, 0, "what does not fit should be reported, not hidden")
    }

    func testNothingDueMeansNoPlan() {
        let planner = StudyPlanner(settings: settings())
        XCTAssertTrue(planner.plan(for: [deck("A", due: 0)]).isEmpty)
    }

    func testNoSlotsMeansNoPlan() {
        let planner = StudyPlanner(settings: settings(slots: []))
        XCTAssertTrue(planner.plan(for: [deck("A", due: 20)]).isEmpty)
    }

    // MARK: - Priority

    func testWeakestDecksAreScheduledFirst() {
        let strong = deck("Strong", due: 10, recall: 0.95)
        let weak = deck("Weak", due: 10, recall: 0.40)
        let planner = StudyPlanner(settings: settings(slots: [StudySlot(hour: 9)]), secondsPerCard: 8)
        let plan = planner.plan(for: [strong, weak])
        XCTAssertEqual(plan.sessions.first?.deckIDs.first, weak.id,
                       "the deck closest to being forgotten should come first")
    }

    func testOnlySelectedDecksAreIncluded() {
        let a = deck("A", due: 10)
        let b = deck("B", due: 10)
        let planner = StudyPlanner(settings: settings(deckIDs: [a.id]), secondsPerCard: 8)
        let plan = planner.plan(for: [a, b])
        XCTAssertEqual(plan.totalCards, 10)
        XCTAssertFalse(plan.sessions.contains { $0.deckIDs.contains(b.id) })
    }

    func testEmptySelectionMeansEveryDeck() {
        let planner = StudyPlanner(settings: settings(), secondsPerCard: 8)
        let plan = planner.plan(for: [deck("A", due: 10), deck("B", due: 10)])
        XCTAssertEqual(plan.totalCards, 20)
    }

    // MARK: - Time estimates

    func testEstimateUsesMeasuredPacePerCard() {
        let fast = StudyPlanner(settings: settings(slots: [StudySlot(hour: 9)]), secondsPerCard: 4)
        let slow = StudyPlanner(settings: settings(slots: [StudySlot(hour: 9)]), secondsPerCard: 16)
        let cards = [deck("A", due: 30)]
        XCTAssertLessThan(fast.plan(for: cards).totalSeconds, slow.plan(for: cards).totalSeconds)
    }

    func testWildPaceEstimatesAreClamped() {
        XCTAssertEqual(StudyPlanner(secondsPerCard: 0).secondsPerCard, 2)
        XCTAssertEqual(StudyPlanner(secondsPerCard: 9999).secondsPerCard, 60)
    }

    func testSessionLabelReadsAsATime() {
        XCTAssertEqual(PlannedSession(hour: 8, minute: 0, deckIDs: [], cardCount: 1, estimatedSeconds: 8).label, "8am")
        XCTAssertEqual(PlannedSession(hour: 20, minute: 30, deckIDs: [], cardCount: 1, estimatedSeconds: 8).label, "8:30pm")
        XCTAssertEqual(PlannedSession(hour: 0, minute: 0, deckIDs: [], cardCount: 1, estimatedSeconds: 8).label, "12am")
    }

    // MARK: - Nudges

    func testADeckUntouchedForTooLongNeedsAttention() {
        let planner = StudyPlanner(settings: settings())
        let stale = deck("Stale", due: 0, recall: 0.99, daysSince: 5)
        XCTAssertEqual(planner.decksNeedingAttention([stale]).count, 1)
    }

    func testADeckThatHasDecayedNeedsAttention() {
        let planner = StudyPlanner(settings: settings())
        let faded = deck("Faded", due: 0, recall: 0.4, daysSince: 0)
        XCTAssertEqual(planner.decksNeedingAttention([faded]).count, 1)
    }

    func testAHealthyRecentlyStudiedDeckIsLeftAlone() {
        let planner = StudyPlanner(settings: settings())
        let healthy = deck("Healthy", due: 0, recall: 0.95, daysSince: 0)
        XCTAssertTrue(planner.decksNeedingAttention([healthy]).isEmpty)
    }

    func testNeverStudiedDecksAreNotNagged() {
        let planner = StudyPlanner(settings: settings())
        let fresh = deck("New", due: 5, recall: 0, studied: false, daysSince: nil)
        XCTAssertTrue(planner.decksNeedingAttention([fresh]).isEmpty,
                      "you cannot be reminded to revisit something you never started")
    }

    func testDecksNeedingAttentionAreWorstFirst() {
        let planner = StudyPlanner(settings: settings())
        let bad = deck("Bad", due: 0, recall: 0.2, daysSince: 9)
        let worse = deck("Worse", due: 0, recall: 0.05, daysSince: 9)
        XCTAssertEqual(planner.decksNeedingAttention([bad, worse]).first?.id, worse.id)
    }
}
