import Foundation

/// One side of a card. Either half may carry typed text, Apple Pencil ink, or both —
/// so a deck can be typed, fully handwritten, or a mix, without changing the model.
public struct CardSide: Codable, Sendable, Equatable {
    public var text: String
    /// `PKDrawing.dataRepresentation()`. Kept as opaque `Data` so this package stays
    /// free of PencilKit and therefore buildable and testable off-device.
    public var drawing: Data?

    public init(text: String = "", drawing: Data? = nil) {
        self.text = text
        self.drawing = drawing
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (drawing?.isEmpty ?? true)
    }
}

/// A single flashcard, owned by one profile and one deck.
public struct Card: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var deckID: UUID
    public var profileID: UUID
    public var front: CardSide
    public var back: CardSide
    public var scheduling: SchedulingState
    public var createdAt: Date
    /// Bumped on every edit; the tiebreaker if this ever syncs across devices.
    public var modifiedAt: Date
    /// Soft delete, so a future sync can propagate removals instead of losing them.
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), deckID: UUID, profileID: UUID,
        front: CardSide = CardSide(), back: CardSide = CardSide(),
        scheduling: SchedulingState? = nil,
        createdAt: Date = Date(), modifiedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.deckID = deckID
        self.profileID = profileID
        self.front = front
        self.back = back
        self.scheduling = scheduling ?? .new(now: createdAt)
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}
