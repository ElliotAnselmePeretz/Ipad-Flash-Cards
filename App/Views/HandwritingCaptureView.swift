import SwiftUI
import SwiftData
import PencilKit
import FlashcardsCore

/// Captures the alphabet in your own hand, one letter at a time.
///
/// One letter per screen rather than a written-out alphabet on a single canvas: a page of
/// ink would have to be segmented back into letters, and multi-stroke characters like i, j
/// and t would be split wrongly. Asking for each character separately means every glyph is
/// labelled correctly by construction.
struct HandwritingCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var index = 0
    @State private var ink: Data?
    @State private var canvasGeneration = 0
    @State private var tool: InkTool = .pen
    @State private var inkColor: InkColor = .ink
    @State private var inkWidth: InkWidth = .medium
    @State private var controller = InkCanvasController()
    @State private var isConfirmingReset = false

    private var store: HandwritingStore { HandwritingStore(context: context) }

    private var alphabet: [Character] { HandwritingAlphabet.characters }
    private var current: Character { alphabet[min(index, alphabet.count - 1)] }
    private var isFinished: Bool { index >= alphabet.count }
    private var hasInk: Bool { PKDrawing.hasStrokes(ink) }

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            if isFinished {
                finishedView
            } else {
                capturing
            }
        }
        .safeAreaInset(edge: .top) {
            AppHeader(title: "Your handwriting",
                      subtitle: isFinished ? nil : "\(index + 1) of \(alphabet.count)",
                      onBack: { dismiss() }) {
                HeaderButton(symbol: "trash", label: "Start over") { isConfirmingReset = true }
            }
            .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .task { index = min(store.capturedCount(), alphabet.count) }
        .overlay {
            if isConfirmingReset {
                AppDialog(
                    title: "Start over?",
                    message: "Every captured letter is deleted and you begin from a again.",
                    confirmTitle: "Delete",
                    onConfirm: {
                        store.deleteAll()
                        index = 0
                        ink = nil
                        canvasGeneration += 1
                        isConfirmingReset = false
                    },
                    onCancel: { isConfirmingReset = false }
                ) { EmptyView() }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isConfirmingReset)
    }

    // MARK: - Capturing

    private var capturing: some View {
        VStack(spacing: 14) {
            progressBar

            WarmCard(padding: 22) {
                VStack(spacing: 12) {
                    Text("Write this letter")
                        .font(Theme.label(11))
                        .tracking(1.4)
                        .foregroundStyle(Theme.softInk(scheme))

                    Text(String(current))
                        .font(.system(size: 76, weight: .light, design: .serif))
                        .foregroundStyle(Theme.accent(scheme))
                        .contentTransition(.numericText())
                        .accessibilityLabel("Write the character \(describe(current))")

                    ZStack {
                        // A writing line, so letters are captured sitting on a baseline
                        // rather than floating at random heights.
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Theme.softInk(scheme).opacity(0.22))
                                .frame(height: 1)
                                .padding(.bottom, 54)
                        }

                        DrawingCanvas(
                            data: $ink,
                            controller: controller,
                            tool: tool, color: inkColor, width: inkWidth
                        )
                        .id(canvasGeneration)

                        if !hasInk {
                            Text("Write it once, as you normally would")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.softInk(scheme).opacity(0.5))
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 260)
                }
            }
            .softGlow(Theme.glow(scheme), active: hasInk, maxOpacity: 0.45)
            .frame(maxWidth: 620)
            .padding(.horizontal, 22)

            InkToolbar(tool: $tool, color: $inkColor, width: $inkWidth)
                .clipShape(RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous))
                .padding(.horizontal, 22)

            controls
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink(scheme).opacity(0.08))
                Capsule()
                    .fill(Theme.accent(scheme).gradient)
                    .frame(width: geo.size.width * CGFloat(index) / CGFloat(alphabet.count))
            }
        }
        .frame(height: 6)
        .padding(.horizontal, 24)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button { controller.undo() } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 22)
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Undo stroke")

            Button { clear() } label: {
                Image(systemName: "trash").frame(width: 22)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!hasInk)

            Button("Skip") { advance(saving: false) }
                .buttonStyle(QuietButtonStyle())

            Spacer(minLength: 0)

            Button { advance(saving: true) } label: {
                HStack(spacing: 7) {
                    Text("Next")
                    Image(systemName: "arrow.right")
                }
                .font(Theme.label(17))
                .frame(minWidth: 170)
                .padding(.vertical, 13)
            }
            .buttonStyle(SpringyButtonStyle(
                tint: hasInk ? Theme.accent(scheme) : Theme.softInk(scheme).opacity(0.25)
            ))
            .disabled(!hasInk)
            .accessibilityIdentifier("handwriting.next")
        }
    }

    private var finishedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 62))
                .foregroundStyle(Theme.easy(scheme))
                .softGlow(Theme.glow(scheme), maxOpacity: 0.45)

            Text("That's your alphabet")
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink(scheme))

            Text("^[\(store.capturedCount()) letter](inflect: true) captured. Any card with typed "
                 + "text can now be written out in your hand.")
                .font(Theme.body(15))
                .foregroundStyle(Theme.softInk(scheme))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            preview
                .frame(maxWidth: 560)
                .padding(.top, 4)

            HStack(spacing: 10) {
                Button("Add more variations") { index = 0; ink = nil; canvasGeneration += 1 }
                    .buttonStyle(QuietButtonStyle())
                Button("Done") { dismiss() }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 6)
        }
        .padding(34)
    }

    /// Shows the library actually composing something, so it can be judged before use.
    private var preview: some View {
        WarmCard(padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("PREVIEW")
                    .font(Theme.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.softInk(scheme))
                DrawingThumbnail(
                    data: store.compose("the quick brown fox", maxWidth: 520)
                        .drawing.dataRepresentation(),
                    height: 90
                )
            }
        }
    }

    // MARK: - Actions

    private func clear() {
        ink = nil
        canvasGeneration += 1
    }

    private func advance(saving: Bool) {
        if saving, let ink, let drawing = try? PKDrawing(data: ink) {
            store.save(drawing, for: current)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            index += 1
            self.ink = nil
            canvasGeneration += 1
        }
    }

    /// Punctuation read aloud as a symbol is unhelpful; name it.
    private func describe(_ character: Character) -> String {
        switch character {
        case ".": "full stop"
        case ",": "comma"
        case "'": "apostrophe"
        case "?": "question mark"
        case "!": "exclamation mark"
        case ":": "colon"
        case ";": "semicolon"
        case "-": "hyphen"
        case "(": "opening bracket"
        case ")": "closing bracket"
        case "/": "slash"
        case "&": "ampersand"
        case "+": "plus"
        case "=": "equals"
        default: String(character)
        }
    }
}
