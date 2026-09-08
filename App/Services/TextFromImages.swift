import Foundation
import UIKit
import Vision
import FlashcardsCore

/// Reads the words off a screenshot.
///
/// Recognition happens on the device, in the same way the rest of the app works: nothing is
/// uploaded, there is nothing to pay for, and it works with no signal.
enum TextFromImages {

    /// Lines of one picture, in reading order, each with how tall it was drawn.
    static func read(_ image: UIImage) throws -> [ScannedLine] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: image.imageOrientation.cgOrientation,
                                            options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        return observations
            // Vision returns boxes with the origin at the bottom, so reading order is
            // downwards then across.
            .sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.005 {
                    return a.boundingBox.midY > b.boundingBox.midY
                }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return ScannedLine(text: text,
                                   characterWidth: observation.boundingBox.width / CGFloat(max(text.count, 1)))
            }
    }

    /// Every picture, read in the order they were chosen and shaped into cards.
    static func studyText(from images: [UIImage]) -> String {
        let pages = images.compactMap { try? read($0) }
        return ScannedText.studyText(fromPages: pages)
    }
}

private extension UIImage.Orientation {
    /// Vision works in Core Graphics orientations; a screenshot taken sideways is otherwise
    /// read sideways.
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: .up
        case .down: .down
        case .left: .left
        case .right: .right
        case .upMirrored: .upMirrored
        case .downMirrored: .downMirrored
        case .leftMirrored: .leftMirrored
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
