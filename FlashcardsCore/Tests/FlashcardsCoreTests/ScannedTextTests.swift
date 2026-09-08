import XCTest
@testable import FlashcardsCore

final class ScannedTextTests: XCTestCase {

    private func page(_ items: [(String, CGFloat)]) -> [ScannedLine] {
        items.map { ScannedLine(text: $0.0, characterWidth: $0.1) }
    }

    func testAHeadingStartsANewCard() {
        let lines = page([
            ("The hydrological cycle", 0.012),
            ("Water moves between stores by evaporation,", 0.009),
            ("condensation and precipitation.", 0.009),
            ("Drainage basins", 0.012),
            ("An area drained by a river and its tributaries.", 0.009),
        ])
        let text = ScannedText.studyText(from: lines)
        let cards = PastedCardParser.parse(text)
        XCTAssertEqual(cards.cards.count, 2, "each heading begins a card")
        XCTAssertEqual(cards.cards[0].question, "The hydrological cycle")
        XCTAssertEqual(cards.cards[0].answer,
                       "Water moves between stores by evaporation,\ncondensation and precipitation.")
        XCTAssertEqual(cards.cards[1].question, "Drainage basins")
    }

    func testPageNumbersAndFurnitureAreDropped() {
        let lines = page([("88", 0.012), ("Infiltration", 0.012),
                          ("Water soaking into soil.", 0.009), ("Page 89", 0.012)])
        let text = ScannedText.studyText(from: lines)
        XCTAssertFalse(text.contains("88"))
        XCTAssertFalse(text.contains("Page 89"))
        XCTAssertTrue(text.contains("Infiltration"))
    }

    func testUniformTextBecomesOneCardRatherThanManyFragments() {
        let lines = page([("Evaporation", 0.009), ("is water turning to vapour.", 0.009),
                          ("It needs energy from the sun.", 0.009)])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.count, 1,
                       "with no heading to go on, the page is one card rather than nonsense")
    }

    func testATrailingHeadingIsNotLeftAsAnAnswerlessCard() {
        let lines = page([("Runoff", 0.012), ("Water flowing over the surface.", 0.009),
                          ("Next section", 0.012)])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.count, 1)
        XCTAssertTrue(cards.cards[0].answer.contains("Next section"),
                      "a heading with nothing under it cannot be a question")
    }

    func testSeveralPagesKeepTheirOrder() {
        let first = page([("Alpha", 0.03), ("First meaning.", 0.009)])
        let second = page([("Beta", 0.03), ("Second meaning.", 0.009)])
        let cards = PastedCardParser.parse(ScannedText.studyText(fromPages: [first, second]))
        XCTAssertEqual(cards.cards.map(\.question), ["Alpha", "Beta"])
    }

    /// Heights measured by running text recognition over a rendered textbook page, so the
    /// heading threshold is checked against what recognition actually returns rather than
    /// against numbers chosen to pass.
    func testARealRecognisedPageSplitsIntoItsSections() {
        let lines = page([
            ("88", 0.01235),
            ("The global hydrological cycle", 0.01514),
            ("Water moves between stores by evaporation,", 0.00972),
            ("condensation, precipitation and runoff.", 0.00891),
            ("It is a closed system driven by the sun.", 0.00876),
            ("Drainage basin", 0.01588),
            ("An area of land drained by a river and its", 0.00876),
            ("tributaries, bounded by a watershed.", 0.00925),
            // Set in the same heading font as the two above, but boxed shorter because it
            // has no descender: this is the case a height-based rule gets wrong.
            ("Infiltration", 0.01284),
            ("The movement of water from the surface into", 0.00940),
            ("the soil beneath it", 0.00864),
        ])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.map(\.question),
                       ["The global hydrological cycle", "Drainage basin", "Infiltration"])
        XCTAssertEqual(cards.cards[1].answer,
                       "An area of land drained by a river and its\ntributaries, bounded by a watershed.")
    }

    /// A glossary: one line per term, nothing set larger, the colon doing the work.
    /// Measured by recognising a rendered page of it.
    func testAGlossaryOfTermAndMeaningBecomesOneCardEach() {
        let lines = page([
            ("Osmosis: movement of water across a partially permeable membrane.", 0.00970),
            ("Diffusion: movement of particles from high to low concentration.", 0.00890),
            ("Active transport: movement against a gradient, using energy.", 0.00916),
            ("Mitosis: cell division producing two identical daughter cells.", 0.00851),
        ])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.map(\.question),
                       ["Osmosis", "Diffusion", "Active transport", "Mitosis"])
        XCTAssertEqual(cards.cards[0].answer,
                       "movement of water across a partially permeable membrane.")
    }

    /// Capitals mark the heading where type size does not.
    func testHeadingsShoutedInCapitalsAreStillHeadings() {
        let lines = page([
            ("OSMOSIS", 0.01371), ("Movement of water across a membrane.", 0.01005),
            ("DIFFUSION", 0.01213), ("High to low concentration.", 0.00900),
            ("MITOSIS", 0.01186), ("Two identical daughter cells.", 0.00887),
        ])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.map(\.question), ["OSMOSIS", "DIFFUSION", "MITOSIS"])
    }

    /// A sentence that happens to contain a colon is not a definition, and a page of prose
    /// must not be shredded into a card per line.
    func testProseWithColonsIsNotTreatedAsAGlossary() {
        let lines = page([
            ("The cycle has three stages: evaporation, condensation and precipitation.", 0.009),
            ("Water moves between stores continuously.", 0.009),
            ("It is driven by energy from the sun.", 0.009),
        ])
        let cards = PastedCardParser.parse(ScannedText.studyText(from: lines))
        XCTAssertEqual(cards.cards.count, 1,
                       "one long line with a colon in it is not a term and its meaning")
    }

    func testAnEmptyScanIsSafe() {
        XCTAssertEqual(ScannedText.studyText(from: []), "")
        XCTAssertEqual(ScannedText.studyText(fromPages: [[], []]), "")
    }
}
