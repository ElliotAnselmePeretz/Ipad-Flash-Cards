import XCTest

/// Exercises the statistics screen, which nothing had ever opened.
final class StatsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
    }

    // MARK: - Setup helpers

    private func openNewDeck(profile: String = "Elliot", deck: String = "Derivatives") {
        app.buttons["Add profile"].tap()
        let pf = app.alerts.textFields.firstMatch
        _ = pf.waitForExistence(timeout: 5); pf.tap(); pf.typeText(profile)
        app.alerts.buttons["Create"].tap()

        app.buttons["New deck"].tap()
        let df = app.alerts.textFields.firstMatch
        _ = df.waitForExistence(timeout: 5); df.tap(); df.typeText(deck)
        app.alerts.buttons["Create"].tap()

        _ = app.staticTexts[deck].waitForExistence(timeout: 10)
        app.staticTexts[deck].tap()
        _ = app.buttons["Statistics"].waitForExistence(timeout: 10)
    }

    private func addCard(front: String, back: String) {
        app.buttons["Cards"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)
        app.buttons["Add card"].tap()

        let f = app.textFields["Question (optional)"]
        _ = f.waitForExistence(timeout: 10)
        f.tap(); f.typeText(front)
        app.segmentedControls.buttons["Answer"].tap()
        let b = app.textFields["Answer (optional)"]
        _ = b.waitForExistence(timeout: 5)
        b.tap(); b.typeText(back)

        app.buttons["Save"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)
        app.buttons["Done"].tap()
    }

    private func openStats() {
        app.buttons["Statistics"].tap()
        XCTAssertTrue(app.navigationBars["Statistics"].waitForExistence(timeout: 10),
                      "the statistics screen should open")
    }

    private func stat(_ id: String) -> String {
        let el = app.staticTexts[id]
        guard el.waitForExistence(timeout: 5) else { return "<missing \(id)>" }
        return el.label
    }

    private func gradeButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    // MARK: - Tests

    func testStatsOpenOnAnEmptyDeckWithoutCrashing() {
        openNewDeck()
        openStats()
        XCTAssertEqual(stat("stat.cards"), "0")
        XCTAssertEqual(stat("stat.reviews"), "0")
        XCTAssertEqual(stat("stat.mature"), "0")
    }

    func testRetentionShowsAPlaceholderBeforeAnyReviews() {
        openNewDeck()
        openStats()
        XCTAssertEqual(stat("stat.retention"), "—",
                       "retention should show a placeholder, not vanish, before there is data")
    }

    func testBothChartSectionsAreShown() {
        openNewDeck()
        openStats()
        XCTAssertTrue(app.staticTexts["Reviews, last 30 days"].exists)
        XCTAssertTrue(app.staticTexts["Due, next 30 days"].exists)
    }

    func testCardCountReflectsAddedCards() {
        openNewDeck()
        addCard(front: "the derivative of sin x", back: "cos x")
        openStats()
        XCTAssertEqual(stat("stat.cards"), "1")
        XCTAssertEqual(stat("stat.reviews"), "0", "adding a card is not a review")
    }

    func testReviewCountIncrementsAfterGrading() {
        openNewDeck()
        addCard(front: "the derivative of sin x", back: "cos x")

        _ = app.buttons["Show answer"].waitForExistence(timeout: 10)
        app.buttons["Show answer"].tap()
        _ = gradeButton("Easy").waitForExistence(timeout: 5)
        gradeButton("Easy").tap()
        _ = app.staticTexts["All caught up"].waitForExistence(timeout: 10)

        openStats()
        XCTAssertEqual(stat("stat.reviews"), "1", "grading a card should record one review")
        XCTAssertEqual(stat("stat.cards"), "1")
    }

    func testDeletingACardRemovesItAndItsReviewsFromStats() {
        openNewDeck()
        addCard(front: "the derivative of sin x", back: "cos x")

        // Study it once so it has review history to leave behind.
        _ = app.buttons["Show answer"].waitForExistence(timeout: 10)
        app.buttons["Show answer"].tap()
        _ = gradeButton("Easy").waitForExistence(timeout: 5)
        gradeButton("Easy").tap()
        _ = app.staticTexts["All caught up"].waitForExistence(timeout: 10)

        // Delete the card.
        app.buttons["Cards"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)
        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "the card should be listed")
        cell.swipeLeft()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "swiping should reveal Delete")
        delete.tap()
        app.buttons["Done"].tap()

        openStats()
        XCTAssertEqual(stat("stat.cards"), "0", "a deleted card should not be counted")
        XCTAssertEqual(stat("stat.reviews"), "0",
                       "reviews belonging to a deleted card should not be counted either")
    }

    func testMatureCountStaysZeroForAYoungCard() {
        openNewDeck()
        addCard(front: "the derivative of sin x", back: "cos x")

        _ = app.buttons["Show answer"].waitForExistence(timeout: 10)
        app.buttons["Show answer"].tap()
        _ = gradeButton("Easy").waitForExistence(timeout: 5)
        gradeButton("Easy").tap()
        _ = app.staticTexts["All caught up"].waitForExistence(timeout: 10)

        openStats()
        // Easy graduates to a 4-day interval; mature means 21 days or more.
        XCTAssertEqual(stat("stat.mature"), "0", "a 4-day card is not mature yet")
    }
}
