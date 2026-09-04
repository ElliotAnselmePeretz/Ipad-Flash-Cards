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

    /// Totals across every deck, so the first screen says something rather than being a
    /// bare list. Due-now is the number that decides whether you study at all.
    private var dueNow: Int {
        decks.reduce(0) { total, deck in
            total + deck.cards.filter { $0.deletedAt == nil && $0.dueDate <= Date() }.count
        }
    }

    private var totalCards: Int {
        decks.reduce(0) { $0 + $1.cards.filter { $0.deletedAt == nil }.count }
    }

    private var reviewedToday: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return decks.reduce(0) { total, deck in
            total + deck.cards.filter { $0.deletedAt == nil }
                .reduce(0) { $0 + $1.reviewLogs.filter { $0.reviewedAt >= start }.count }
        }
    }

    private func addSampleDeck() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            SampleDeck.add(to: profile, in: context)
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default: "Still up?"
        }
    }

    @ViewBuilder
    private var summaryHeader: some View {
        if !decks.isEmpty {
            WarmCard(padding: 18) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(Theme.display(24))
                                .foregroundStyle(Theme.ink(scheme))
                            Text(dueNow == 0
                                 ? "Nothing due right now."
                                 : "^[\(dueNow) card](inflect: true) waiting for you.")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.softInk(scheme))
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        StatChip(value: "\(dueNow)", label: "due now", tint: Theme.accent(scheme))
                        StatChip(value: "\(reviewedToday)", label: "done today", tint: Theme.easy(scheme))
                        StatChip(value: "\(totalCards)", label: "cards", tint: nil)
                    }
                }
            }
            // A faint halo when something is actually waiting, and none when it is not.
            .softGlow(Theme.accent(scheme), active: dueNow > 0, maxOpacity: 0.20)
            .animation(.easeInOut(duration: 0.5), value: dueNow)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    summaryHeader
                        .padding(.bottom, 4)

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
                    EmptyDecksView(onAddSample: addSampleDeck)
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

    private var liveCards: [StoredCard] { deck.cards.filter { $0.deletedAt == nil } }
    private var dueCount: Int { liveCards.filter { $0.dueDate <= Date() }.count }

    private var counts: QueueCounts {
        ReviewQueue(deck: deck.core).counts(from: deck.cards.map(\.core))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(deck.name).font(Theme.display(20))
                HStack(spacing: 8) {
                    Text("^[\(liveCards.count) card](inflect: true)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.softInk(scheme))
                    if dueCount > 0 {
                        Text("\(dueCount) due")
                            .font(Theme.label(12))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Theme.accent(scheme).opacity(0.16))
                            )
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }
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

/// Shown when there are no decks at all. Broken out of `DeckListView` because the compiler
/// could not type-check the whole body as one expression.
private struct EmptyDecksView: View {
    @Environment(\.colorScheme) private var scheme
    let onAddSample: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.accent(scheme))
                .softGlow(Theme.accent(scheme), maxOpacity: 0.25)

            Text("Nothing here yet")
                .font(Theme.display(24))
                .foregroundStyle(Theme.ink(scheme))

            Text("Make a deck, then write cards with your Pencil.")
                .font(Theme.body())
                .foregroundStyle(Theme.softInk(scheme))
                .multilineTextAlignment(.center)

            Button("Add the sample deck", action: onAddSample)
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("decks.addSample")
                .padding(.top, 4)
        }
        .padding(50)
    }
}
