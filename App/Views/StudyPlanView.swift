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
    @State private var newGoal: StudyGoal?

    private var decks: [StoredDeck] { profile.decks.filter { $0.deletedAt == nil } }
    private var workloads: [DeckWorkload] { PlanBuilder.workloads(for: profile) }
    private var planner: StudyPlanner { PlanBuilder.planner(for: profile, settings: settings) }
    private var plan: StudyPlan { planner.plan(for: workloads) }
    private var needingAttention: [DeckWorkload] { planner.decksNeedingAttention(workloads) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if settings.isEnabled {
                    todayCard
                    goalsCard
                    timesCard
                    decksCard
                    lengthCard
                    nudgeCard
                    turnOffCard
                } else {
                    createCard
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

    /// The empty state: one obvious button, and a plain description of what it will do.
    private var createCard: some View {
        WarmCard(padding: 26) {
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(Theme.accent(scheme))
                    .softGlow(Theme.glow(scheme), maxOpacity: 0.5)

                Text("Make a study plan")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.ink(scheme))

                Text("Splits what is due into short sittings at times you choose, and "
                     + "reminds you when they come round. Spreading practice out is what "
                     + "makes it stick; one long session does far less than two short ones.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.softInk(scheme))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    bullet("Two sittings a day to start, morning and evening")
                    bullet("About 15 minutes each, and it rolls over what will not fit")
                    bullet("Whatever you are closest to forgetting comes first")
                    bullet("Add a test date and its decks jump the queue")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    createPlan()
                } label: {
                    Text("Create my plan")
                        .font(Theme.label(18))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
                .accessibilityIdentifier("plan.create")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.easy(scheme))
                .padding(.top, 2)
            Text(text)
                .font(Theme.body(14))
                .foregroundStyle(Theme.softInk(scheme))
        }
    }

    private var turnOffCard: some View {
        WarmCard(padding: 18) {
            Button("Turn off the plan", role: .destructive) {
                settings.isEnabled = false
                Task { await reminders.cancelAll() }
            }
            .font(Theme.body(15))
            .frame(maxWidth: .infinity)
        }
    }

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
                HStack(alignment: .firstTextBaseline) {
                    Text("Today")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.ink(scheme))
                    Spacer()
                    if let goal = plan.goal {
                        Text("\(goal.name) \(goal.countdown())")
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }

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

    /// What you are working towards. A date is what turns "keep everything alive" into
    /// "get this ready by Thursday".
    private var goalsCard: some View {
        WarmCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Coming up")
                        .font(Theme.display(20))
                        .foregroundStyle(Theme.ink(scheme))
                    Spacer()
                    Button("Add") { newGoal = StudyGoal(name: "", date: defaultGoalDate, deckIDs: []) }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("plan.addGoal")
                }

                if upcomingGoals.isEmpty {
                    Text("No test or deadline set. Add one and its decks come first, more "
                         + "insistently as the date gets closer.")
                        .font(Theme.body(14))
                        .foregroundStyle(Theme.softInk(scheme))
                } else {
                    ForEach(upcomingGoals) { goal in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(goal.name.isEmpty ? "Untitled" : goal.name)
                                    .font(Theme.label(16))
                                    .foregroundStyle(Theme.ink(scheme))
                                Text("\(goal.countdown()) · \(deckNames(goal.deckIDs))")
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.softInk(scheme))
                            }
                            Spacer()
                            Button {
                                settings.goals.removeAll { $0.id == goal.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.hard(scheme))
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .sheet(item: $newGoal) { goal in
            NavigationStack {
                GoalEditor(goal: goal, decks: decks) { saved in
                    settings.goals.append(saved)
                    newGoal = nil
                } onCancel: { newGoal = nil }
            }
        }
    }

    private var upcomingGoals: [StudyGoal] {
        settings.goals.filter { $0.isUpcoming() }.sorted { $0.date < $1.date }
    }

    private var defaultGoalDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
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

    private func createPlan() {
        settings.isEnabled = true
        Task { await enable() }
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

/// Adding a test: what it is, when it is, and which decks it covers.
private struct GoalEditor: View {
    @State var goal: StudyGoal
    let decks: [StoredDeck]
    let onSave: (StudyGoal) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Form {
            Section("What") {
                TextField("Maths mock, driving theory…", text: $goal.name)
                    .accessibilityIdentifier("goal.name")
            }
            Section("When") {
                DatePicker("Date", selection: $goal.date, in: Date()..., displayedComponents: .date)
            }
            Section {
                ForEach(decks) { deck in
                    Button {
                        if goal.deckIDs.contains(deck.id) {
                            goal.deckIDs.removeAll { $0 == deck.id }
                        } else {
                            goal.deckIDs.append(deck.id)
                        }
                    } label: {
                        HStack {
                            Image(systemName: goal.deckIDs.contains(deck.id)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(goal.deckIDs.contains(deck.id)
                                                 ? Theme.accent(scheme) : Theme.softInk(scheme))
                            Text(deck.name).foregroundStyle(Theme.ink(scheme))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Which decks does it cover?")
            } footer: {
                Text("These jump the queue, and the plan pushes harder as the date nears.")
            }
        }
        .navigationTitle("Coming up")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add") { onSave(goal) }
                    .disabled(goal.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || goal.deckIDs.isEmpty)
                    .accessibilityIdentifier("goal.save")
            }
        }
    }
}
