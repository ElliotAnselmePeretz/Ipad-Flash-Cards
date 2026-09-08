import Foundation
import UIKit
import PencilKit
import Vision
import SwiftData
import FlashcardsCore

/// Reads a short name off the ink on a card.
///
/// A handwritten card has no words in the database, so the card list can only call it
/// "(handwritten)". This reads the front with the device's own text recognition and uses
/// the opening words as a title — enough to tell one card from another in a list.
///
/// It is deliberately only a *name*: recognition of handwriting is good, not perfect, and a
/// misread title costs nothing, whereas a misread answer would be studied and learnt wrong.
/// Nothing here touches what a card teaches.
enum InkNaming {

    /// Ink is stored light for PencilKit's own dark-mode handling, so it is rendered on
    /// white at a generous scale: recognition wants dark marks on a pale ground.
    static func render(_ drawing: PKDrawing, targetWidth: CGFloat = 1400) -> UIImage? {
        let bounds = drawing.bounds.insetBy(dx: -16, dy: -16)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let scale = min(max(targetWidth / bounds.width, 1), 6)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)

        let traits = UITraitCollection(userInterfaceStyle: .light)
        var image: UIImage?
        traits.performAsCurrent {
            image = renderer.image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: bounds.size))
                drawing.image(from: bounds, scale: scale)
                    .draw(in: CGRect(origin: .zero, size: bounds.size))
            }
        }
        return image
    }

    /// Everything recognition could read on the ink, in reading order.
    static func read(_ data: Data) -> String? {
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty,
              let image = render(drawing), let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])) != nil
        else { return nil }

        let lines = (request.results ?? [])
            .sorted { a, b in
                if abs(a.boundingBox.midY - b.boundingBox.midY) > 0.02 {
                    return a.boundingBox.midY > b.boundingBox.midY
                }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }

        let joined = lines.joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    /// Gives a handwritten card a title, unless it has words of its own or one already.
    ///
    /// Recognition takes long enough to be felt, so it happens off the main thread and the
    /// card is updated when it comes back. Nothing waits for it: a card is usable the moment
    /// it is written, and the title appears a moment later.
    @MainActor
    static func nameInBackground(_ card: StoredCard, context: ModelContext) {
        guard card.frontText.isEmpty, card.readName.isEmpty, let ink = card.frontDrawing else { return }
        Task {
            guard let name = await Task.detached(priority: .utility, operation: {
                InkNaming.name(from: ink)
            }).value else { return }
            guard card.deletedAt == nil, card.readName.isEmpty else { return }
            card.readName = name
            try? context.save()
        }
    }

    /// A title's worth of it: the first few words, cut at a word boundary.
    static func name(from data: Data, wordLimit: Int = 8, characterLimit: Int = 60) -> String? {
        guard let text = read(data) else { return nil }
        var words = text.split(separator: " ").prefix(wordLimit).map(String.init)
        while words.count > 1, words.joined(separator: " ").count > characterLimit {
            words.removeLast()
        }
        let name = words.joined(separator: " ")
        return name.count >= 2 ? name : nil
    }
}
