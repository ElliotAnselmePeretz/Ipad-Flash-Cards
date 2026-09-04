import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    /// Foreground time is only measurable while the app is running, so this starts
    /// counting from first launch — there is no history to backfill.
    @State private var usage = UsageTracker()
    @Environment(\.scenePhase) private var scenePhase
    /// Local-only for now. Switching to `cloudKitDatabase: .automatic` is the one-line
    /// change that turns this into a synced app — the models are already shaped for it
    /// (UUID keys, modifiedAt, soft deletes, every record scoped by profile).
    let container: ModelContainer = {
        let schema = Schema([StoredProfile.self, StoredDeck.self, StoredCard.self, StoredReviewLog.self])
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
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: usage.appDidEnterForeground()
                    case .background, .inactive: usage.appDidEnterBackground()
                    @unknown default: break
                    }
                }
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

    var body: some View {
        Group {
            if let profile = profiles.first {
                // Dev-only: lets the progress screen be opened directly for verification.
                if ProcessInfo.processInfo.arguments.contains("-open-progress") {
                    NavigationStack { OverallProgressView(profile: profile) }
                } else {
                    DeckListView(profile: profile)
                }
            } else {
                // First launch: nothing to choose, so just get out of the way.
                ProgressView().task { createDefaultProfile() }
            }
        }
        .preferredColorScheme(appearance.colorScheme)
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
