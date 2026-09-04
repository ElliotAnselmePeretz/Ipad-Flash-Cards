import SwiftUI
import SwiftData
import FlashcardsCore

struct CardListView: View {
    let deck: StoredDeck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var editingCard: StoredCard?

    private var cards: [StoredCard] {
        deck.cards.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            ForEach(cards) { card in
                NavigationLink(value: card) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.frontText.isEmpty ? "(handwritten)" : card.frontText)
                                .font(.headline)
                                .foregroundStyle(card.frontText.isEmpty ? .secondary : .primary)
                            Text(statusLabel(card)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if card.frontDrawing != nil || card.backDrawing != nil {
                            Image(systemName: "pencil.and.scribble").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet { cards[index].deletedAt = Date() }
                try? context.save()
            }
        }
        .navigationTitle("Cards")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if cards.isEmpty {
                ContentUnavailableView("No cards", systemImage: "rectangle.on.rectangle",
                                       description: Text("Add your first card to this deck."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    ImportView(deck: deck)
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add card", systemImage: "plus") {
                    let card = StoredCard(deck: deck)
                    context.insert(card)
                    try? context.save()
                    editingCard = card
                }
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

/// Edit both sides. Each side takes typed text, Pencil ink, or both.
struct CardEditorView: View {
    @Bindable var card: StoredCard
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var side: Side = .front

    enum Side: String, CaseIterable { case front = "Front", back = "Answer" }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Side", selection: $side) {
                ForEach(Side.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("sidePicker")
            .padding()

            TextField(side == .front ? "Question (optional)" : "Answer (optional)",
                      text: side == .front ? $card.frontText : $card.backText,
                      axis: .vertical)
                .font(.system(.title3, design: .serif))
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal)

            Divider().padding(.top, 8)

            ZStack {
                RuledPaper()
                DrawingCanvas(
                    data: side == .front ? $card.frontDrawing : $card.backDrawing,
                    showsToolPicker: true
                )
            }
            .id(side)   // fresh canvas per side
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
