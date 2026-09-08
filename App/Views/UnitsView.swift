import SwiftUI
import SwiftData
import FlashcardsCore

/// The units inside a deck: Phycology's Unit 1, Unit 2, and so on.
///
/// A unit is a deck of its own — it can be studied, written into, pasted into — and its
/// cards also count towards the deck above it, so studying Phycology draws from every unit.
struct UnitsView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var newUnitName = ""
    @State private var isAddingUnit = false
    @State private var writingInto: StoredDeck?
    @State private var unitsOf: StoredDeck?

    private var units: [StoredDeck] { deck.liveUnits }
    private var ownCards: Int { deck.cards.filter { $0.deletedAt == nil }.count }

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 14) {
                    if ownCards > 0 {
                        Text("^[\(ownCards) card](inflect: true) sit in \(deck.name) itself, outside any unit.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.softInk(scheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                    }

                    ForEach(units) { unit in
                        WarmCard(padding: 18) {
                            HStack(spacing: 14) {
                                NavigationLink {
                                    StudyView(deck: unit)
                                } label: {
                                    UnitRow(unit: unit)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    writingInto = unit
                                } label: {
                                    Image(systemName: "pencil.and.scribble")
                                        .font(.system(size: 18, weight: .medium))
                                        .frame(width: 46, height: 46)
                                        .background(Circle().fill(Theme.accent(scheme).opacity(0.15)))
                                        .foregroundStyle(Theme.accent(scheme))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Write cards in \(unit.name)")

                                // Units can hold units of their own, as deep as the subject goes.
                                Button {
                                    unitsOf = unit
                                } label: {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.system(size: 17, weight: .medium))
                                        .frame(width: 46, height: 46)
                                        .background(Circle().fill(Theme.ink(scheme).opacity(0.07)))
                                        .foregroundStyle(Theme.ink(scheme))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Units of \(unit.name)")
                            }
                        }
                        .contextMenu {
                            Button("Delete unit", systemImage: "trash", role: .destructive) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    unit.deletedAt = Date()
                                    try? context.save()
                                }
                            }
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if units.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 34, weight: .light))
                                .foregroundStyle(Theme.softInk(scheme))
                            Text("No units yet")
                                .font(Theme.title(20))
                                .foregroundStyle(Theme.ink(scheme))
                            Text("Split \(deck.name) into units — one per topic or chapter. Studying the deck still covers all of them.")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.softInk(scheme))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .top) {
            AppHeader(title: deck.name, subtitle: "Units", onBack: { dismiss() }) {
                HeaderButton(symbol: "plus", label: "New unit", tint: Theme.accent(scheme)) {
                    isAddingUnit = true
                }
            }
            .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $writingInto) { unit in
            RapidCaptureView(deck: unit)
        }
        .navigationDestination(item: $unitsOf) { unit in
            UnitsView(deck: unit)
        }
        .overlay {
            if isAddingUnit {
                AppDialog(
                    title: "New unit",
                    message: "A topic or chapter inside \(deck.name).",
                    confirmTitle: "Create",
                    isConfirmEnabled: !newUnitName.trimmingCharacters(in: .whitespaces).isEmpty,
                    onConfirm: { addUnit() },
                    onCancel: { withAnimation { isAddingUnit = false; newUnitName = "" } }
                ) {
                    AppTextField(placeholder: "Unit 1, Memory, Chapter 3…", text: $newUnitName)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isAddingUnit)
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: units.count)
    }

    private func addUnit() {
        let name = newUnitName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            let unit = StoredDeck(name: name, profile: deck.profile, parent: deck)
            unit.newCardsPerDay = deck.newCardsPerDay
            unit.maximumReviewsPerDay = deck.maximumReviewsPerDay
            context.insert(unit)
            try? context.save()
            newUnitName = ""
            isAddingUnit = false
        }
    }
}

private struct UnitRow: View {
    let unit: StoredDeck
    @Environment(\.colorScheme) private var scheme

    private var cards: [StoredCard] { unit.allCards }
    private var due: Int { cards.filter { $0.dueDate <= Date() }.count }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text(unit.name).font(Theme.display(20))
                HStack(spacing: 8) {
                    Text("^[\(cards.count) card](inflect: true)")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.softInk(scheme))
                    if !unit.liveUnits.isEmpty {
                        Text("· ^[\(unit.liveUnits.count) unit](inflect: true)")
                            .font(Theme.body(14))
                            .foregroundStyle(Theme.softInk(scheme))
                    }
                    if due > 0 {
                        Text("\(due) due")
                            .font(Theme.label(12))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.accent(scheme).opacity(0.16)))
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }
                MemoryBar(estimate: DeckListView.memory(for: unit))
                    .padding(.top, 1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
