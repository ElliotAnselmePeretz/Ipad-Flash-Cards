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

        var out: [String] = []
        for (index, line) in kept.enumerated() {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let isHeading = line.characterWidth >= headingSize
            // A heading only starts a card when something follows it to be the answer.
            if isHeading, index > 0, index < kept.count - 1 {
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
