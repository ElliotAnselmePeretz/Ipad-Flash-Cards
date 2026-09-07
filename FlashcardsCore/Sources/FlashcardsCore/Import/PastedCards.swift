import Foundation

/// One question and answer lifted out of pasted text.
public struct PastedCard: Sendable, Equatable {
    public var question: String
    public var answer: String

    public init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

/// What a paste turned out to contain.
public struct PastedCards: Sendable, Equatable {
    public enum Format: String, Sendable {
        /// `QUESTION … ANSWER …` labels, however they are spelled or punctuated.
        case labelled
        /// An Anki text export, or notes copied straight out of it.
        case anki
        /// Two columns, separated by tabs, commas or semicolons.
        case table
        /// Blocks separated by blank lines: first line the question, the rest the answer.
        case blocks
        case empty
    }

    public var cards: [PastedCard]
    public var format: Format
    /// Pieces that had no question in them, so nothing could be made of them.
    public var skipped: Int

    public init(cards: [PastedCard], format: Format, skipped: Int = 0) {
        self.cards = cards
        self.format = format
        self.skipped = skipped
    }
}

/// Reads flashcards out of whatever got pasted.
///
/// People arrive with text from all over — an Anki export, a study guide with QUESTION and
/// ANSWER written out, a two-column table, notes with a blank line between each pair. The
/// text decides which reading applies; nothing has to be chosen up front.
public enum PastedCardParser {

    public static func parse(_ text: String) -> PastedCards {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        // Anki writes its settings at the top of an export as `#key:value` lines.
        var separator: Character?
        var html = false
        var sawDirective = false
        lines.removeAll { line in
            guard line.hasPrefix("#"), let colon = line.firstIndex(of: ":") else { return false }
            sawDirective = true
            let key = line[line.index(after: line.startIndex)..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
            switch key {
            case "separator":
                separator = ["tab": "\t", "comma": ",", "semicolon": ";", "pipe": "|", "colon": ":"][value]
                    ?? value.first
            case "html":
                html = value == "true"
            default:
                break
            }
            return true
        }

        let body = lines.joined(separator: "\n")
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PastedCards(cards: [], format: .empty)
        }

        // Raw Anki fields are joined with U+001F; that alone settles it.
        if body.contains("\u{1F}") {
            return table(body, separator: "\u{1F}", format: .anki, html: true)
        }
        if let separator {
            return table(body, separator: separator, format: .anki, html: html || sawDirective)
        }
        if let result = labelled(body) {
            return result
        }
        if let result = detectedTable(body) {
            return result
        }
        return blocks(body)
    }

    // MARK: - QUESTION / ANSWER

    private static let questionLabel = try! NSRegularExpression(
        pattern: #"^\s*(?:question|q|frage|pregunta)\s*\d*\s*[:.)\-–—]?\s*(.*)$"#,
        options: [.caseInsensitive])
    private static let answerLabel = try! NSRegularExpression(
        pattern: #"^\s*(?:answer|a|ans|antwort|respuesta)\s*\d*\s*[:.)\-–—]?\s*(.*)$"#,
        options: [.caseInsensitive])
    /// An answer label further along the same line as the question.
    private static let inlineAnswer = try! NSRegularExpression(
        pattern: #"\s+(?:answer|ans|a)\s*[:\-–—]\s*"#, options: [.caseInsensitive])

    private static func labelled(_ text: String) -> PastedCards? {
        var cards: [PastedCard] = []
        var skipped = 0
        var question: [String]?
        var answer: [String]?
        var sawQuestion = false, sawAnswer = false

        func flush() {
            if let q = question {
                let joined = clean(q.joined(separator: "\n"), html: false)
                if joined.isEmpty { skipped += 1 }
                else { cards.append(PastedCard(question: joined,
                                               answer: clean((answer ?? []).joined(separator: "\n"), html: false))) }
            } else if answer != nil {
                skipped += 1
            }
            question = nil
            answer = nil
        }

        for line in text.components(separatedBy: "\n") {
            if let rest = match(questionLabel, line) {
                flush()
                sawQuestion = true
                // "Question: x  Answer: y" on one line.
                let range = NSRange(rest.startIndex..., in: rest)
                if let split = inlineAnswer.firstMatch(in: rest, range: range),
                   let r = Range(split.range, in: rest) {
                    question = [String(rest[..<r.lowerBound])]
                    answer = [String(rest[r.upperBound...])]
                    sawAnswer = true
                } else {
                    question = [rest]
                }
            } else if let rest = match(answerLabel, line) {
                sawAnswer = true
                answer = [rest]
            } else if answer != nil {
                answer?.append(line)
            } else if question != nil {
                question?.append(line)
            }
        }
        flush()

        guard sawQuestion, sawAnswer, !cards.isEmpty else { return nil }
        return PastedCards(cards: cards, format: .labelled, skipped: skipped)
    }

    private static func match(_ regex: NSRegularExpression, _ line: String) -> String? {
        // A bare "a" or "q" at the start of an ordinary sentence is not a label; it needs
        // punctuation or the full word to count.
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, range: range),
              let whole = Range(m.range, in: line),
              let restRange = Range(m.range(at: 1), in: line) else { return nil }
        let head = line[whole.lowerBound..<restRange.lowerBound].lowercased()
        let bare = head.trimmingCharacters(in: .whitespaces)
        if bare.count <= 1 { return nil }            // "a cat sat" is not "A: cat sat"
        return String(line[restRange])
    }

