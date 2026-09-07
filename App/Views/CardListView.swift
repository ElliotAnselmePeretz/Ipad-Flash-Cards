import SwiftUI
import SwiftData
import PencilKit
import FlashcardsCore

struct CardListView: View {
    let deck: StoredDeck
    @Environment(\.colorScheme) private var scheme
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editingCard: StoredCard?

    private var cards: [StoredCard] {
        // Suspended cards stay listed — they are out of the review queue, not gone.
        deck.cards.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    private var suspendedCount: Int { cards.filter(\.isSuspended).count }

    /// Cards with typed text on a side that has no ink yet.
    private var typedOnly: [StoredCard] {
        cards.filter { card in
            (!card.frontText.isEmpty && !PKDrawing.hasStrokes(card.frontDrawing))
                || (!card.backText.isEmpty && !PKDrawing.hasStrokes(card.backDrawing))
        }
    }

    private func writeTypedCardsInMyHand() {
        let handwriting = HandwritingStore(context: context)
        for card in typedOnly {
            if !card.frontText.isEmpty, !PKDrawing.hasStrokes(card.frontDrawing) {
                card.frontDrawing = handwriting.compose(card.frontText, maxWidth: 680).drawing.dataRepresentation()
            }
            if !card.backText.isEmpty, !PKDrawing.hasStrokes(card.backDrawing) {
                card.backDrawing = handwriting.compose(card.backText, maxWidth: 680).drawing.dataRepresentation()
            }
            card.modifiedAt = Date()
        }
        try? context.save()
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.18)))
            .foregroundStyle(tint)
    }

    var body: some View {
        List {
            if suspendedCount > 0 {
                Section {
                    Label("^[\(suspendedCount) card](inflect: true) paused after too many lapses. "
                          + "Rewrite them, then swipe right to resume.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            // Cards that arrived typed — an Anki or CSV import — can be written out in one go.
            if !typedOnly.isEmpty, HandwritingStore(context: context).capturedCount() > 0 {
                Section {
                    Button {
                        writeTypedCardsInMyHand()
                    } label: {
                        Label("Write \(counted(typedOnly.count, "typed card")) in my handwriting",
                              systemImage: "hand.draw")
                    }
                    .accessibilityIdentifier("cards.writeAllInMyHand")
                }
            }
            ForEach(cards) { card in
                NavigationLink(value: card) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.frontText.isEmpty ? "(handwritten)" : card.frontText)
                                .font(.headline)
                                .foregroundStyle(card.frontText.isEmpty ? .secondary : .primary)
                            HStack(spacing: 6) {
                                Text(statusLabel(card)).font(.caption).foregroundStyle(.secondary)
                                if card.isLeech { badge("Leech", tint: .orange) }
                                if card.isSuspended { badge("Paused", tint: .secondary) }
                            }
                        }
                        Spacer()
                        if card.frontDrawing != nil || card.backDrawing != nil {
                            Image(systemName: "pencil.and.scribble").foregroundStyle(.tertiary)
                        }
                    }
                    .opacity(card.isSuspended ? 0.55 : 1)
                }
                // A suspended card has to be recoverable, or it is just gone.
                .swipeActions(edge: .leading) {
                    Button {
                        card.isSuspended.toggle()
                        if !card.isSuspended { card.isLeech = false }
                        try? context.save()
                    } label: {
                        Label(card.isSuspended ? "Resume" : "Pause",
                              systemImage: card.isSuspended ? "play.circle" : "pause.circle")
                    }
                    .tint(card.isSuspended ? .green : .orange)
                }
            }
            .onDelete { indexSet in
                for index in indexSet { cards[index].deletedAt = Date() }
                try? context.save()
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page(scheme))
        .safeAreaInset(edge: .top) {
            AppHeader(title: "Cards", onBack: { dismiss() }) {
                NavigationLink { RapidCaptureView(deck: deck) } label: {
                    HeaderGlyph(symbol: "pencil.and.scribble", label: "Write cards",
                                tint: Theme.accent(scheme))
                }
                NavigationLink { PasteCardsView(deck: deck) } label: {
                    HeaderGlyph(symbol: "doc.on.clipboard", label: "Paste cards")
                }
                NavigationLink { ImportView(deck: deck) } label: {
                    HeaderGlyph(symbol: "square.and.arrow.down", label: "Import")
                }
                HeaderButton(symbol: "plus", label: "Add card") {
                    let card = StoredCard(deck: deck)
                    context.insert(card)
                    try? context.save()
                    editingCard = card
                }
            }
            .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView("No cards", systemImage: "rectangle.on.rectangle",
                                       description: Text("Add your first card to this deck."))
            }
        }
        .navigationDestination(item: $editingCard) { card in
            CardEditorView(card: card)
        }
        .navigationDestination(for: StoredCard.self) { card in
            CardEditorView(card: card)
        }
    }

    private func statusLabel(_ card: StoredCard) -> String {
        switch card.scheduling.phase {
        case .new: "New"
        case .learning: "Learning"
        case .relearning: "Relearning"
        case .review:
            "Due \(card.scheduling.dueDate.formatted(.relative(presentation: .named))) · \(Int(card.scheduling.intervalDays))d"
        }
    }
}

