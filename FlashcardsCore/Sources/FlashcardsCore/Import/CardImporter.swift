import Foundation

/// How a CSV's columns map onto cards.
public struct ImportPlan: Sendable, Equatable {
    public var hasHeaderRow: Bool
    /// Column supplying the question.
    public var frontColumn: Int
    /// Column supplying the answer, or `nil` to leave every answer blank so it can be
    /// handwritten. This is the point of the whole importer for a Pencil-first deck:
    /// bring in the prompts, write the answers yourself.
    public var backColumn: Int?
    /// Skip rows whose question already exists in the deck.
    public var skipDuplicates: Bool

    public init(hasHeaderRow: Bool = true, frontColumn: Int = 0, backColumn: Int? = 1, skipDuplicates: Bool = true) {
        self.hasHeaderRow = hasHeaderRow
        self.frontColumn = frontColumn
        self.backColumn = backColumn
        self.skipDuplicates = skipDuplicates
    }

    /// The prompts-only plan: one column of questions, answers left for the Pencil.
    public static let handwrittenAnswers = ImportPlan(hasHeaderRow: true, frontColumn: 0, backColumn: nil)
}

/// What the import screen shows before committing anything.
public struct ImportPreview: Sendable, Equatable {
    /// Header names when present, otherwise "Column 1", "Column 2"…
    public var columnNames: [String]
    public var sampleRows: [[String]]
    public var totalRows: Int
    public var looksLikeHeaderRow: Bool

    public init(columnNames: [String], sampleRows: [[String]], totalRows: Int, looksLikeHeaderRow: Bool) {
        self.columnNames = columnNames
        self.sampleRows = sampleRows
        self.totalRows = totalRows
        self.looksLikeHeaderRow = looksLikeHeaderRow
    }
}

public struct ImportResult: Sendable {
    public var cards: [Card]
    public var skippedDuplicates: Int
    public var skippedEmpty: Int

    public var importedCount: Int { cards.count }
}

public struct CardImporter: Sendable {

    public init() {}

    private static let headerWords: Set<String> = [
        "front", "back", "question", "answer", "term", "definition",
        "prompt", "response", "word", "meaning", "q", "a"
    ]

    /// Reads the file well enough to show the user what they are about to import.
    public func preview(text: String, delimiter: CSVParser.Delimiter? = nil, sampleLimit: Int = 5) -> ImportPreview {
        let d = delimiter ?? CSVParser.detectDelimiter(in: text)
        let rows = CSVParser(delimiter: d).rows(from: text)
        guard let first = rows.first else {
            return ImportPreview(columnNames: [], sampleRows: [], totalRows: 0, looksLikeHeaderRow: false)
        }

        let isHeader = first.allSatisfy { field in
            let f = field.trimmingCharacters(in: .whitespaces).lowercased()
            return !f.isEmpty && Self.headerWords.contains(f)
        }

        let names = isHeader
            ? first.map { $0.trimmingCharacters(in: .whitespaces) }
            : (0..<first.count).map { "Column \($0 + 1)" }

        let body = isHeader ? Array(rows.dropFirst()) : rows
        return ImportPreview(
            columnNames: names,
            sampleRows: Array(body.prefix(sampleLimit)),
            totalRows: body.count,
            looksLikeHeaderRow: isHeader
        )
    }

    /// Turns rows into cards. Nothing is persisted here — the caller decides.
    public func makeCards(
        text: String,
        plan: ImportPlan,
        deckID: UUID,
        profileID: UUID,
        existingFronts: Set<String> = [],
        delimiter: CSVParser.Delimiter? = nil,
        now: Date = Date()
    ) -> ImportResult {
        let d = delimiter ?? CSVParser.detectDelimiter(in: text)
        var rows = CSVParser(delimiter: d).rows(from: text)
        if plan.hasHeaderRow, !rows.isEmpty { rows.removeFirst() }

        var cards: [Card] = []
        var seen = existingFronts
        var duplicates = 0
        var empty = 0

        for (offset, row) in rows.enumerated() {
            guard plan.frontColumn < row.count else { empty += 1; continue }
            let front = row[plan.frontColumn].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty else { empty += 1; continue }

            if plan.skipDuplicates {
                let key = front.lowercased()
                if seen.contains(key) { duplicates += 1; continue }
                seen.insert(key)
            }

            // A nil backColumn deliberately leaves the answer empty, ready for ink.
            var back = ""
            if let bc = plan.backColumn, bc < row.count {
                back = row[bc].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            cards.append(Card(
                deckID: deckID,
                profileID: profileID,
                front: CardSide(text: front),
                back: CardSide(text: back),
                // Stagger creation dates so the queue introduces them in file order.
                createdAt: now.addingTimeInterval(Double(offset) / 1000)
            ))
        }

        return ImportResult(cards: cards, skippedDuplicates: duplicates, skippedEmpty: empty)
    }
}
