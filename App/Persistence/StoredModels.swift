import Foundation
import SwiftData
import FlashcardsCore

// SwiftData mirrors of the pure types in FlashcardsCore.
//
// Scheduling fields are stored FLAT rather than as a nested Codable value: SwiftData
// can persist a Codable struct, but #Predicate can't reach inside one, and "fetch the
// cards due before now" is the single most important query in the app.
//
// Ids are UUIDs generated on creation rather than declared with #Unique, which needs
// iOS 18 and would have to go anyway if this ever moves to CloudKit — CloudKit doesn't
// enforce unique constraints.

@Model
final class StoredProfile {
    var id: UUID = UUID()
    var name: String = ""
    var avatar: String = "person.circle"
    var dayStartHour: Int = 4
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \StoredDeck.profile)
    var decks: [StoredDeck] = []

    init(id: UUID = UUID(), name: String, avatar: String = "person.circle", dayStartHour: Int = 4) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.dayStartHour = dayStartHour
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

@Model
final class StoredDeck {
    var id: UUID = UUID()
    var name: String = ""
    var newCardsPerDay: Int = 20
    var maximumReviewsPerDay: Int = 200
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    var profile: StoredProfile?

    @Relationship(deleteRule: .cascade, inverse: \StoredCard.deck)
    var cards: [StoredCard] = []

    /// A deck can hold units: Phycology has Unit 1, Unit 2… Studying the deck draws from
    /// every unit; studying a unit draws from that unit alone.
    var parent: StoredDeck?

    @Relationship(deleteRule: .cascade, inverse: \StoredDeck.parent)
    var units: [StoredDeck] = []

