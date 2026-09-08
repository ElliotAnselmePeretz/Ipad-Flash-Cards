import Foundation
import CoreGraphics

/// One line of text read off a picture, with how large it was drawn.
public struct ScannedLine: Sendable, Equatable {
    public var text: String
    /// How wide each character was drawn, as a fraction of the page width.
    ///
    /// This stands in for font size. The obvious measure — the height of the line's box —
    /// is not dependable: recognition boxes a line containing a `g` or a `y` taller than one
    /// without, so `Infiltration` measures shorter than `Drainage basin` set in the same
    /// heading font, and the section boundary is missed. Averaged across a line, width per
    /// character tracks the type size and barely moves with which letters happen to be in it.
    public var characterWidth: CGFloat

    public init(text: String, characterWidth: CGFloat) {
        self.text = text
        self.characterWidth = characterWidth
    }
}

/// Turns lines read off a page into text shaped like flashcards.
///
/// A screenshot of study material is a heading followed by what it means, over and over.
/// Recognition gives back a flat list of lines, so the shape has to come from how the page
/// looks: a heading is drawn larger than the body under it, and that is the boundary
/// between one card and the next. Blank lines are inserted at those boundaries, which is
/// the same shape a person types by hand, so the pasted-card reader handles it unchanged.
public enum ScannedText {

    /// Lines that are numbering or page furniture rather than something to learn.
    private static let furniture = try! NSRegularExpression(
        pattern: #"^\s*(?:page\s*)?\d+\s*$"#, options: [.caseInsensitive])

    /// A short line shouted in capitals is a heading whatever size it is set at.
    private static func isShoutedHeading(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count <= 5, text.count >= 2 else { return false }
        guard text.contains(where: \.isLetter) else { return false }
        return !text.contains(where: { $0.isLowercase })
    }

    /// `Term: what it means`, all on one line.
    private static func splitOnColon(_ text: String) -> (term: String, meaning: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let term = text[..<colon].trimmingCharacters(in: .whitespaces)
        let meaning = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        // A term is a label, not a sentence, and it has to be defined as something.
        guard !term.isEmpty, term.count <= 60, term.split(separator: " ").count <= 6,
              !meaning.isEmpty else { return nil }
        return (term, meaning)
    }

    public static func studyText(from lines: [ScannedLine]) -> String {
        let kept = lines.filter { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { return false }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return furniture.firstMatch(in: trimmed, range: range) == nil
        }
        guard !kept.isEmpty else { return "" }

        // A heading stands out from the body around it; with nothing to stand out from,
        // every line is body and the page becomes one card. The median is a body line
        // whenever body text outnumbers headings, which is what a page of notes looks like.
        let sizes = kept.map(\.characterWidth).sorted()
        let body = sizes[sizes.count / 2]
        let headingSize = body * 1.18

        func isHeading(_ line: ScannedLine) -> Bool {
            line.characterWidth >= headingSize || isShoutedHeading(line.text.trimmingCharacters(in: .whitespaces))
        }

        // A glossary sets every line the same size and marks the term with a colon instead,
        // so there is no larger type to go on and the colon is the boundary.
        let defined = kept.compactMap { splitOnColon($0.text.trimmingCharacters(in: .whitespaces)) }
        if kept.filter(isHeading).count < 2, defined.count >= 2, defined.count * 10 >= kept.count * 6 {
            return defined.map { "\($0.term)\n\($0.meaning)" }.joined(separator: "\n\n")
        }

        var out: [String] = []
        for (index, line) in kept.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            // A heading only starts a card when something follows it to be the answer.
            if isHeading(line), index > 0, index < kept.count - 1 {
                out.append("")
            }
            out.append(text)
        }
        return out.joined(separator: "\n")
    }

    /// Several pages, read in the order they were chosen.
    public static func studyText(fromPages pages: [[ScannedLine]]) -> String {
        pages.map { studyText(from: $0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
