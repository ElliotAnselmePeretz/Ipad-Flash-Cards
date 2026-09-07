import XCTest
@testable import FlashcardsCore

final class PastedCardsTests: XCTestCase {

    // MARK: - QUESTION / ANSWER

    func testLabelledPairs() {
        let text = """
        QUESTION: What is marginal utility?
        ANSWER: The extra satisfaction from one more unit.

        QUESTION: What is a leech?
        ANSWER: A card you keep forgetting.
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.format, .labelled)
        XCTAssertEqual(result.cards, [
            PastedCard(question: "What is marginal utility?", answer: "The extra satisfaction from one more unit."),
            PastedCard(question: "What is a leech?", answer: "A card you keep forgetting."),
        ])
    }

    func testLabelsAreForgivingAboutCaseNumberingAndPunctuation() {
        let text = """
        Question 1 - What is GDP?
        Answer 1 - Total output of an economy.
        q2) Define inflation
        a2) A general rise in prices
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.format, .labelled)
        XCTAssertEqual(result.cards.map(\.question), ["What is GDP?", "Define inflation"])
        XCTAssertEqual(result.cards.map(\.answer), ["Total output of an economy.", "A general rise in prices"])
    }

    func testAnswersMaySpanSeveralLines() {
        let text = """
        QUESTION: Steps of neurotransmission?
        ANSWER: Release
        Diffusion
        Binding
        QUESTION: Next
        ANSWER: Done
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.cards.first?.answer, "Release\nDiffusion\nBinding")
        XCTAssertEqual(result.cards.count, 2)
    }

    func testQuestionAndAnswerOnOneLine() {
        let result = PastedCardParser.parse("Question: Capital of France? Answer: Paris\nQuestion: Of Spain? Answer: Madrid")
        XCTAssertEqual(result.format, .labelled)
        XCTAssertEqual(result.cards, [PastedCard(question: "Capital of France?", answer: "Paris"),
                                      PastedCard(question: "Of Spain?", answer: "Madrid")])
    }

    func testAnOrdinarySentenceStartingWithAIsNotALabel() {
        let text = """
        QUESTION: What is schema theory?
        ANSWER: A mental shortcut
        a restaurant script is the usual example
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards.first?.answer, "A mental shortcut\na restaurant script is the usual example")
    }

    // MARK: - Anki

    /// A note as Anki actually stores it, fields joined by U+001F, with its HTML intact.
    func testARawAnkiNoteIsReadAndCleaned() {
        let raw = "Schema theory\u{1F}Def:Mental shot cut/past experiences||Types: script&nbsp;||Why:saves time --&gt; effort<br>"
        let result = PastedCardParser.parse(raw)
        XCTAssertEqual(result.format, .anki)
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.cards[0].question, "Schema theory")
        XCTAssertEqual(result.cards[0].answer, "Def:Mental shot cut/past experiences\nTypes: script\nWhy:saves time --> effort")
    }

    func testAnAnkiTextExportWithDirectives() {
        let export = """
        #separator:tab
        #html:true
        #tags column:3
        Neuroplasticity\tBrain's ability to reorganise<br>Pruning, neurogenesis\tbio
        Enculturation\tLearning cultural norms in childhood\tbio
        """
        let result = PastedCardParser.parse(export)
        XCTAssertEqual(result.format, .anki)
        XCTAssertEqual(result.cards.map(\.question), ["Neuroplasticity", "Enculturation"])
        XCTAssertEqual(result.cards[0].answer, "Brain's ability to reorganise\nPruning, neurogenesis")
    }

    func testClozeDeletionsKeepTheirText() {
        let result = PastedCardParser.parse("Term\u{1F}The {{c1::hippocampus::organ}} forms memories")
        XCTAssertEqual(result.cards.first?.answer, "The hippocampus forms memories")
    }

    // MARK: - Tables and blocks

    func testTabSeparatedColumns() {
        let result = PastedCardParser.parse("front\tback\nDog\tChien\nCat\tChat")
        XCTAssertEqual(result.format, .table)
        XCTAssertEqual(result.cards, [PastedCard(question: "Dog", answer: "Chien"),
                                      PastedCard(question: "Cat", answer: "Chat")],
                       "a header row is recognised and dropped")
    }

    func testCommaSeparatedColumns() {
        let result = PastedCardParser.parse("\"Hello, there\",Bonjour\nGoodbye,Au revoir")
        XCTAssertEqual(result.format, .table)
        XCTAssertEqual(result.cards.first, PastedCard(question: "Hello, there", answer: "Bonjour"))
    }

    func testBlocksSeparatedByBlankLines() {
        let text = """
        What is supply?
        How much producers offer
        at each price.

        What is demand?
        How much buyers want.
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.format, .blocks)
        XCTAssertEqual(result.cards, [
            PastedCard(question: "What is supply?", answer: "How much producers offer\nat each price."),
            PastedCard(question: "What is demand?", answer: "How much buyers want."),
        ])
    }

    func testProseWithCommasIsNotMistakenForATable() {
        let text = """
        What is supply, roughly?
        How much producers offer, at each price
        """
        let result = PastedCardParser.parse(text)
        XCTAssertEqual(result.format, .blocks, "a comma in a sentence is not a column")
    }

    // MARK: - Edges

    func testEmptyPaste() {
        XCTAssertEqual(PastedCardParser.parse("  \n\n ").format, .empty)
        XCTAssertTrue(PastedCardParser.parse("").cards.isEmpty)
    }

    func testWindowsLineEndings() {
        let result = PastedCardParser.parse("QUESTION: a?\r\nANSWER: b\r\nQUESTION: c?\r\nANSWER: d")
        XCTAssertEqual(result.cards.count, 2)
    }

    func testAnAnswerWithNoQuestionIsCountedNotInvented() {
        let result = PastedCardParser.parse("ANSWER: orphan\nQUESTION: real?\nANSWER: yes")
        XCTAssertEqual(result.cards.count, 1)
        XCTAssertEqual(result.skipped, 1)
    }
}
