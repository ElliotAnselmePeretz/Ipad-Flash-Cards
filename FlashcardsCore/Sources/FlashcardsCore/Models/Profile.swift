import Foundation

/// One person using this iPad. Every deck, card and review log is scoped by `profileID`,
/// which is also what makes a later move to per-user CloudKit containers cheap.
public struct Profile: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    /// SF Symbol or emoji shown on the profile picker.
    public var avatar: String
    public var config: SchedulerConfig
    /// Hour of day (0...23) at which "tomorrow" begins, so a late-night session still
    /// counts as today. Anki's equivalent default is 4am.
    public var dayStartHour: Int
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), name: String, avatar: String = "person.circle",
        config: SchedulerConfig = .default, dayStartHour: Int = 4,
        createdAt: Date = Date(), modifiedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.config = config
        self.dayStartHour = dayStartHour
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
}