/// Edit a card. Both sides are handwritten — there is no typing here.
///
/// Typed text only ever arrives through CSV import, so an imported question is shown
/// above the canvas as a read-only caption rather than an editable field.
/// Fills a side with the typed text, written out in the user's own letters.
struct CardEditorView: View {
    @Bindable var card: StoredCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var side: Side = .front
    @State private var tool: InkTool = .pen
    @State private var inkColor: InkColor = .ink
    @State private var inkWidth: InkWidth = .medium
    @State private var missingLetters: Set<Character> = []

    private var handwriting: HandwritingStore { HandwritingStore(context: context) }

    enum Side: String, CaseIterable { case front = "Question", back = "Answer" }

    private var importedCaption: String {
        side == .front ? card.frontText : card.backText
    }

    private func writeInMyHand() {
        let text = importedCaption
        guard !text.isEmpty else { return }
        let composition = handwriting.compose(text, maxWidth: 680)
        guard !composition.drawing.strokes.isEmpty else { return }

        withAnimation(.easeInOut(duration: 0.35)) {
            let data = composition.drawing.dataRepresentation()
            if side == .front { card.frontDrawing = data } else { card.backDrawing = data }
            missingLetters = composition.missing
            card.modifiedAt = Date()
            try? context.save()
        }
    }

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            VStack(spacing: 0) {
                AppSegmented(items: Side.allCases, label: \.rawValue, selection: $side)
                    .accessibilityIdentifier("sidePicker")
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if !importedCaption.isEmpty, handwriting.capturedCount() > 0 {
                    Button {
                        writeInMyHand()
                    } label: {
                        Label("Write this in my handwriting", systemImage: "hand.draw")
                            .font(Theme.label(15))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
                    .padding(.top, 12)
                    .accessibilityIdentifier("card.writeInMyHand")
                }

                if !missingLetters.isEmpty {
                    Text("Not captured yet: \(missingLetters.sorted().map(String.init).joined(separator: " "))")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.medium(scheme))
                        .padding(.top, 6)
                }

                if !importedCaption.isEmpty {
                    Text(importedCaption)
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.ink(scheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .transition(.opacity)
                }

                DrawingCanvas(
                    data: side == .front ? $card.frontDrawing : $card.backDrawing,
                    tool: tool, color: inkColor, width: inkWidth,
                    onFlip: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        side = side == .front ? .back : .front
                    } }
                )
                .id(side)

                InkToolbar(tool: $tool, color: $inkColor, width: $inkWidth)
            }
        }
        .navigationTitle("Edit card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") {
                    card.modifiedAt = Date()
                    try? context.save()
                    dismiss()
                }
                .disabled(card.core.front.isEmpty)
            }
        }
    }
}