    // MARK: - Tables

    private static func detectedTable(_ text: String) -> PastedCards? {
        let rows = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard rows.count >= 1 else { return nil }
        // Tabs are unambiguous; commas and semicolons only count if every line has one.
        if rows.filter({ $0.contains("\t") }).count * 2 > rows.count {
            return table(text, separator: "\t", format: .table, html: false)
        }
        let delimiter = CSVParser.detectDelimiter(in: text)
        guard delimiter != .tab else { return nil }
        let parsed = CSVParser(delimiter: delimiter).rows(from: text)
        guard parsed.count == rows.count, parsed.allSatisfy({ $0.count >= 2 }) else { return nil }
        // A sentence has commas too. Exported data puts nothing after the separator, or
        // quotes its fields; prose puts a space. Either tell settles it.
        let machineMade = rows.filter { line in
            line.contains("\"") || line.contains("\(delimiter.rawValue)\(delimiter.rawValue)")
                || zip(line, line.dropFirst()).contains { $0 == delimiter.character && $1 != " " }
        }
        let header = CardImporter().preview(text: text, delimiter: delimiter).looksLikeHeaderRow
        guard header || machineMade.count * 2 >= rows.count else { return nil }
        return table(text, separator: delimiter.character, format: .table, html: false)
    }

    private static func table(_ text: String, separator: Character,
                              format: PastedCards.Format, html: Bool) -> PastedCards {
        var rows: [[String]]
        if let delimiter = CSVParser.Delimiter(rawValue: String(separator)) {
            rows = CSVParser(delimiter: delimiter).rows(from: text)
        } else {
            rows = text.components(separatedBy: "\n").map { $0.split(separator: separator, omittingEmptySubsequences: false).map(String.init) }
        }
        rows.removeAll { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        if let first = rows.first, CardImporter().preview(text: first.joined(separator: "\t"), delimiter: .tab).looksLikeHeaderRow {
            rows.removeFirst()
        }

        var cards: [PastedCard] = []
        var skipped = 0
        for row in rows {
            let question = clean(row.first ?? "", html: html)
            guard !question.isEmpty else { skipped += 1; continue }
            let answer = clean(row.count > 1 ? row[1] : "", html: html)
            cards.append(PastedCard(question: question, answer: answer))
        }
        return PastedCards(cards: cards, format: format, skipped: skipped)
    }

    // MARK: - Blocks

    private static func blocks(_ text: String) -> PastedCards {
        var cards: [PastedCard] = []
        var skipped = 0
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            guard let first = lines.first else { continue }
            let question = clean(first, html: false)
            guard !question.isEmpty else { skipped += 1; continue }
            cards.append(PastedCard(question: question,
                                    answer: clean(lines.dropFirst().joined(separator: "\n"), html: false)))
        }
        return PastedCards(cards: cards, format: .blocks, skipped: skipped)
    }

    // MARK: - Cleaning

    private static let tag = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let lineBreakTag = try! NSRegularExpression(
        pattern: #"<\s*(?:br|/p|/div|/li|/tr)\s*/?\s*>"#, options: [.caseInsensitive])
    private static let cloze = try! NSRegularExpression(pattern: #"\{\{c\d+::(.*?)(?:::[^}]*)?\}\}"#)
    private static let numericEntity = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)

    /// Text as a person would write it out: no markup, entities spelled as characters, and
    /// the `||` some people use to separate points turned into separate lines.
    static func clean(_ raw: String, html: Bool) -> String {
        var text = raw
        if html || text.contains("<") || text.contains("&") {
            text = replace(lineBreakTag, in: text, with: "\n")
            text = replace(tag, in: text, with: "")
            text = decodeEntities(text)
        }
        text = replace(cloze, in: text, with: "$1")
        text = text.replacingOccurrences(of: "||", with: "\n")
        text = text.replacingOccurrences(of: "\u{A0}", with: " ")

        // Tidy each line, drop empty ones, collapse runs of spaces.
        let lines = text.components(separatedBy: "\n").map { line in
            line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                       withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        var out = text
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        let matches = numericEntity.matches(in: out, range: NSRange(out.startIndex..., in: out))
        for m in matches.reversed() {
            guard let whole = Range(m.range, in: out), let digits = Range(m.range(at: 2), in: out),
                  let hex = Range(m.range(at: 1), in: out) else { continue }
            let radix = out[hex].isEmpty ? 10 : 16
            if let code = UInt32(out[digits], radix: radix), let scalar = Unicode.Scalar(code) {
                out.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return out
    }
}
