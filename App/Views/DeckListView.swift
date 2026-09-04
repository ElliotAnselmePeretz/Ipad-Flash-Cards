import SwiftUI
import SwiftData
import FlashcardsCore


struct DeckListView: View {
    let profile: StoredProfile

    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = Appearance.system
    @Environment(\.colorScheme) private var scheme
    @State private var newDeckName = ""
    @State private var isAddingDeck = false

    private var decks: [StoredDeck] {
        profile.decks.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(Array(decks.enumerated()), id: \.element.id) { index, deck in
                        NavigationLink {
                            StudyView(deck: deck)
                        } label: {
                            WarmCard(padding: 18) { DeckRow(deck: deck) }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    deck.deletedAt = Date()
                                    try? context.save()
                                }
                            }
                        }
                        // Decks fan in on appearance rather than snapping into place.
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.45, dampingFraction: 0.82)
                                    .delay(Double(index) * 0.04), value: decks.count)
                    }
                }
                .padding(20)
            }
            .background(Theme.page(scheme))
            .navigationTitle("Decks")
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No decks yet", systemImage: "rectangle.stack")
                    } description: {
                        Text("Create a deck to start writing cards.")
                    } actions: {
                        Button("Add the sample deck") {
                            SampleDeck.add(to: profile, in: context)
                        }
                        .accessibilityIdentifier("decks.addSample")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(Appearance.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityIdentifier("decks.appearance")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New deck", systemImage: "plus") { isAddingDeck = true }
                }
            }
            .alert("New deck", isPresented: $isAddingDeck) {
                TextField("Name", text: $newDeckName)
                Button("Cancel", role: .cancel) { newDeckName = "" }
                Button("Create") { createDeck() }
            }
        }
    }

    private func createDeck() {
        let trimmed = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(StoredDeck(name: trimmed, profile: profile))
        try? context.save()
        newDeckName = ""
    }
}

private struct DeckRow: View {
    let deck: StoredDeck
    @Environment(\.colorScheme) private var scheme

    private var counts: QueueCounts {
        ReviewQueue(deck: deck.core).counts(from: deck.cards.map(\.core))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name).font(Theme.display(20))
                Text("^[\(deck.cards.filter { $0.deletedAt == nil }.count) card](inflect: true)")
                    .font(Theme.body(14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            let c = counts
            HStack(spacing: 10) {
                CountPill(value: c.new, color: .blue, label: "new")
                CountPill(value: c.learning, color: .orange, label: "learning")
                CountPill(value: c.review, color: .green, label: "due")
            }
        }
        .padding(.vertical, 4)
    }
}

struct CountPill: View {
    let value: Int
    let color: Color
    let label: String

    var body: some View {
        Text("\(value)")
            .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(value == 0 ? Color.secondary : color)
            .accessibilityLabel("\(value) \(label)")
    }
}
