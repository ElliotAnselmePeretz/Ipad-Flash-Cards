import SwiftUI
import SwiftData
import FlashcardsCore


struct DeckListView: View {
    let profile: StoredProfile

    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = Appearance.system
    @AppStorage("studyPlanSettings") private var planSettingsData = Data()
    @Environment(\.colorScheme) private var scheme
    @State private var newDeckName = ""
    @State private var isAddingDeck = false
    @State private var writingInto: StoredDeck?

    private static let estimator = MemoryEstimator()

    static func memory(for deck: StoredDeck, now: Date = Date()) -> MemoryEstimate {
        estimator.estimate(
            for: deck.cards.filter { $0.deletedAt == nil }.map(\.scheduling),
            now: now
        )
    }

    /// Everything the screen needs about the decks, worked out in a single pass.
    ///
    /// This used to be four computed properties that each walked every card, and a sort
    /// whose comparator ran the memory estimate afresh on both sides of every comparison.
    /// A view body runs far more often than it looks — on every frame of an animation —
    /// so that arrangement re-ran the whole FSRS estimate for the library dozens of times
    /// a second and pinned a core for as long as the screen was open.
    struct Overview {
        var decks: [StoredDeck] = []
        var memory: [UUID: MemoryEstimate] = [:]
        var dueNow = 0
        var totalCards = 0
        var reviewedToday = 0
    }

    private func makeOverview(now: Date = Date()) -> Overview {
        var overview = Overview()
        let live = profile.decks.filter { $0.deletedAt == nil }
        let startOfToday = Calendar.current.startOfDay(for: now)

        for deck in live {
            let cards = deck.cards.filter { $0.deletedAt == nil }
            // Estimated once per deck, then looked up: the sort must not recompute it.
            overview.memory[deck.id] = Self.estimator.estimate(for: cards.map(\.scheduling), now: now)
            overview.totalCards += cards.count
            for card in cards {
                if card.dueDate <= now { overview.dueNow += 1 }
                for log in card.reviewLogs where log.reviewedAt >= startOfToday {
                    overview.reviewedToday += 1
                }
            }
        }

        // Ordered by what you are closest to forgetting, so the deck that needs you is
        // first. Decks with nothing studied yet sort last: there is nothing to lose there.
        overview.decks = live.sorted { a, b in
            guard let ma = overview.memory[a.id], let mb = overview.memory[b.id] else {
                return a.createdAt < b.createdAt
            }
            if ma.isEmpty != mb.isEmpty { return !ma.isEmpty }
            if ma.recallProbability != mb.recallProbability {
                return ma.recallProbability < mb.recallProbability
            }
            return a.createdAt < b.createdAt
        }
        return overview
    }

    private func cycleAppearance() {
        let all = Appearance.allCases
        let next = (all.firstIndex(of: appearance).map { $0 + 1 } ?? 0) % all.count
        withAnimation { appearance = all[next] }
    }

