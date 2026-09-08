import Foundation
import SwiftData
import PencilKit
import FlashcardsCore

/// Adds cards to a named deck from CSV handed in at launch.
///
/// Dev-only, and inert unless the app is started with `-import-cards`, which only a debugger
/// or `devicectl` can pass. It exists because getting a file onto the iPad is the awkward
/// part of importing: this hands the text straight to the same importer the Import screen
/// uses, so the cards arrive through SwiftData with every invariant intact rather than by
/// editing the store underneath the app.
enum DevImport {

    static func runIfRequested(context: ModelContext, profile: StoredProfile) {
        guard ProcessInfo.processInfo.arguments.contains("-import-cards") else { return }
        let environment = ProcessInfo.processInfo.environment
        guard let deckName = environment["IMPORT_DECK"],
              let csv = environment["IMPORT_CSV"], !csv.isEmpty else {
            print("[import] needs IMPORT_DECK and IMPORT_CSV")
            return
        }
        guard let deck = profile.decks.first(where: { $0.name == deckName && $0.deletedAt == nil })
        else {
            print("[import] no deck named \(deckName)")
            return
        }

        let existing = Set(deck.cards.filter { $0.deletedAt == nil }
            .map { $0.frontText.lowercased() })
        let result = CardImporter().makeCards(
            text: csv, plan: ImportPlan(), deckID: deck.id, profileID: profile.id,
            existingFronts: existing)

        let handwriting = HandwritingStore(context: context)
        let canWrite = handwriting.capturedCount() > 0

        for card in result.cards {
            let stored = StoredCard(deck: deck, frontText: card.front.text, backText: card.back.text)
            stored.createdAt = card.createdAt
            if canWrite {
                stored.frontDrawing = handwriting.compose(card.front.text, maxWidth: 680)
                    .drawing.dataRepresentation()
                if !card.back.text.isEmpty {
                    stored.backDrawing = handwriting.compose(card.back.text, maxWidth: 680)
                        .drawing.dataRepresentation()
                }
            }
            context.insert(stored)
        }
        try? context.save()

        let live = deck.cards.filter { $0.deletedAt == nil }.count
        print("[import] added \(result.importedCount) to \(deckName)"
              + " (skipped \(result.skippedDuplicates) duplicate, \(result.skippedEmpty) blank)"
              + "; deck now holds \(live); handwriting \(canWrite ? "on" : "off")")
    }
}
