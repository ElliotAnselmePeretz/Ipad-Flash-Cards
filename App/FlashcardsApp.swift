import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    /// Local-only for now. Switching to `cloudKitDatabase: .automatic` is the one-line
    /// change that turns this into a synced app — the models are already shaped for it
    /// (UUID keys, modifiedAt, soft deletes, every record scoped by profile).
    let container: ModelContainer = {
        let schema = Schema([StoredProfile.self, StoredDeck.self, StoredCard.self, StoredReviewLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

/// Profile gate: pick who is studying before anything else is shown.
struct RootView: View {
    @Query(sort: \StoredProfile.createdAt) private var profiles: [StoredProfile]
    @Environment(\.modelContext) private var context
    @State private var activeProfileID: UUID?

    var body: some View {
        Group {
            if let id = activeProfileID, let profile = profiles.first(where: { $0.id == id }) {
                DeckListView(profile: profile, onSwitchProfile: { activeProfileID = nil })
            } else {
                ProfilePickerView(onSelect: { activeProfileID = $0.id })
            }
        }
        .onAppear {
            // Single-profile installs shouldn't see a picker every launch.
            if activeProfileID == nil, profiles.count == 1 { activeProfileID = profiles.first?.id }
        }
    }
}
