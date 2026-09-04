import XCTest
@testable import FlashcardsCore

final class CSVParserTests: XCTestCase {

    func testPlainRows() {
        let rows = CSVParser().rows(from: "a,b\nc,d")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }

    func testQuotedFieldWithComma() {
        let rows = CSVParser().rows(from: "\"one, two\",three")
        XCTAssertEqual(rows, [["one, two", "three"]])
    }

    func testEscapedQuotesInsideQuotedField() {
        let rows = CSVParser().rows(from: "\"she said \"\"hi\"\"\",next")
        XCTAssertEqual(rows, [["she said \"hi\"", "next"]])
    }

    func testEmbeddedNewlineInsideQuotedField() {
        let rows = CSVParser().rows(from: "\"line one\nline two\",after")
        XCTAssertEqual(rows, [["line one\nline two", "after"]])
    }

    func testCarriageReturnLineEndings() {
        let rows = CSVParser().rows(from: "a,b\r\nc,d\r\n")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }

    func testTrailingNewlineDoesNotProduceAnEmptyRow() {
        XCTAssertEqual(CSVParser().rows(from: "a,b\n").count, 1)
    }

    func testByteOrderMarkIsStripped() {
        let rows = CSVParser().rows(from: "\u{FEFF}front,back")
        XCTAssertEqual(rows, [["front", "back"]])
    }

    func testEmptyFieldsArePreserved() {
        XCTAssertEqual(CSVParser().rows(from: "a,,c"), [["a", "", "c"]])
    }

    func testDelimiterDetection() {
        XCTAssertEqual(CSVParser.detectDelimiter(in: "a;b;c"), .semicolon)
        XCTAssertEqual(CSVParser.detectDelimiter(in: "a\tb\tc"), .tab)
        XCTAssertEqual(CSVParser.detectDelimiter(in: "a,b,c"), .comma)
    }

    func testDelimiterDetectionIgnoresCommasInsideQuotes() {
        XCTAssertEqual(CSVParser.detectDelimiter(in: "\"a,a,a,a\";b"), .semicolon,
                       "commas inside a quoted field must not win the vote")
    }
}

final class CardImporterTests: XCTestCase {

    let deckID = UUID()
    let profileID = UUID()
    let importer = CardImporter()

    func testPreviewDetectsHeaderRow() {
        let p = importer.preview(text: "Question,Answer\nsin x,cos x")
        XCTAssertTrue(p.looksLikeHeaderRow)
        XCTAssertEqual(p.columnNames, ["Question", "Answer"])
        XCTAssertEqual(p.totalRows, 1)
    }

    func testPreviewNamesColumnsWhenThereIsNoHeader() {
        let p = importer.preview(text: "sin x,cos x\nln x,1/x")
        XCTAssertFalse(p.looksLikeHeaderRow)
        XCTAssertEqual(p.columnNames, ["Column 1", "Column 2"])
        XCTAssertEqual(p.totalRows, 2, "without a header, every row is data")
    }

    func testImportsFrontAndBack() {
        let r = importer.makeCards(
            text: "Question,Answer\nsin x,cos x\nln x,1/x",
            plan: ImportPlan(), deckID: deckID, profileID: profileID
        )
        XCTAssertEqual(r.importedCount, 2)
        XCTAssertEqual(r.cards[0].front.text, "sin x")
        XCTAssertEqual(r.cards[0].back.text, "cos x")
    }

    // The case this importer exists for: prompts in, answers handwritten later.
    func testHandwrittenAnswersPlanLeavesBacksEmpty() {
        let r = importer.makeCards(
            text: "Question\nsin x\nln x\ntan x",
            plan: .handwrittenAnswers, deckID: deckID, profileID: profileID
        )
        XCTAssertEqual(r.importedCount, 3)
        XCTAssertTrue(r.cards.allSatisfy { !$0.front.text.isEmpty }, "questions should import")
        XCTAssertTrue(r.cards.allSatisfy { $0.back.isEmpty }, "answers must be left blank for ink")
    }

    func testHandwrittenPlanIgnoresASecondColumnIfPresent() {
        let r = importer.makeCards(
            text: "Question,Answer\nsin x,cos x",
            plan: .handwrittenAnswers, deckID: deckID, profileID: profileID
        )
        XCTAssertEqual(r.cards.first?.back.text, "", "choosing handwritten answers must ignore the answer column")
    }

    func testImportedCardsAreNewAndDueImmediately() {
        let r = importer.makeCards(text: "Question\nsin x", plan: .handwrittenAnswers,
                                   deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.cards.first?.scheduling.phase, .new)
        XCTAssertEqual(r.cards.first?.scheduling.repetitions, 0)
    }

    func testCardsKeepFileOrder() {
        let r = importer.makeCards(text: "Question\nfirst\nsecond\nthird",
                                   plan: .handwrittenAnswers, deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.cards.map(\.front.text), ["first", "second", "third"])
        XCTAssertTrue(r.cards[0].createdAt < r.cards[1].createdAt,
                      "creation order drives the order new cards are introduced")
    }

    func testBlankRowsAreSkipped() {
        let r = importer.makeCards(text: "Question\nsin x\n\n   \nln x",
                                   plan: .handwrittenAnswers, deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.importedCount, 2)
        XCTAssertGreaterThan(r.skippedEmpty, 0)
    }

    func testDuplicatesWithinTheFileAreSkipped() {
        let r = importer.makeCards(text: "Question\nsin x\nsin x\nSIN X",
                                   plan: .handwrittenAnswers, deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.importedCount, 1, "duplicate questions should collapse, case-insensitively")
        XCTAssertEqual(r.skippedDuplicates, 2)
    }

    func testDuplicatesAgainstExistingCardsAreSkipped() {
        let r = importer.makeCards(text: "Question\nsin x\nln x", plan: .handwrittenAnswers,
                                   deckID: deckID, profileID: profileID,
                                   existingFronts: ["sin x"])
        XCTAssertEqual(r.importedCount, 1)
        XCTAssertEqual(r.cards.first?.front.text, "ln x")
    }

    func testDuplicatesCanBeAllowed() {
        var plan = ImportPlan.handwrittenAnswers
        plan.skipDuplicates = false
        let r = importer.makeCards(text: "Question\nsin x\nsin x", plan: plan,
                                   deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.importedCount, 2)
    }

    func testRowsShorterThanTheChosenColumnAreSkipped() {
        let r = importer.makeCards(text: "Question,Answer\nonly one column",
                                   plan: ImportPlan(frontColumn: 1, backColumn: nil),
                                   deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.importedCount, 0)
        XCTAssertEqual(r.skippedEmpty, 1)
    }

    func testSemicolonFileImports() {
        let r = importer.makeCards(text: "Question;Answer\nsin x;cos x",
                                   plan: ImportPlan(), deckID: deckID, profileID: profileID)
        XCTAssertEqual(r.cards.first?.front.text, "sin x")
        XCTAssertEqual(r.cards.first?.back.text, "cos x")
    }

    func testEveryImportedCardBelongsToTheTargetDeckAndProfile() {
        let r = importer.makeCards(text: "Question\na\nb", plan: .handwrittenAnswers,
                                   deckID: deckID, profileID: profileID)
        XCTAssertTrue(r.cards.allSatisfy { $0.deckID == deckID && $0.profileID == profileID })
    }
}
