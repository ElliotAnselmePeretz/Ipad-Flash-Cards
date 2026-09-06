import SwiftUI
import FlashcardsCore

/// How much of a deck you would still get right, drawn as a bar.
///
/// The colour is the message: green means it is holding, amber means it is slipping away,
/// red means most of it is gone. The number underneath is the same thing in words, because
/// "62%" alone does not tell you whether to act.
struct MemoryBar: View {
    let estimate: MemoryEstimate
    var showsLabel = true
    var height: CGFloat = 8

    @Environment(\.colorScheme) private var scheme

    private var tint: Color {
        guard !estimate.isEmpty else { return Theme.softInk(scheme).opacity(0.4) }
        switch estimate.percentage {
        case 80...: return Theme.easy(scheme)
        case 55..<80: return Theme.medium(scheme)
        default: return Theme.hard(scheme)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.ink(scheme).opacity(0.09))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(0, geo.size.width * estimate.recallProbability))
                }
            }
            .frame(height: height)

            if showsLabel {
                HStack(spacing: 6) {
                    Text(estimate.isEmpty ? "—" : "\(estimate.percentage)%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(tint)
                    Text(estimate.summary)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.softInk(scheme))
                    if estimate.unseenCards > 0 {
                        Text("· \(estimate.unseenCards) new")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.softInk(scheme).opacity(0.8))
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: estimate.recallProbability)
    }
}
