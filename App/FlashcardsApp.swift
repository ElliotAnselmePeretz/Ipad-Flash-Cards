import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    /// Foreground time is only measurable while the app is running, so this starts
    /// counting from first launch — there is no history to backfill.
    @State private var usage = UsageTracker()
    @State private var reminders = StudyReminders()
    /// Local-only for now. Switching to `cloudKitDatabase: .automatic` is the one-line
    /// change that turns this into a synced app — the models are already shaped for it
    /// (UUID keys, modifiedAt, soft deletes, every record scoped by profile).
    let container: ModelContainer = {
        let schema = Schema([StoredProfile.self, StoredDeck.self, StoredCard.self, StoredReviewLog.self, StoredGlyph.self])
        // UI tests pass -ui-testing-reset so each test starts from an empty store
        // instead of inheriting whatever the previous test left behind.
        let inMemory = ProcessInfo.processInfo.arguments.contains("-ui-testing-reset")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(usage)
                .environment(reminders)
        }
        .modelContainer(container)
    }
}

/// The app opens straight into the decks. There is no sign-in and no profile picker:
/// this is a single-person app on a personal iPad.
///
/// A `Profile` record still exists underneath, created silently on first launch, because
/// every deck, card and review log is scoped by `profileID`. Keeping that scoping means
/// multiple users or CloudKit sync remain possible later without a data migration.
struct RootView: View {
    @Query(sort: \StoredProfile.createdAt) private var profiles: [StoredProfile]
    @Environment(\.modelContext) private var context
    @AppStorage("appearance") private var appearance = Appearance.system
    @Environment(UsageTracker.self) private var usage
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let profile = profiles.first {
                // Dev-only: lets the progress screen be opened directly for verification.
                if ProcessInfo.processInfo.arguments.contains("-open-progress") {
                    NavigationStack { OverallProgressView(profile: profile) }
                } else if ProcessInfo.processInfo.arguments.contains("-open-handwriting") {
                    NavigationStack { HandwritingCaptureView() }
                } else if ProcessInfo.processInfo.arguments.contains("-open-study"),
                          let deck = seededStudyDeck(profile) ?? profile.decks.first(where: { $0.deletedAt == nil && !$0.cards.isEmpty }) {
                    NavigationStack { StudyView(deck: deck) }
                } else if ProcessInfo.processInfo.arguments.contains("-open-cards"),
                          let deck = profile.decks.first(where: { $0.deletedAt == nil && !$0.cards.isEmpty }) {
                    NavigationStack { CardListView(deck: deck) }
                } else if ProcessInfo.processInfo.arguments.contains("-open-paste"),
                          let deck = profile.decks.first(where: { $0.deletedAt == nil }) {
                    NavigationStack { PasteCardsView(deck: deck) }
                } else {
                    DeckListView(profile: profile)
                }
            } else {
                // First launch: nothing to choose, so just get out of the way.
                ProgressView().task { createDefaultProfile() }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
        .task { BackupSelfTest.runIfRequested(context: context) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                usage.appDidEnterForeground()
            case .background, .inactive:
                usage.appDidEnterBackground()
                backupIfDue()
            @unknown default:
                break
            }
        }
    }

    private static let seedDeckName = "Seed"

    /// Dev-only: a throwaway deck holding one card written out from STUDY_SEED, so the
    /// study card can be looked at with real ink of a chosen length.
    private func seededStudyDeck(_ profile: StoredProfile) -> StoredDeck? {
        guard let text = ProcessInfo.processInfo.environment["STUDY_SEED"] else { return nil }
        // This is reached from `body`, which runs repeatedly: without reusing the deck it
        // made last time, every pass inserted another one.
        let store = HandwritingStore(context: context)
        let ink = store.compose(text, maxWidth: 680).drawing.dataRepresentation()

        if let existing = profile.decks.first(where: { $0.name == Self.seedDeckName && $0.deletedAt == nil }) {
            // Written out again each launch, so a change to the composer can be seen rather
            // than the ink from whenever the deck was first made.
            // Only when the text itself changes: composing picks between captured samples at
            // random, so comparing the ink would rewrite it on every pass and leave the card
            // endlessly crossfading between two versions of itself.
            if let card = existing.cards.first, card.frontText != text {
                card.frontText = text
                card.frontDrawing = ink
            }
            return existing
        }
        let deck = StoredDeck(name: Self.seedDeckName, profile: profile)
        let card = StoredCard(deck: deck, frontText: text)
        card.frontDrawing = ink
        context.insert(deck)
        context.insert(card)
        return deck
    }

    /// Leaving the app is the natural moment to save: the day's work is done.
    private func backupIfDue() {
        guard let profile = profiles.first else { return }
        AutoBackup.runIfDue(profile: profile, context: context)
    }

    private func createDefaultProfile() {
        guard profiles.isEmpty else { return }
        let profile = StoredProfile(name: "My cards")
        context.insert(profile)
        if !ProcessInfo.processInfo.arguments.contains("-ui-testing-no-sample") {
            SampleDeck.add(to: profile, in: context)
        }
        try? context.save()
    }
}

/// Light, dark, or follow the system.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
