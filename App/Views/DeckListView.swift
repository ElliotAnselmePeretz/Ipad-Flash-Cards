import SwiftUI
import SwiftData
import FlashcardsCore

struct DeckListView: View {
    let profile: StoredProfile
    let onSwitchProfile: () -> Void

    @Environment(\.modelContext) private var context
    @State private var newDeckName = ""
    @State private var isAddingDeck = false

    private var decks: [StoredDeck] {
        profile.decks.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(decks) { deck in
                    NavigationLink {
                        StudyView(deck: deck)
                    } label: {
                        DeckRow(deck: deck)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { decks[index].deletedAt = Date() }
                    try? context.save()
                }
            }
            .navigationTitle(profile.name)
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView(
                        "No decks yet",
                        systemImage: "rectangle.stack",
                        description: Text("Create a deck to start writing cards.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Switch profile", systemImage: "person.crop.circle", action: onSwitchProfile)
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

    private var counts: QueueCounts {
        ReviewQueue(deck: deck.core).counts(from: deck.cards.map(\.core))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.name).font(.headline)
                Text("^[\(deck.cards.filter { $0.deletedAt == nil }.count) card](inflect: true)")
                    .font(.subheadline)
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
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(value == 0 ? Color.secondary : color)
            .accessibilityLabel("\(value) \(label)")
    }
}
