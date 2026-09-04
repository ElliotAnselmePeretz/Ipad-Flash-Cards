import XCTest

/// Drives the app the way a person would: make a profile, make a deck, write a card,
/// study it. These run in the simulator with no human at the keyboard, which is the
/// only way the view layer gets exercised on a machine with no iPad attached.
final class StudyFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Start from an empty store every time, so tests don't depend on each other.
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
    }

    // MARK: - Helpers

    @discardableResult
    private func createProfile(named name: String) -> Bool {
        let add = app.buttons["Add profile"]
        guard add.waitForExistence(timeout: 10) else { return false }
        add.tap()

        let field = app.alerts.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else { return false }
        field.tap()
        field.typeText(name)
        app.alerts.buttons["Create"].tap()
        return true
    }

    @discardableResult
    private func createDeck(named name: String) -> Bool {
        let newDeck = app.buttons["New deck"]
        guard newDeck.waitForExistence(timeout: 10) else { return false }
        newDeck.tap()

        let field = app.alerts.textFields.firstMatch
        guard field.waitForExistence(timeout: 5) else { return false }
        field.tap()
        field.typeText(name)
        app.alerts.buttons["Create"].tap()
        return true
    }

    /// Grade buttons stack a title and the next interval, so their accessibility label can
    /// read either "Again" or "Again, 1m" depending on how SwiftUI flattens them. Match on
    /// the prefix so the test doesn't depend on that detail.
    private func gradeButton(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    // MARK: - Tests

    func testProfilePickerIsFirstScreen() {
        XCTAssertTrue(app.staticTexts["Who's studying?"].waitForExistence(timeout: 10),
                      "the profile gate should be the first thing shown")
        XCTAssertTrue(app.buttons["Add profile"].exists)
    }

    func testCreatingAProfileOpensItsDeckList() {
        XCTAssertTrue(createProfile(named: "Elliot"), "could not create a profile")
        XCTAssertTrue(app.navigationBars["Elliot"].waitForExistence(timeout: 10),
                      "creating a profile should drop straight into that profile's decks")
        XCTAssertTrue(app.staticTexts["No decks yet"].exists, "a new profile should have no decks")
    }

    func testCreatingADeckShowsItInTheList() {
        createProfile(named: "Elliot")
        XCTAssertTrue(createDeck(named: "Derivatives"), "could not create a deck")
        XCTAssertTrue(app.staticTexts["Derivatives"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["No decks yet"].exists)
    }

    func testEmptyDeckSaysNothingIsDue() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.staticTexts["Derivatives"].tap()
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 10),
                      "an empty deck should land on the caught-up screen, not a blank one")
    }

    func testAddingACardThenStudyingIt() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.staticTexts["Derivatives"].tap()

        // Open the card manager and add one card.
        app.buttons["Cards"].tap()
        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 10))
        app.buttons["Add card"].tap()

        let front = app.textFields["Question (optional)"]
        XCTAssertTrue(front.waitForExistence(timeout: 10), "card editor should open on the front side")
        front.tap()
        front.typeText("the derivative of sin x")

        app.segmentedControls.buttons["Answer"].tap()
        let back = app.textFields["Answer (optional)"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        back.typeText("cos x")

        app.buttons["Save"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 5)
        app.buttons["Done"].tap()

        // The card should now be waiting to be studied.
        XCTAssertTrue(app.staticTexts["the derivative of sin x"].waitForExistence(timeout: 10),
                      "the new card should appear as the current question")
        XCTAssertTrue(app.buttons["Show answer"].exists)
    }

    func testRevealingAnAnswerShowsTheFourGradeButtons() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.staticTexts["Derivatives"].tap()
        addOneCard(front: "the derivative of sin x", back: "cos x")

        app.buttons["Show answer"].tap()

        for label in ["Again", "Hard", "Good", "Easy"] {
            XCTAssertTrue(gradeButton(label).waitForExistence(timeout: 5),
                          "the \(label) button should appear once the answer is revealed")
        }
        XCTAssertTrue(app.staticTexts["cos x"].exists, "the correct answer should be shown")
        XCTAssertFalse(app.buttons["Show answer"].exists, "reveal button should be gone after revealing")
    }

    func testGradingACardAdvancesPastIt() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.staticTexts["Derivatives"].tap()
        addOneCard(front: "the derivative of sin x", back: "cos x")

        app.buttons["Show answer"].tap()
        XCTAssertTrue(gradeButton("Easy").waitForExistence(timeout: 5))
        gradeButton("Easy").tap()

        // Answered Easy, the card graduates to a 4-day interval, so nothing is left today.
        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 10),
                      "grading the only card Easy should empty the queue")
    }

    func testAgainKeepsTheCardInTheSession() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.staticTexts["Derivatives"].tap()
        addOneCard(front: "the derivative of sin x", back: "cos x")

        app.buttons["Show answer"].tap()
        XCTAssertTrue(gradeButton("Again").waitForExistence(timeout: 5))
        gradeButton("Again").tap()

        // "Again" schedules the card a minute out, so it should come straight back.
        XCTAssertTrue(app.staticTexts["the derivative of sin x"].waitForExistence(timeout: 10),
                      "a card answered Again should return within the same session")
        XCTAssertFalse(app.staticTexts["All caught up"].exists)
    }

    func testSwitchingProfilesReturnsToThePicker() {
        createProfile(named: "Elliot")
        app.buttons["Switch profile"].tap()
        XCTAssertTrue(app.staticTexts["Who's studying?"].waitForExistence(timeout: 10))
    }

    func testSecondProfileHasItsOwnDecks() {
        createProfile(named: "Elliot")
        createDeck(named: "Derivatives")
        app.buttons["Switch profile"].tap()

        XCTAssertTrue(app.buttons["Add profile"].waitForExistence(timeout: 10))
        createProfile(named: "Sam")

        XCTAssertTrue(app.navigationBars["Sam"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No decks yet"].exists,
                      "a second profile must not see the first profile's decks")
        XCTAssertFalse(app.staticTexts["Derivatives"].exists)
    }

    // MARK: - Shared setup

    private func addOneCard(front: String, back: String) {
        app.buttons["Cards"].tap()
        app.buttons["Add card"].tap()

        let f = app.textFields["Question (optional)"]
        _ = f.waitForExistence(timeout: 10)
        f.tap(); f.typeText(front)

        app.segmentedControls.buttons["Answer"].tap()
        let b = app.textFields["Answer (optional)"]
        _ = b.waitForExistence(timeout: 5)
        b.tap(); b.typeText(back)

        app.buttons["Save"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 5)
        app.buttons["Done"].tap()
        _ = app.buttons["Show answer"].waitForExistence(timeout: 10)
    }
}
