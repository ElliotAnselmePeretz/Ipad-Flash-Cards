import SwiftUI
import SwiftData
import PencilKit
import FlashcardsCore

/// Writing a deck by hand, without leaving the pen.
///
/// Deliberately shaped like the study screen: the same warm raised card, the same
/// QUESTION / ANSWER label. What you write on is what you will later be shown, so the two
/// screens should read as the same object seen from two sides.
struct RapidCaptureView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private enum Step { case question, answer }

    @State private var step: Step = .question
    @State private var questionInk: Data?
    @State private var answerInk: Data?
    @State private var createdCount = 0
    @State private var canvasGeneration = 0
    @State private var tool: InkTool = .pen
    @State private var inkColor: InkColor = .ink
    @State private var inkWidth: InkWidth = .medium
    @State private var controller = InkCanvasController()

    private var currentInk: Binding<Data?> {
        step == .question ? $questionInk : $answerInk
    }

    private var canAdvance: Bool {
        PKDrawing.hasStrokes(step == .question ? questionInk : answerInk)
    }

    private var accent: Color {
        step == .question ? Theme.accent(scheme) : Theme.easy(scheme)
    }

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            VStack(spacing: 16) {
                progress

                writingCard
                    .frame(maxWidth: 760)
                    .padding(.horizontal, 22)

                InkToolbar(tool: $tool, color: $inkColor, width: $inkWidth)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
                    .padding(.horizontal, 22)

                controls
                    .padding(.horizontal, 22)
                    .padding(.bottom, 18)
            }
        }
        .navigationTitle("Write cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }.accessibilityIdentifier("rapid.done")
            }
        }
    }

    // MARK: - Header

    /// Two dots showing which half of the card you are on, plus a running tally. The
    /// screen used to be a bare canvas; this gives it somewhere to start and a sense of
    /// progress across a session.
    private var progress: some View {
        HStack(spacing: 16) {
            HStack(spacing: 7) {
                stepDot(filled: true, done: step == .answer)
                Rectangle()
                    .fill(step == .answer ? accent : Theme.softInk(scheme).opacity(0.25))
                    .frame(width: 26, height: 2)
                stepDot(filled: step == .answer, done: false)
            }

            Text(step == .question ? "Question" : "Answer")
                .font(Theme.label(17))
                .foregroundStyle(accent)
                .contentTransition(.numericText())

            Spacer()

            if createdCount > 0 {
                Label("^[\(createdCount) card](inflect: true)", systemImage: "checkmark.circle.fill")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.easy(scheme))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: createdCount)
    }

    private func stepDot(filled: Bool, done: Bool) -> some View {
        Circle()
            .fill(filled ? accent : Theme.softInk(scheme).opacity(0.25))
            .frame(width: 9, height: 9)
    }

    // MARK: - Card

    private var writingCard: some View {
        WarmCard(padding: 22) {
            VStack(spacing: 12) {
                Text(step == .question ? "QUESTION" : "ANSWER")
                    .font(Theme.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.softInk(scheme))

                ZStack {
                    DrawingCanvas(
                        data: currentInk,
                        controller: controller,
                        tool: tool, color: inkColor, width: inkWidth,
                        onFlip: { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipSide() } }
                    )
                    .id(canvasGeneration)

                    if !canAdvance {
                        VStack(spacing: 8) {
                            Image(systemName: step == .question ? "questionmark.bubble" : "lightbulb")
                                .font(.system(size: 30, weight: .light))
                            Text(step == .question ? "Write the question" : "Write the answer")
                                .font(Theme.title(19))
                            Text("Tap with a finger to flip sides")
                                .font(Theme.body(13))
                                .opacity(0.7)
                        }
                        .foregroundStyle(Theme.softInk(scheme).opacity(0.55))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .frame(minHeight: 300)
            }
        }
        // The glow appears only once the side has ink, so it reads as quiet encouragement.
        .softGlow(accent, active: canAdvance, maxOpacity: 0.22)
        .animation(.easeInOut(duration: 0.45), value: canAdvance)
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 22)
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Undo stroke")

            Button { controller.redo() } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 22)
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Redo stroke")

            Button { clearCurrent() } label: {
                Image(systemName: "trash").frame(width: 22)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!canAdvance)
            .accessibilityIdentifier("rapid.clear")

            if step == .answer {
                Button { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { flipSide() } } label: {
                    Label("Question", systemImage: "arrow.left")
                        .font(Theme.body(15))
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("rapid.back")
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            Spacer(minLength: 0)

            Button {
                advance()
            } label: {
                HStack(spacing: 7) {
                    Text(step == .question ? "Write answer" : "Save card")
                    Image(systemName: step == .question ? "arrow.right" : "checkmark")
                }
                .font(Theme.label(17))
                .frame(minWidth: 190)
                .padding(.vertical, 13)
            }
            .buttonStyle(SpringyButtonStyle(
                tint: canAdvance ? accent : Theme.softInk(scheme).opacity(0.25)
            ))
            .disabled(!canAdvance)
            .accessibilityIdentifier("rapid.advance")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)
    }

    // MARK: - Actions

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
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
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
    }

    private func saveCard() {
        let card = StoredCard(deck: deck)
        card.frontDrawing = questionInk
        card.backDrawing = answerInk
        context.insert(card)
        try? context.save()
    }
}
