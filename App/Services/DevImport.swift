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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-remove-cards") { removeCards(context: context, profile: profile) }
        if arguments.contains("-rewrite-handwriting") { rewriteHandwriting(context: context, profile: profile) }
        if arguments.contains("-import-cards") { importCards(context: context, profile: profile) }
        if arguments.contains("-name-report") { nameReport(profile: profile) }
    }

    /// Scores reading a card's name off its ink against the text that made that ink.
    ///
    /// Cards written out from typed text are the only place the truth is known, so they are
    /// the only honest measure of whether naming a handwritten card would work.
    private static func nameReport(profile: StoredProfile) {
        var scored = 0
        var exact = 0
        var total = 0.0
        for deck in profile.decks where deck.deletedAt == nil {
            for card in deck.cards where card.deletedAt == nil {
                guard let ink = card.frontDrawing else { continue }
                let read = InkNaming.read(ink) ?? ""
                if card.frontText.isEmpty {
                    print("[name] handwritten in \(deck.name): \(read.isEmpty ? "(nothing read)" : read)")
                    continue
                }
                let truth = card.frontText
                let score = similarity(read.lowercased(), truth.lowercased())
                scored += 1
                total += score
                if score > 0.999 { exact += 1 }
                if score < 0.9 {
                    print("[name] \(Int(score * 100))%  read: \(read)")
                    print("[name]        want: \(truth)")
                }
            }
        }
        if scored > 0 {
            print("[name] \(scored) composed cards: \(exact) read exactly, average \(Int(total / Double(scored) * 100))% of characters")
        }
    }

    /// How much of `want` survives in `got`, by longest common subsequence.
    private static func similarity(_ got: String, _ want: String) -> Double {
        let a = Array(got), b = Array(want)
        guard !b.isEmpty else { return a.isEmpty ? 1 : 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = previous
        for i in 1...max(a.count, 1) where !a.isEmpty {
            for j in 1...b.count {
                current[j] = a[i - 1] == b[j - 1] ? previous[j - 1] + 1 : max(previous[j], current[j - 1])
            }
            swap(&previous, &current)
        }
        return Double(previous[b.count]) / Double(b.count)
    }

    /// Soft-deletes typed cards in a deck whose question matches a pattern.
    /// `REMOVE_DECK`, `REMOVE_PATTERN` (a regular expression tested against the question).
    private static func removeCards(context: ModelContext, profile: StoredProfile) {
        let environment = ProcessInfo.processInfo.environment
        guard let deckName = environment["REMOVE_DECK"], let pattern = environment["REMOVE_PATTERN"],
              let regex = try? NSRegularExpression(pattern: pattern),
              let deck = profile.decks.first(where: { $0.name == deckName && $0.deletedAt == nil })
        else { print("[remove] needs REMOVE_DECK and a valid REMOVE_PATTERN"); return }
        var removed = 0
        for card in deck.cards where card.deletedAt == nil && !card.frontText.isEmpty {
            let range = NSRange(card.frontText.startIndex..., in: card.frontText)
            if regex.firstMatch(in: card.frontText, range: range) != nil {
                card.deletedAt = Date()
                removed += 1
            }
        }
        try? context.save()
        print("[remove] removed \(removed) from \(deckName)")
    }

    /// Writes every typed side out again in the captured hand, so a change to the composer
    /// reaches cards that already exist.
    private static func rewriteHandwriting(context: ModelContext, profile: StoredProfile) {
        let handwriting = HandwritingStore(context: context)
        guard handwriting.capturedCount() > 0 else { print("[rewrite] no alphabet"); return }
        var rewritten = 0
        for deck in profile.decks where deck.deletedAt == nil {
            for card in deck.cards where card.deletedAt == nil {
                if !card.frontText.isEmpty {
                    card.frontDrawing = handwriting.compose(card.frontText, maxWidth: 680).drawing.dataRepresentation()
                }
                if !card.backText.isEmpty {
                    card.backDrawing = handwriting.compose(card.backText, maxWidth: 680).drawing.dataRepresentation()
                }
                if !card.frontText.isEmpty || !card.backText.isEmpty {
                    card.modifiedAt = Date()
                    rewritten += 1
                }
            }
        }
        try? context.save()
        print("[rewrite] rewrote \(rewritten) cards")
    }

    /// `IMPORT_DECK`, `IMPORT_CSV`; set `IMPORT_CREATE_DECK` to make the deck if it is missing.
    private static func importCards(context: ModelContext, profile: StoredProfile) {
        let environment = ProcessInfo.processInfo.environment
        guard let deckName = environment["IMPORT_DECK"],
              let csv = environment["IMPORT_CSV"], !csv.isEmpty else {
            print("[import] needs IMPORT_DECK and IMPORT_CSV")
            return
        }
        let deck: StoredDeck
        if let found = profile.decks.first(where: { $0.name == deckName && $0.deletedAt == nil }) {
            deck = found
        } else if environment["IMPORT_CREATE_DECK"] != nil {
            deck = StoredDeck(name: deckName, profile: profile)
            context.insert(deck)
        } else {
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
