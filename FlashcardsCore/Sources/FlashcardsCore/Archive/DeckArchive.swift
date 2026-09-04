import Foundation

/// A complete, self-contained copy of everything the app knows.
///
/// The point is that handwriting cannot be retyped. A lost deck is not an inconvenience,
/// it is hours of work gone, so the archive carries the ink itself — not a reference to
/// it — along with scheduling state and review history, so a restored deck resumes rather
/// than starting over.
public struct DeckArchive: Codable, Sendable, Equatable {
    /// Bumped whenever the shape changes, so a future version can migrate old files
    /// instead of refusing them.
    public static let currentVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var decks: [ArchivedDeck]

    public init(decks: [ArchivedDeck], exportedAt: Date = Date(), formatVersion: Int = DeckArchive.currentVersion) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.decks = decks
    }

    /// Rounds every timestamp to whole milliseconds, which is the precision the archive
    /// format stores. Applied before writing so that what is exported is exactly what a
    /// restore produces, with no drift hiding in the fractions.
    public func normalized() -> DeckArchive {
        func ms(_ date: Date) -> Date {
            Date(timeIntervalSince1970: ((date.timeIntervalSince1970 * 1000).rounded()) / 1000)
        }
        var copy = self
        copy.exportedAt = ms(exportedAt)
        copy.decks = decks.map { deck in
            var d = deck
            d.createdAt = ms(deck.createdAt)
            d.cards = deck.cards.map { card in
                var c = card
                c.createdAt = ms(card.createdAt)
                c.modifiedAt = ms(card.modifiedAt)
                c.scheduling.dueDate = ms(card.scheduling.dueDate)
                c.scheduling.lastReviewedAt = card.scheduling.lastReviewedAt.map(ms)
                c.reviews = card.reviews.map { review in
                    var r = review
                    r.reviewedAt = ms(review.reviewedAt)
                    return r
                }
                return c
            }
            return d
        }
        return copy
    }

    public var cardCount: Int { decks.reduce(0) { $0 + $1.cards.count } }
    public var reviewCount: Int { decks.reduce(0) { $0 + $1.cards.reduce(0) { $0 + $1.reviews.count } } }
}

public struct ArchivedDeck: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var newCardsPerDay: Int
    public var maximumReviewsPerDay: Int
    public var createdAt: Date
    public var cards: [ArchivedCard]

    public init(id: UUID, name: String, newCardsPerDay: Int, maximumReviewsPerDay: Int,
                createdAt: Date, cards: [ArchivedCard]) {
        self.id = id
        self.name = name
        self.newCardsPerDay = newCardsPerDay
        self.maximumReviewsPerDay = maximumReviewsPerDay
        self.createdAt = createdAt
        self.cards = cards
    }
}

public struct ArchivedCard: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var frontText: String
    public var backText: String
    /// PencilKit ink, carried whole. This is the part that cannot be recreated.
    public var frontDrawing: Data?
    public var backDrawing: Data?
    public var scheduling: SchedulingState
    public var createdAt: Date
    public var modifiedAt: Date
    public var reviews: [ArchivedReview]

    public init(id: UUID, frontText: String, backText: String,
                frontDrawing: Data?, backDrawing: Data?,
                scheduling: SchedulingState, createdAt: Date, modifiedAt: Date,
                reviews: [ArchivedReview]) {
        self.id = id
        self.frontText = frontText
        self.backText = backText
        self.frontDrawing = frontDrawing
        self.backDrawing = backDrawing
        self.scheduling = scheduling
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.reviews = reviews
    }
}

public struct ArchivedReview: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var reviewedAt: Date
    public var grade: ReviewGrade
    public var intervalBefore: Double
    public var intervalAfter: Double
    public var easeAfter: Double
    public var durationSeconds: Double

    public init(id: UUID, reviewedAt: Date, grade: ReviewGrade, intervalBefore: Double,
                intervalAfter: Double, easeAfter: Double, durationSeconds: Double) {
        self.id = id
        self.reviewedAt = reviewedAt
        self.grade = grade
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
        self.easeAfter = easeAfter
        self.durationSeconds = durationSeconds
    }
}

/// Reads and writes archives. Kept separate from the file system so it can be tested
/// without touching disk.
public struct ArchiveCoder: Sendable {

    public enum ArchiveError: Error, LocalizedError, Equatable {
        case notAnArchive
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notAnArchive:
                "That file isn't an Ink Recall backup."
            case .unsupportedVersion(let version):
                "This backup was made by a newer version of the app (format \(version))."
            }
        }
    }

    public init() {}

    public func encode(_ archive: DeckArchive) throws -> Data {
        let encoder = JSONEncoder()
        // Dates are stored as whole milliseconds since 1970. ISO-8601 truncates to whole
        // seconds and raw Doubles do not survive JSON exactly, and either way a restored
        // archive differed from the original. Integer milliseconds round-trip exactly, and
        // millisecond precision is far finer than anything scheduling depends on.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970 * 1000).rounded()))
        }
        // Sorted keys make two exports of unchanged data byte-identical, which makes it
        // obvious whether a backup actually changed.
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(archive)
    }

    public func decode(_ data: Data) throws -> DeckArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let milliseconds = try decoder.singleValueContainer().decode(Int64.self)
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        let archive: DeckArchive
        do {
            archive = try decoder.decode(DeckArchive.self, from: data)
        } catch {
            throw ArchiveError.notAnArchive
        }
        guard archive.formatVersion <= DeckArchive.currentVersion else {
            throw ArchiveError.unsupportedVersion(archive.formatVersion)
        }
        return archive
    }

    /// A filename that sorts chronologically and says what it is.
    public func suggestedFilename(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "InkRecall-\(formatter.string(from: now)).inkrecall"
    }
}

/// How an import should treat decks that already exist.
public enum ImportStrategy: String, Sendable, CaseIterable {
    /// Keep what is there and add the archive alongside it, with new identifiers.
    case addAlongside
    /// Skip anything whose identifier already exists.
    case skipExisting
}
