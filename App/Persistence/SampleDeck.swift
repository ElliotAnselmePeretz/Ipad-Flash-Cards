import Foundation
import SwiftData

/// A starter deck, so a new profile has something to study instead of an empty screen.
///
/// The questions are typed and every answer is left blank on purpose: writing the answers
/// is the point of the app, and it puts a new user straight into the Pencil the first time
/// they open a card.
enum SampleDeck {

    static let name = "Derivatives (sample)"

    /// Chosen because they are quicker to write than to type — which is the case for
    /// handwriting flashcards in the first place.
    static let questions = [
        "the derivative of sin x",
        "the derivative of cos x",
        "the derivative of tan x",
        "the derivative of ln x",
        "the derivative of eˣ",
        "the derivative of xⁿ",
        "the derivative of √x",
        "the product rule for u·v",
        "the chain rule for f(g(x))",
        "the derivative of arctan x"
    ]

    /// Adds the sample deck to a profile. Does nothing if that profile already has one.
    @discardableResult
    static func add(to profile: StoredProfile, in context: ModelContext) -> StoredDeck? {
        guard !profile.decks.contains(where: { $0.name == name && $0.deletedAt == nil }) else {
            return nil
        }

        let deck = StoredDeck(name: name, profile: profile)
        context.insert(deck)

        let start = Date()
        for (index, question) in questions.enumerated() {
            let card = StoredCard(deck: deck, frontText: question)
            // Stagger creation so new cards are introduced in this order.
            card.createdAt = start.addingTimeInterval(Double(index) / 1000)
            context.insert(card)
        }

        try? context.save()
        return deck
    }
}
