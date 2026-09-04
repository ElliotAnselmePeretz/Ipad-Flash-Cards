import Foundation

public struct Deck: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var profileID: UUID
    public var name: String
    /// Per-deck overrides; falls back to the profile default when nil.
    public var config: SchedulerConfig?
    public var newCardsPerDay: Int
    public var maximumReviewsPerDay: Int
    public var createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(), profileID: UUID, name: String,
        config: SchedulerConfig? = nil,
        newCardsPerDay: Int = 20, maximumReviewsPerDay: Int = 200,
        createdAt: Date = Date(), modifiedAt: Date = Date(), deletedAt: Date? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.name = name
        self.config = config
        self.newCardsPerDay = newCardsPerDay
        self.maximumReviewsPerDay = maximumReviewsPerDay
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
    }

    public var isDeleted: Bool { deletedAt != nil }
}
