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

final class StudyGoalTests: XCTestCase {

    private func deck(_ name: String, due: Int, recall: Double = 0.8) -> DeckWorkload {
        DeckWorkload(id: UUID(), name: name, dueCount: due, recallProbability: recall,
                     hasBeenStudied: true, daysSinceLastReview: 1)
    }

    private func settings(goals: [StudyGoal], maxMinutes: Int = 15) -> StudyPlanSettings {
        var s = StudyPlanSettings.default
        s.isEnabled = true
        s.goals = goals
        s.slots = [StudySlot(hour: 9)]
        s.maximumSessionMinutes = maxMinutes
        return s
    }

    func testDecksForTheNextTestComeFirstEvenIfTheyAreStrong() {
        let exam = deck("Exam material", due: 10, recall: 0.95)
        let weak = deck("Something else", due: 10, recall: 0.20)
        let goal = StudyGoal(name: "Mock", date: Date().addingTimeInterval(5 * 86_400), deckIDs: [exam.id])

        let plan = StudyPlanner(settings: settings(goals: [goal]), secondsPerCard: 8)
            .plan(for: [weak, exam])
        XCTAssertEqual(plan.sessions.first?.deckIDs.first, exam.id,
                       "what is being tested should be studied first")
    }

    func testTheSoonestUpcomingGoalIsTheOneThatCounts() {
        let soon = StudyGoal(name: "Soon", date: Date().addingTimeInterval(2 * 86_400), deckIDs: [])
        let later = StudyGoal(name: "Later", date: Date().addingTimeInterval(40 * 86_400), deckIDs: [])
        let planner = StudyPlanner(settings: settings(goals: [later, soon]))
        XCTAssertEqual(planner.nextGoal()?.name, "Soon")
    }

    func testPastGoalsAreIgnored() {
        let past = StudyGoal(name: "Gone", date: Date().addingTimeInterval(-3 * 86_400), deckIDs: [])
        XCTAssertNil(StudyPlanner(settings: settings(goals: [past])).nextGoal())
    }

    func testSittingsGrowAsTheTestApproaches() {
        let cards = [deck("A", due: 500)]
        let far = StudyGoal(name: "Far", date: Date().addingTimeInterval(30 * 86_400), deckIDs: [])
        let tomorrow = StudyGoal(name: "Tomorrow", date: Date().addingTimeInterval(86_400), deckIDs: [])

        let relaxed = StudyPlanner(settings: settings(goals: [far]), secondsPerCard: 8).plan(for: cards)
        let urgent = StudyPlanner(settings: settings(goals: [tomorrow]), secondsPerCard: 8).plan(for: cards)

        XCTAssertGreaterThan(urgent.totalCards, relaxed.totalCards,
                             "a test tomorrow should pull more work forward")
    }

    func testNoGoalMeansNormalPacing() {
        let cards = [deck("A", due: 500)]
        let none = StudyPlanner(settings: settings(goals: []), secondsPerCard: 8).plan(for: cards)
        for session in none.sessions {
            XCTAssertLessThanOrEqual(session.estimatedMinutes, 15)
        }
    }

    func testThePlanReportsWhatItIsWorkingTowards() {
        let goal = StudyGoal(name: "Physics", date: Date().addingTimeInterval(4 * 86_400), deckIDs: [])
        let plan = StudyPlanner(settings: settings(goals: [goal]), secondsPerCard: 8)
            .plan(for: [deck("A", due: 5)])
        XCTAssertEqual(plan.goal?.name, "Physics")
    }

    /// Anchored to a fixed hour rather than whatever time the suite happens to run.
    ///
    /// Counting in seconds made this depend on the wall clock: 1.2 days after nine in the
    /// evening is two calendar days away, so the same assertion passed in the morning and
    /// failed at night. A countdown is measured in days on a calendar, not in seconds.
    func testCountdownReadsNaturally() {
        let calendar = Calendar.current
        let now = calendar.date(byAdding: .hour, value: 9, to: calendar.startOfDay(for: Date()))!

        func goal(inDays days: Int, atHour hour: Int) -> StudyGoal {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            return StudyGoal(name: "x", date: calendar.date(byAdding: .hour, value: hour, to: day)!,
                             deckIDs: [])
        }

        XCTAssertEqual(goal(inDays: 0, atHour: 9).countdown(from: now), "today")
        XCTAssertEqual(goal(inDays: 1, atHour: 23).countdown(from: now), "tomorrow",
                       "late tomorrow is still tomorrow")
        XCTAssertEqual(goal(inDays: 4, atHour: 14).countdown(from: now), "in 4 days")
        XCTAssertEqual(goal(inDays: 7, atHour: 9).countdown(from: now), "in 7 days",
                       "a week out still reads in days; weeks start at a fortnight")
        XCTAssertEqual(goal(inDays: 14, atHour: 9).countdown(from: now), "in 2 weeks")
        XCTAssertEqual(goal(inDays: 21, atHour: 9).countdown(from: now), "in 3 weeks")
        XCTAssertEqual(goal(inDays: -1, atHour: 9).countdown(from: now), "passed")
    }

    func testOldSettingsWithoutGoalsStillDecode() throws {
        let legacy = """
        {"isEnabled":true,"deckIDs":[],"slots":[{"hour":8,"minute":0}],
         "maximumSessionMinutes":20,"nudgeAfterDays":2,"nudgeBelowRecall":0.7}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(StudyPlanSettings.self, from: legacy)
        XCTAssertTrue(decoded.isEnabled)
        XCTAssertEqual(decoded.goals, [], "an update must not discard an existing plan")
        XCTAssertEqual(decoded.maximumSessionMinutes, 20)
    }
}
