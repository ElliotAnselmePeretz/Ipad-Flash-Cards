import SwiftUI
import SwiftData
import PencilKit
import FlashcardsCore

/// Writing a deck by hand, without leaving the pen.
///
/// The ordinary editor costs six taps per card: Add, write, switch side, write, Save,
/// Add again. That is fine for one card and miserable for fifty. Here the question and
/// answer are two steps of one loop, and finishing a card immediately opens the next.
struct RapidCaptureView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Step { case question, answer }

    @State private var step: Step = .question
    @State private var questionInk: Data?
    @State private var answerInk: Data?
    @State private var createdCount = 0
    /// Forces a fresh PKCanvasView between steps so ink never bleeds across sides.
    @State private var canvasGeneration = 0
    @State private var tool: InkTool = .pen
    @State private var inkColor: InkColor = .ink
    @State private var inkWidth: InkWidth = .medium
    @Environment(\.colorScheme) private var scheme

    private var currentInk: Binding<Data?> {
        step == .question ? $questionInk : $answerInk
    }

    private var canAdvance: Bool {
        PKDrawing.hasStrokes(step == .question ? questionInk : answerInk)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)

            ZStack(alignment: .topLeading) {
                DrawingCanvas(
                    data: currentInk, tool: tool, color: inkColor, width: inkWidth,
                    onFlip: { withAnimation(.snappy) { flipSide() } }
                )
                .id(canvasGeneration)

                if !canAdvance {
                    Text(step == .question ? "Write the question" : "Write the answer")
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.softInk(scheme).opacity(0.6))
                        .padding(24)
                        .allowsHitTesting(false)
                }
            }

            InkToolbar(tool: $tool, color: $inkColor, width: $inkWidth)
            controls
        }
        .navigationTitle("Write cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }.accessibilityIdentifier("rapid.done")
            }
        }
    }

    private var header: some View {
        HStack {
            Label(step == .question ? "Question" : "Answer",
                  systemImage: step == .question ? "questionmark.circle" : "checkmark.circle")
                .font(Theme.label(17))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(step == .question ? Color.accentColor : .green)
                .accessibilityIdentifier("rapid.step")

            Spacer()

            Text("^[\(createdCount) card](inflect: true) written")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("rapid.count")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Clear", systemImage: "trash") { clearCurrent() }
                .disabled(!canAdvance)
                .accessibilityIdentifier("rapid.clear")

            if step == .answer {
                Button("Back to question", systemImage: "arrow.uturn.backward") {
                    step = .question
                    canvasGeneration += 1
                }
                .accessibilityIdentifier("rapid.back")
            }

            Spacer()

            Button {
                advance()
            } label: {
                Label(step == .question ? "Write answer" : "Save and write next",
                      systemImage: step == .question ? "arrow.right" : "checkmark")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 200)
                    .padding(.vertical, 6)
            }
            .buttonStyle(SpringyButtonStyle(tint: canAdvance ? Theme.accent(scheme) : Theme.softInk(scheme).opacity(0.3)))
            .disabled(!canAdvance)
            .accessibilityIdentifier("rapid.advance")
        }
        .padding(14)
        .background(.regularMaterial)
    }

    // MARK: - Actions

    /// A finger tap or swipe moves between the two sides of the card being written,
    /// without committing anything.
    private func flipSide() {
        step = step == .question ? .answer : .question
        canvasGeneration += 1
    }

    private func clearCurrent() {
        if step == .question { questionInk = nil } else { answerInk = nil }
        canvasGeneration += 1
    }

    private func advance() {
        guard canAdvance else { return }
        if step == .question {
            step = .answer
        } else {
            saveCard()
            step = .question
            questionInk = nil
            answerInk = nil
            createdCount += 1
        }
        canvasGeneration += 1
    }

    private func saveCard() {
        let card = StoredCard(deck: deck)
        card.frontDrawing = questionInk
        card.backDrawing = answerInk
        context.insert(card)
        try? context.save()
    }
}
