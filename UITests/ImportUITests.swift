import XCTest

/// Covers the import screen. The file picker itself is a system component that cannot be
/// driven from a UI test, so the file's contents are injected and everything after that
/// — parsing, column mapping, the handwriting option, and the actual insert — is real.
final class ImportUITests: XCTestCase {

    var app: XCUIApplication!

    private func launch(csv: String) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launchEnvironment["UITEST_CSV"] = csv
        app.launch()
    }

    private func openImportScreen() {
        app.buttons["Add profile"].tap()
        let pf = app.alerts.textFields.firstMatch
        _ = pf.waitForExistence(timeout: 5); pf.tap(); pf.typeText("Elliot")
        app.alerts.buttons["Create"].tap()

        app.buttons["New deck"].tap()
        let df = app.alerts.textFields.firstMatch
        _ = df.waitForExistence(timeout: 5); df.tap(); df.typeText("Derivatives")
        app.alerts.buttons["Create"].tap()

        _ = app.staticTexts["Derivatives"].waitForExistence(timeout: 10)
        app.staticTexts["Derivatives"].tap()
        _ = app.buttons["Cards"].waitForExistence(timeout: 10)
        app.buttons["Cards"].tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)
        app.buttons["Import"].tap()
        XCTAssertTrue(app.navigationBars["Import cards"].waitForExistence(timeout: 10))
    }

    /// The Import button states the count, and unlike a row buried in the Form it is
    /// always on screen and always rendered.
    private var importButton: XCUIElement { app.buttons["import.confirm"] }

    /// A Toggle inside a Form only responds to a tap on the switch itself, not the row,
    /// so aim at the trailing edge and confirm the value actually changed.
    private func setHandwriting(_ on: Bool) {
        let toggle = app.switches["import.handwriteToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        guard (toggle.value as? String) != (on ? "1" : "0") else { return }
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let expected = on ? "1" : "0"
        let changed = NSPredicate(format: "value == %@", expected)
        expectation(for: changed, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
    }

    private var willImportCount: String {
        guard importButton.waitForExistence(timeout: 5) else { return "<missing button>" }
        let label = importButton.label
        return label.hasPrefix("Import ")
            ? String(label.dropFirst("Import ".count))
            : "0"
    }

    // MARK: - Tests

    func testPreviewCountsRowsFromTheFile() {
        launch(csv: "Question,Answer\nsin x,cos x\nln x,1/x\ntan x,sec^2 x")
        openImportScreen()
        XCTAssertEqual(willImportCount, "3")
    }

    func testHandwritingIsTheDefault() {
        launch(csv: "Question,Answer\nsin x,cos x")
        openImportScreen()
        let toggle = app.switches["import.handwriteToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1",
                       "handwriting answers should be the default for a Pencil deck")
        XCTAssertTrue(app.staticTexts["handwritten"].exists,
                      "the preview should show the answer will be handwritten")
    }

    func testImportedCardsHaveQuestionsAndBlankAnswers() {
        launch(csv: "Question,Answer\nsin x,cos x\nln x,1/x")
        openImportScreen()
        importButton.tap()

        // Back on the card list, both questions should be listed.
        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["sin x"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ln x"].exists)

        // Studying one should show the question with an empty answer to write into.
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Show answer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Write your answer"].exists,
                      "an imported card should present a blank canvas for the answer")
    }

    func testTurningOffHandwritingImportsTypedAnswers() {
        launch(csv: "Question,Answer\nsin x,cos x")
        openImportScreen()
        setHandwriting(false)
        importButton.tap()

        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        _ = app.buttons["Show answer"].waitForExistence(timeout: 10)
        app.buttons["Show answer"].tap()
        XCTAssertTrue(app.staticTexts["cos x"].waitForExistence(timeout: 5),
                      "with handwriting off, the answer column should be imported as text")
    }

    func testDuplicateQuestionsAreSkipped() {
        launch(csv: "Question\nsin x\nsin x\nln x")
        openImportScreen()
        XCTAssertEqual(willImportCount, "2", "the repeated question should be skipped")
    }

    func testSingleColumnFileImportsFine() {
        launch(csv: "Question\nsin x\nln x\ntan x")
        openImportScreen()
        XCTAssertEqual(willImportCount, "3")
        importButton.tap()
        XCTAssertTrue(app.navigationBars["Cards"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["tan x"].waitForExistence(timeout: 5))
    }

    func testQuotedFieldsSurviveTheRoundTrip() {
        launch(csv: "Question\n\"the derivative of sin x, in full\"")
        openImportScreen()
        importButton.tap()
        XCTAssertTrue(app.staticTexts["the derivative of sin x, in full"].waitForExistence(timeout: 10),
                      "a quoted field containing a comma must import as one question")
    }

    func testImportingTwiceSkipsWhatIsAlreadyThere() {
        launch(csv: "Question\nsin x\nln x")
        openImportScreen()
        importButton.tap()
        _ = app.navigationBars["Cards"].waitForExistence(timeout: 10)

        app.buttons["Import"].tap()
        _ = app.navigationBars["Import cards"].waitForExistence(timeout: 10)
        XCTAssertEqual(willImportCount, "0",
                       "re-importing the same file should add nothing")
    }
}
