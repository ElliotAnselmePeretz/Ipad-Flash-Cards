import SwiftUI
import SwiftData

struct ProfilePickerView: View {
    @Query(sort: \StoredProfile.createdAt) private var profiles: [StoredProfile]
    @Environment(\.modelContext) private var context
    @State private var newName = ""
    @State private var isAddingProfile = false

    let onSelect: (StoredProfile) -> Void

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 24)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(profiles) { profile in
                        Button { onSelect(profile) } label: {
                            VStack(spacing: 12) {
                                Image(systemName: profile.avatar)
                                    .font(.system(size: 56))
                                    .foregroundStyle(.tint)
                                Text(profile.name).font(.title3.weight(.medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                context.delete(profile)
                            }
                        }
                    }

                    Button { isAddingProfile = true } label: {
                        VStack(spacing: 12) {
                            Image(systemName: "plus.circle").font(.system(size: 56))
                            Text("Add profile").font(.title3.weight(.medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(32)
            }
            .navigationTitle("Who's studying?")
            .alert("New profile", isPresented: $isAddingProfile) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) { newName = "" }
                Button("Create") { createProfile() }
            }
        }
    }

    private func createProfile() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let profile = StoredProfile(name: trimmed)
        context.insert(profile)
        try? context.save()
        newName = ""
        onSelect(profile)
    }
}
