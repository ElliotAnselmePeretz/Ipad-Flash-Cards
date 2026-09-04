import Foundation

/// A small RFC 4180 CSV reader.
///
/// Written by hand rather than split on commas because real exports contain quoted
/// fields with commas, newlines and doubled quotes inside them — and a flashcard deck
/// is exactly the kind of file where a question contains a comma.
public struct CSVParser: Sendable {
    public enum Delimiter: String, Sendable, CaseIterable {
        case comma = ","
        case semicolon = ";"
        case tab = "\t"

        public var character: Character { Character(rawValue) }
    }

    public let delimiter: Delimiter

    public init(delimiter: Delimiter = .comma) {
        self.delimiter = delimiter
    }

    /// Swift treats "\r\n" as a single Character, so it matches neither "\r" nor "\n".
    /// Normalising once up front is simpler than special-casing the grapheme everywhere.
    private static func normalizingNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Guesses the delimiter by counting candidates outside quoted regions on the first line.
    public static func detectDelimiter(in text: String) -> Delimiter {
        let normalized = normalizingNewlines(text)
        let firstLine = normalized.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        var counts: [Delimiter: Int] = [:]
        var inQuotes = false
        for ch in firstLine {
            if ch == "\"" { inQuotes.toggle(); continue }
            guard !inQuotes else { continue }
            for d in Delimiter.allCases where ch == d.character {
                counts[d, default: 0] += 1
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? .comma
    }

    /// Splits the text into rows of fields. Handles quoted fields, doubled quotes,
    /// embedded newlines, a UTF-8 BOM, and both LF and CRLF line endings.
    public func rows(from text: String) -> [[String]] {
        var text = Self.normalizingNewlines(text)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            // Ignore the trailing empty row a final newline produces.
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil

            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") }   // escaped quote
                        else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }

            switch ch {
            case "\"" where field.isEmpty:
                inQuotes = true
            case delimiter.character:
                endField()
            case "\n":
                endRow()
            default:
                field.append(ch)
            }
        }

        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