    private func addDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            let deck = StoredDeck(name: name, profile: profile)
            context.insert(deck)
            try? context.save()
            newDeckName = ""
            isAddingDeck = false
        }
    }

    private func addSampleDeck() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            SampleDeck.add(to: profile, in: context)
        }
    }

    private var planSettings: StudyPlanSettings {
        (try? JSONDecoder().decode(StudyPlanSettings.self, from: planSettingsData)) ?? .default
    }

    /// The plan lived behind a menu, which meant nobody found it. It belongs on the first
    /// screen: either today's sittings, or an invitation to set them up.
    @ViewBuilder
    private var planCard: some View {
        let settings = planSettings
        if settings.isEnabled {
            let planner = PlanBuilder.planner(for: profile, settings: settings)
            let plan = planner.plan(for: PlanBuilder.workloads(for: profile))
            WarmCard(padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Study plan", systemImage: "calendar")
                            .font(Theme.label(15))
                            .foregroundStyle(Theme.accent(scheme))
                        Spacer()
                        if let goal = plan.goal {
                            Text("\(goal.name) \(goal.countdown())")
                                .font(Theme.body(13))
                                .foregroundStyle(Theme.softInk(scheme))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.softInk(scheme))
                    }

                    if plan.isEmpty {
                        Text("Nothing due today.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.softInk(scheme))
                    } else {
                        HStack(spacing: 18) {
                            ForEach(plan.sessions) { session in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.label)
                                        .font(Theme.label(16))
                                        .foregroundStyle(Theme.ink(scheme))
                                    Text("^[\(session.cardCount) card](inflect: true) · \(session.estimatedMinutes)m")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.softInk(scheme))
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        } else {
            WarmCard(padding: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.accent(scheme))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Make a study plan")
                            .font(Theme.label(16))
                            .foregroundStyle(Theme.ink(scheme))
                        Text("Short sittings, reminders, and test dates that jump the queue.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.softInk(scheme))
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.softInk(scheme))
                }
            }
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
    private func summaryHeader(_ overview: Overview) -> some View {
        Group {
        if !overview.decks.isEmpty {
            WarmCard(padding: 18) {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting)
                                .font(Theme.display(24))
                                .foregroundStyle(Theme.ink(scheme))
                            Text(overview.dueNow == 0
                                 ? "Nothing due right now."
                                 : "^[\(overview.dueNow) card](inflect: true) waiting for you.")
                                .font(Theme.body(15))
                                .foregroundStyle(Theme.softInk(scheme))
                        }
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        StatChip(value: "\(overview.dueNow)", label: "due now", tint: Theme.accent(scheme))
                        StatChip(value: "\(overview.reviewedToday)", label: "done today", tint: Theme.easy(scheme))
                        StatChip(value: "\(overview.totalCards)", label: "cards", tint: nil)
                    }
                }
            }
            // A faint halo when something is actually waiting, and none when it is not.
            .softGlow(Theme.glow(scheme), active: overview.dueNow > 0, maxOpacity: 0.6)
            .animation(.easeInOut(duration: 0.5), value: overview.dueNow)
        }
        }
    }

    var body: some View {
        // Worked out once for the whole pass, then handed down.
        let overview = makeOverview()
        return NavigationStack {
            VStack(spacing: 0) {
                AppHeader(title: "Decks") {
                    HeaderButton(symbol: "circle.lefthalf.filled", label: "Appearance") {
                        cycleAppearance()
                    }
                    NavigationLink {
                        OverallProgressView(profile: profile)
                    } label: {
                        HeaderGlyph(symbol: "chart.line.uptrend.xyaxis", label: "Progress")
                    }
                    NavigationLink {
                        HandwritingCaptureView()
                    } label: {
                        HeaderGlyph(symbol: "signature", label: "Your handwriting")
                    }
                    HeaderButton(symbol: "plus", label: "New deck", tint: Theme.accent(scheme)) {
                        isAddingDeck = true
                    }
                }

                ScrollView {
                LazyVStack(spacing: 14) {
                    NavigationLink {
                        OverallProgressView(profile: profile)
                    } label: {
                        summaryHeader(overview)
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        StudyPlanView(profile: profile)
                    } label: {
                        planCard
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 4)

                    ForEach(Array(overview.decks.enumerated()), id: \.element.id) { index, deck in
                        WarmCard(padding: 18) {
                            HStack(spacing: 14) {
                                NavigationLink {
                                    StudyView(deck: deck)
                                } label: {
                                    DeckRow(deck: deck, estimate: overview.memory[deck.id])
                                }
                                .buttonStyle(.plain)

                                // A visible way to add cards without entering the deck.
                                Button {
                                    writingInto = deck
                                } label: {
                                    Image(systemName: "pencil.and.scribble")
                                        .font(.system(size: 18, weight: .medium))
                                        .frame(width: 46, height: 46)
                                        .background(
                                            Circle().fill(Theme.accent(scheme).opacity(0.15))
                                        )
                                        .foregroundStyle(Theme.accent(scheme))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Write cards in \(deck.name)")
                                .accessibilityIdentifier("deck.write")
                            }
                        }
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
                                    .delay(Double(index) * 0.04), value: overview.decks.count)
                    }
                }
                    .padding(20)
                }
                .background(Theme.page(scheme))
            }
            .background(Theme.page(scheme))
            .navigationBarHidden(true)
            .navigationDestination(item: $writingInto) { deck in
                RapidCaptureView(deck: deck)
            }
            .overlay {
                if isAddingDeck {
                    AppDialog(
                        title: "New deck",
                        message: "What is it a deck of?",
                        confirmTitle: "Create",
                        isConfirmEnabled: !newDeckName.trimmingCharacters(in: .whitespaces).isEmpty,
                        onConfirm: { addDeck() },
                        onCancel: { withAnimation { isAddingDeck = false; newDeckName = "" } }
                    ) {
                        AppTextField(placeholder: "Derivatives, Spanish verbs…", text: $newDeckName)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isAddingDeck)
            .overlay {
                if overview.decks.isEmpty {
                    EmptyDecksView(onAddSample: addSampleDeck)
                }
            }
        }
    }

}

private struct DeckRow: View {
    let deck: StoredDeck
    /// Passed in from the screen's single pass, rather than estimated again per row.
    var estimate: MemoryEstimate?
    @Environment(\.colorScheme) private var scheme

    private var liveCards: [StoredCard] { deck.cards.filter { $0.deletedAt == nil } }
    private var dueCount: Int { liveCards.filter { $0.dueDate <= Date() }.count }

    private var counts: QueueCounts {
        ReviewQueue(deck: deck.core).counts(from: deck.cards.map(\.core))
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
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
                MemoryBar(estimate: estimate ?? DeckListView.memory(for: deck))
                    .padding(.top, 1)
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
                .softGlow(Theme.glow(scheme), maxOpacity: 0.6)

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
