import Foundation

/// How well the learner recalled a card. Mirrors Anki's four answer buttons.
public enum ReviewGrade: Int, Codable, Sendable, CaseIterable {
    case again = 0
    case hard = 1
    case good = 2
    case easy = 3

    /// SM-2's original 0...5 recall quality, used for the ease-factor formula.
    var quality: Double {
        switch self {
        case .again: 2
        case .hard: 3
        case .good: 4
        case .easy: 5
        }
    }

    /// A grade below `.hard` means the card was forgotten and must lapse.
    var isFailure: Bool { self == .again }
}
