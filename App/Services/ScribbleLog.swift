import Foundation
import FlashcardsCore

/// Records what each stroke actually measured, so the scribble thresholds can be set from
/// real handwriting instead of guesses.
///
/// The first attempts at these numbers were guesses, and they were wrong in both
/// directions — too eager, then too strict to fire at all. This writes the measurements to
/// a file that can be read off the device, so the next set of numbers comes from evidence.
enum ScribbleLog {
    /// Keep the file small; only recent strokes are interesting.
    private static let maximumLines = 200
    private nonisolated(unsafe) static var lines: [String] = []

    static var fileURL: URL {
        URL.documentsDirectory.appendingPathComponent("scribble-log.txt")
    }

    static func record(_ m: ScribbleDetector.Measurement) {
        let line = String(
            format: "%@  len=%.0f diag=%.0f density=%.2f elong=%.2f rev=%d dur=%.2fs speed=%.0f  %@",
            ISO8601DateFormatter().string(from: Date()),
            m.length, m.density, m.elongation, m.reversals, m.duration, m.speed, m.overlap,
            m.isScribble ? "ERASED" : "kept (\(m.rejectedBy ?? "?"))"
        )
        lines.append(line)
        if lines.count > maximumLines { lines.removeFirst(lines.count - maximumLines) }
        try? lines.joined(separator: "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
