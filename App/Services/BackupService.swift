import Foundation
import SwiftData
import FlashcardsCore

/// Moves the whole library in and out of a single file.
///
/// Cards are handwriting: they cannot be retyped from memory, and until now they existed
/// in exactly one place. This is the copy.
struct BackupService {
    let context: ModelContext
    private let coder = ArchiveCoder()

    // MARK: - Export

    func makeArchive(for profile: StoredProfile) -> DeckArchive {
        let decks = profile.decks
            .filter { $0.deletedAt == nil }
            .sorted { $0.createdAt < $1.createdAt }
            .map { deck in
                ArchivedDeck(
                    id: deck.id,
                    name: deck.name,
                    newCardsPerDay: deck.newCardsPerDay,
                    maximumReviewsPerDay: deck.maximumReviewsPerDay,
                    createdAt: deck.createdAt,
                    cards: deck.cards
                        .filter { $0.deletedAt == nil }
                        .sorted { $0.createdAt < $1.createdAt }
                        .map(archived)
                )
            }
        return DeckArchive(decks: decks).normalized()
    }

    private func archived(_ card: StoredCard) -> ArchivedCard {
        ArchivedCard(
            id: card.id,
            frontText: card.frontText,
            backText: card.backText,
            frontDrawing: card.frontDrawing,
            backDrawing: card.backDrawing,
            scheduling: card.scheduling,
            createdAt: card.createdAt,
            modifiedAt: card.modifiedAt,
            reviews: card.reviewLogs
                .sorted { $0.reviewedAt < $1.reviewedAt }
                .map { log in
                    ArchivedReview(
                        id: log.id,
                        reviewedAt: log.reviewedAt,
                        grade: log.grade,
                        intervalBefore: log.intervalBefore,
                        intervalAfter: log.intervalAfter,
                        easeAfter: log.easeAfter,
                        durationSeconds: log.durationSeconds
                    )
                }
        )
    }

    func exportData(for profile: StoredProfile) throws -> Data {
        try coder.encode(makeArchive(for: profile))
    }

    /// Writes the backup to a temporary file so it can be handed to the share sheet.
    func writeArchiveFile(for profile: StoredProfile) throws -> URL {
        let data = try exportData(for: profile)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(coder.suggestedFilename())
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Import

    struct ImportSummary: Equatable {
        var decksAdded = 0
        var cardsAdded = 0
        var reviewsAdded = 0
        var decksSkipped = 0
    }

    @discardableResult
    func restore(_ data: Data, into profile: StoredProfile,
                 strategy: ImportStrategy = .addAlongside) throws -> ImportSummary {
        let archive = try coder.decode(data)
        var summary = ImportSummary()

        let existingDeckIDs = Set(profile.decks.filter { $0.deletedAt == nil }.map(\.id))

        for archivedDeck in archive.decks {
            if strategy == .skipExisting, existingDeckIDs.contains(archivedDeck.id) {
                summary.decksSkipped += 1
                continue
            }

            // Restoring alongside gives fresh identifiers, so importing the same file
            // twice produces two decks rather than silently merging into one.
            let isDuplicate = existingDeckIDs.contains(archivedDeck.id)
            let deck = StoredDeck(
                id: isDuplicate ? UUID() : archivedDeck.id,
                name: isDuplicate ? "\(archivedDeck.name) (restored)" : archivedDeck.name,
                profile: profile
            )
            deck.newCardsPerDay = archivedDeck.newCardsPerDay
            deck.maximumReviewsPerDay = archivedDeck.maximumReviewsPerDay
            deck.createdAt = archivedDeck.createdAt
            context.insert(deck)
            summary.decksAdded += 1

            for archivedCard in archivedDeck.cards {
                let card = StoredCard(
                    id: isDuplicate ? UUID() : archivedCard.id,
                    deck: deck,
                    frontText: archivedCard.frontText,
                    backText: archivedCard.backText
                )
                card.frontDrawing = archivedCard.frontDrawing
                card.backDrawing = archivedCard.backDrawing
                card.createdAt = archivedCard.createdAt
                card.modifiedAt = archivedCard.modifiedAt
                // Set last: assigning scheduling also stamps modifiedAt.
                card.scheduling = archivedCard.scheduling
                context.insert(card)
                summary.cardsAdded += 1

                for archivedReview in archivedCard.reviews {
                    let log = StoredReviewLog(
                        card: card,
                        reviewedAt: archivedReview.reviewedAt,
                        grade: archivedReview.grade,
                        intervalBefore: archivedReview.intervalBefore,
                        intervalAfter: archivedReview.intervalAfter,
                        easeAfter: archivedReview.easeAfter,
                        durationSeconds: archivedReview.durationSeconds,
                        attemptDrawing: nil
                    )
                    log.id = isDuplicate ? UUID() : archivedReview.id
                    context.insert(log)
                    summary.reviewsAdded += 1
                }
            }
        }

        try context.save()
        return summary
    }
}
