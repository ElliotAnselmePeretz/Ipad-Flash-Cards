import SwiftUI
import SwiftData
import FlashcardsCore

/// Choose what to keep in memory, and when to work on it.
struct StudyPlanView: View {
    let profile: StoredProfile

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(StudyReminders.self) private var reminders

    @AppStorage("studyPlanSettings") private var settingsData = Data()
    @State private var settings = StudyPlanSettings.default
    @State private var showingPermissionNote = false

    private var decks: [StoredDeck] { profile.decks.filter { $0.deletedAt == nil } }
    private var workloads: [DeckWorkload] { PlanBuilder.workloads(for: profile) }
    private var planner: StudyPlanner { PlanBuilder.planner(for: profile, settings: settings) }
    private var plan: StudyPlan { planner.plan(for: workloads) }
    private var needingAttention: [DeckWorkload] { planner.decksNeedingAttention(workloads) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                enableCard
                if settings.isEnabled {
                    todayCard
                    timesCard
                    decksCard
                    lengthCard
                    nudgeCard
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page(scheme))
        .navigationTitle("Study plan")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            load()
            await reminders.refreshAuthorization()
        }
        .onChange(of: settings) { _, _ in save() }
    }

    // MARK: - Cards

    private var enableCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { settings.isEnabled },
                    set: { on in
                        settings.isEnabled = on
                        if on { Task { await enable() } } else { Task { await reminders.cancelAll() } }
                    }
                )) {
                    Text("Study plan")
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink(scheme))
                }
                .accessibilityIdentifier("plan.enable")

                Text("Splits what is due across short sittings and reminds you when they "
                     + "arrive. Spreading practice out is what makes it stick — the length "
                     + "of any one sitting matters far less than doing it more than once.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.softInk(scheme))

                if settings.isEnabled && reminders.authorization == .denied {
                    Label("Notifications are off for this app. Turn them on in Settings to "
                          + "get reminders; the plan still works without them.",
                          systemImage: "bell.slash")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.hard(scheme))
                }
            }
        }
    }

    private var todayCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Today")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink(scheme))

                if plan.isEmpty {
                    Text("Nothing due. Enjoy it.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.softInk(scheme))
                } else {
                    ForEach(plan.sessions) { session in
                        HStack(alignment: .top, spacing: 14) {
                            Text(session.label)
                                .font(Theme.label(16))
                                .foregroundStyle(Theme.accent(scheme))
                                .frame(width: 74, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("^[\(session.cardCount) card](inflect: true) · about \(session.estimatedMinutes) min")
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.ink(scheme))
                                Text(deckNames(session.deckIDs))
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.softInk(scheme))
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    if plan.deferredCards > 0 {
                        Text("^[\(plan.deferredCards) card](inflect: true) won't fit today and will roll over.")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.medium(scheme))
                    }

                    Text("Total: about \(plan.totalMinutes) minutes")
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.softInk(scheme))
                }
            }
        }
        .softGlow(Theme.glow(scheme), active: !plan.isEmpty, maxOpacity: 0.5)
    }

    private var timesCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("When")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink(scheme))

                ForEach(Array(settings.slots.enumerated()), id: \.offset) { index, slot in
                    HStack {
                        DatePicker(
                            "Sitting \(index + 1)",
                            selection: Binding(
                                get: { dateFrom(slot) },
                                set: { settings.slots[index] = slotFrom($0) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .font(Theme.body(15))

                        if settings.slots.count > 1 {
                            Button {
                                settings.slots.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.hard(scheme))
                        }
                    }
                }

                if settings.slots.count < 4 {
                    Button("Add a sitting") {
                        settings.slots.append(StudySlot(hour: 13))
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var decksCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("What")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink(scheme))
                Text(settings.deckIDs.isEmpty ? "Every deck." : "^[\(settings.deckIDs.count) deck](inflect: true) selected.")
                    .font(Theme.body(14))
                    .foregroundStyle(Theme.softInk(scheme))

                ForEach(decks) { deck in
                    let included = settings.deckIDs.isEmpty || settings.deckIDs.contains(deck.id)
                    Button {
                        toggle(deck)
                    } label: {
                        HStack {
                            Image(systemName: included ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(included ? Theme.accent(scheme) : Theme.softInk(scheme))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(deck.name)
                                    .font(Theme.body(15))
                                    .foregroundStyle(Theme.ink(scheme))
                                MemoryBar(estimate: DeckListView.memory(for: deck), showsLabel: false, height: 5)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lengthCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("How long")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink(scheme))
                Stepper(value: Binding(
                    get: { settings.maximumSessionMinutes },
                    set: { settings.maximumSessionMinutes = $0 }
                ), in: 5...60, step: 5) {
                    Text("At most \(settings.maximumSessionMinutes) minutes a sitting")
                        .font(Theme.body(15))
                }
                Text("Anything that will not fit rolls over rather than making one long session.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.softInk(scheme))
            }
        }
    }

    private var nudgeCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nudges")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink(scheme))

                Stepper(value: Binding(
                    get: { settings.nudgeAfterDays },
                    set: { settings.nudgeAfterDays = $0 }
                ), in: 1...30) {
                    Text("Say something after \(settings.nudgeAfterDays) quiet ^[day](inflect: true)")
                        .font(Theme.body(15))
                }

                if needingAttention.isEmpty {
                    Text("Nothing is slipping right now.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.easy(scheme))
                } else {
                    ForEach(needingAttention.prefix(3)) { deck in
                        HStack {
                            Text(deck.name).font(Theme.body(15))
                            Spacer()
                            Text("\(Int(deck.recallProbability * 100))%")
                                .font(Theme.label(14))
                                .foregroundStyle(Theme.hard(scheme))
                        }
                    }
                }
            }
        }
    }

    private func deckNames(_ ids: [UUID]) -> String {
        let names = ids.compactMap { id in decks.first { $0.id == id }?.name }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    // MARK: - Actions

    private func toggle(_ deck: StoredDeck) {
        if settings.deckIDs.isEmpty {
            // "All" is stored as empty; selecting one means everything except it.
            settings.deckIDs = decks.map(\.id).filter { $0 != deck.id }
        } else if settings.deckIDs.contains(deck.id) {
            settings.deckIDs.removeAll { $0 == deck.id }
        } else {
            settings.deckIDs.append(deck.id)
        }
    }

    private func enable() async {
        if reminders.authorization == .notAsked {
            await reminders.requestAuthorization()
        }
        await reminders.reschedule(plan: plan, decksNeedingAttention: needingAttention, settings: settings)
    }

    private func load() {
        if let decoded = try? JSONDecoder().decode(StudyPlanSettings.self, from: settingsData) {
            settings = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) { settingsData = data }
        Task {
            await reminders.reschedule(plan: plan, decksNeedingAttention: needingAttention, settings: settings)
        }
    }

    private func dateFrom(_ slot: StudySlot) -> Date {
        Calendar.current.date(from: DateComponents(hour: slot.hour, minute: slot.minute)) ?? Date()
    }

    private func slotFrom(_ date: Date) -> StudySlot {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return StudySlot(hour: parts.hour ?? 8, minute: parts.minute ?? 0)
    }
}