    init(id: UUID = UUID(), name: String, profile: StoredProfile?, parent: StoredDeck? = nil) {
        self.id = id
        self.name = name
        self.profile = profile
        self.parent = parent
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    var isUnit: Bool { parent != nil }

    var liveUnits: [StoredDeck] {
        units.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    /// This deck and every unit beneath it.
    var family: [StoredDeck] { [self] + liveUnits.flatMap(\.family) }

    /// Every live card in this deck and its units.
    var allCards: [StoredCard] {
        family.flatMap { $0.cards.filter { $0.deletedAt == nil } }
    }

    /// Bridge to the pure type the scheduler and queue understand.
    var core: Deck {
        Deck(
            id: id,
            profileID: profile?.id ?? UUID(),
            name: name,
            newCardsPerDay: newCardsPerDay,
            maximumReviewsPerDay: maximumReviewsPerDay,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deletedAt: deletedAt
        )
    }
}

@Model
final class StoredCard {
    var id: UUID = UUID()

    var frontText: String = ""
    var backText: String = ""
    /// PKDrawing.dataRepresentation(). External storage keeps big ink blobs out of the
    /// main store file so card fetches stay fast.
    @Attribute(.externalStorage) var frontDrawing: Data?
    @Attribute(.externalStorage) var backDrawing: Data?

    // Flattened scheduling state — see the note at the top of this file.
    var phaseRaw: Int = 0          // 0 new, 1 learning, 2 review, 3 relearning
    var phaseStep: Int = 0
    var intervalDays: Double = 0
    var easeFactor: Double = 2.5
    /// FSRS memory model. Nil until the card has been answered once.
    var stability: Double?
    var difficulty: Double?
    /// Leeches are cards you keep forgetting; suspended ones leave the queue entirely.
    var isSuspended: Bool = false
    var isLeech: Bool = false
    var repetitions: Int = 0
    var lapses: Int = 0
    var dueDate: Date = Date()
    var lastReviewedAt: Date?

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var deletedAt: Date?

    var deck: StoredDeck?

    @Relationship(deleteRule: .cascade, inverse: \StoredReviewLog.card)
    var reviewLogs: [StoredReviewLog] = []

    init(id: UUID = UUID(), deck: StoredDeck?, frontText: String = "", backText: String = "") {
        self.id = id
        self.deck = deck
        self.frontText = frontText
        self.backText = backText
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.dueDate = Date()
    }

    private var memoryState: MemoryState? {
        guard let stability, let difficulty else { return nil }
        return MemoryState(stability: stability, difficulty: difficulty)
    }

    var scheduling: SchedulingState {
        get {
            SchedulingState(
                phase: Self.phase(raw: phaseRaw, step: phaseStep),
                intervalDays: intervalDays,
                easeFactor: easeFactor,
                repetitions: repetitions,
                lapses: lapses,
                dueDate: dueDate,
                lastReviewedAt: lastReviewedAt,
                memory: memoryState,
                isSuspended: isSuspended,
                isLeech: isLeech
            )
        }
        set {
            let (raw, step) = Self.encode(newValue.phase)
            phaseRaw = raw
            phaseStep = step
            intervalDays = newValue.intervalDays
            easeFactor = newValue.easeFactor
            repetitions = newValue.repetitions
            lapses = newValue.lapses
            dueDate = newValue.dueDate
            lastReviewedAt = newValue.lastReviewedAt
            stability = newValue.memory?.stability
            difficulty = newValue.memory?.difficulty
            isSuspended = newValue.isSuspended
            isLeech = newValue.isLeech
            modifiedAt = Date()
        }
    }

    var core: Card {
        Card(
            id: id,
            deckID: deck?.id ?? UUID(),
            profileID: deck?.profile?.id ?? UUID(),
            front: CardSide(text: frontText, drawing: frontDrawing),
            back: CardSide(text: backText, drawing: backDrawing),
            scheduling: scheduling,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            deletedAt: deletedAt
        )
    }

    private static func encode(_ phase: LearningPhase) -> (Int, Int) {
        switch phase {
        case .new: (0, 0)
        case .learning(let step): (1, step)
        case .review: (2, 0)
        case .relearning(let step): (3, step)
        }
    }

    private static func phase(raw: Int, step: Int) -> LearningPhase {
        switch raw {
        case 1: .learning(step: step)
        case 2: .review
        case 3: .relearning(step: step)
        default: .new
        }
    }
}

@Model
final class StoredReviewLog {
    var id: UUID = UUID()
    var reviewedAt: Date = Date()
    var gradeRaw: Int = 0
    var intervalBefore: Double = 0
    var intervalAfter: Double = 0
    var easeAfter: Double = 2.5
    var durationSeconds: Double = 0
    /// What the learner actually wrote during this review.
    @Attribute(.externalStorage) var attemptDrawing: Data?

    var card: StoredCard?

    init(
        card: StoredCard?, reviewedAt: Date, grade: ReviewGrade,
        intervalBefore: Double, intervalAfter: Double, easeAfter: Double,
        durationSeconds: Double, attemptDrawing: Data?
    ) {
        self.card = card
        self.reviewedAt = reviewedAt
        self.gradeRaw = grade.rawValue
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
        self.easeAfter = easeAfter
        self.durationSeconds = durationSeconds
        self.attemptDrawing = attemptDrawing
    }

    var grade: ReviewGrade { ReviewGrade(rawValue: gradeRaw) ?? .again }
}

/// One captured letter, in the user's own hand.
///
/// Stored per character with a sample index, so several attempts at the same letter can be
/// kept and drawn on at random — repeated letters looking identical is what makes
/// synthesised handwriting obvious.
@Model
final class StoredGlyph {
    var id: UUID = UUID()
    /// A single character, held as a String because SwiftData cannot store Character.
    var character: String = ""
    var sampleIndex: Int = 0
    /// PKDrawing data for this letter alone.
    var drawing: Data = Data()
    /// Bounds of the ink when captured, so it can be scaled without re-parsing.
    var width: Double = 0
    var height: Double = 0
    /// How far the ink fell below the writing line: the tail of a `g`, or zero for most letters.
    ///
    /// Recorded so letters can be set on a shared baseline rather than aligned by their tops,
    /// which would leave a comma floating and a capital sitting low.
    var descender: Double = 0
    /// Whether `descender` was measured against a known writing line, rather than left to be
    /// worked out from what the character is.
    var baselineRecorded: Bool = false
    var createdAt: Date = Date()

    init(character: Character, sampleIndex: Int, drawing: Data,
         width: Double, height: Double, descender: Double = 0,
         baselineRecorded: Bool = false) {
        self.character = String(character)
        self.sampleIndex = sampleIndex
        self.drawing = drawing
        self.width = width
        self.height = height
        self.descender = descender
        self.baselineRecorded = baselineRecorded
    }
}
