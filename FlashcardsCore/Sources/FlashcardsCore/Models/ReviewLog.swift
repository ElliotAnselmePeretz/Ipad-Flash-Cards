import Foundation

/// An immutable record of one answered card. Drives the stats screens, and means the
/// whole scheduling history can be replayed if the algorithm is ever swapped for FSRS.
public struct ReviewLog: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var cardID: UUID
    public var profileID: UUID
    public var reviewedAt: Date
    public var grade: ReviewGrade
    /// Scheduling state before and after, so history is reconstructable.
    public var intervalBefore: Double
    public var intervalAfter: Double
    public var easeAfter: Double
    /// How long the learner looked at the card, in seconds.
    public var durationSeconds: Double
    /// What they wrote as their answer during this review, if ink was captured.
    public var attemptDrawing: Data?

    public init(
        id: UUID = UUID(), cardID: UUID, profileID: UUID, reviewedAt: Date,
        grade: ReviewGrade, intervalBefore: Double, intervalAfter: Double,
        easeAfter: Double, durationSeconds: Double, attemptDrawing: Data? = nil
    ) {
        self.id = id
        self.cardID = cardID
        self.profileID = profileID
        self.reviewedAt = reviewedAt
        self.grade = grade
        self.intervalBefore = intervalBefore
        self.intervalAfter = intervalAfter
        self.easeAfter = easeAfter
        self.durationSeconds = durationSeconds
        self.attemptDrawing = attemptDrawing
    }
}
