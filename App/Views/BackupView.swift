import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FlashcardsCore

/// Export and restore. Handwriting cannot be retyped, so this is the difference between a
/// mistake costing an afternoon and costing everything.
struct BackupView: View {
    let profile: StoredProfile

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var message: String?
    @State private var isError = false
    @State private var automatic: [URL] = []

    private var service: BackupService { BackupService(context: context) }

    private var liveDecks: [StoredDeck] { profile.decks.filter { $0.deletedAt == nil } }
    private var cardCount: Int {
        liveDecks.reduce(0) { $0 + $1.cards.filter { $0.deletedAt == nil }.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WarmCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Back up")
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.ink(scheme))
                        Text("Saves every deck, every drawing and all your review history "
                             + "to one file. Keep it in iCloud Drive or Files.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.softInk(scheme))

                        HStack(spacing: 10) {
                            StatChip(value: "\(liveDecks.count)", label: "decks", tint: nil)
                            StatChip(value: "\(cardCount)", label: "cards", tint: nil)
                        }

                        Button {
                            exportBackup()
                        } label: {
                            Label("Save a backup", systemImage: "square.and.arrow.up")
                                .font(Theme.label(17))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
                        .disabled(cardCount == 0)
                        .accessibilityIdentifier("backup.export")
                    }
                }

                WarmCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Restore")
                            .font(Theme.display(22))
                            .foregroundStyle(Theme.ink(scheme))
                        Text("Adds the decks from a backup file. Nothing already here is "
                             + "removed or overwritten.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.softInk(scheme))

                        Button {
                            isImporting = true
                        } label: {
                            Label("Restore from a file", systemImage: "square.and.arrow.down")
                                .font(Theme.label(17))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("backup.import")
                    }
                }

                WarmCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Automatic")
                                .font(Theme.display(22))
                                .foregroundStyle(Theme.ink(scheme))
                            Spacer()
                            Button("Back up now") { makeAutomaticBackup() }
                                .buttonStyle(QuietButtonStyle())
                                .accessibilityIdentifier("backup.now")
                        }
                        Text("The app saves a copy to its own storage when you leave it, "
                             + "keeping the last \(AutoBackup.keepCount). These survive app "
                             + "updates but not deleting the app, so keep a copy elsewhere too.")
                            .font(Theme.body(15))
                            .foregroundStyle(Theme.softInk(scheme))

                        if automatic.isEmpty {
                            Text("No automatic backups yet.")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.softInk(scheme))
                                .padding(.top, 2)
                        } else {
                            ForEach(automatic, id: \.self) { url in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.deletingPathExtension().lastPathComponent
                                                .replacingOccurrences(of: "InkRecall-", with: ""))
                                            .font(Theme.body(15))
                                        Text(sizeLabel(url))
                                            .font(Theme.body(12))
                                            .foregroundStyle(Theme.softInk(scheme))
                                    }
                                    Spacer()
                                    Button("Share") { exportURL = url }
                                        .buttonStyle(QuietButtonStyle())
                                    Button("Restore") { restore(.success(url)) }
                                        .buttonStyle(QuietButtonStyle())
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                if let message {
                    Text(message)
                        .font(Theme.body(15))
                        .foregroundStyle(isError ? Theme.hard(scheme) : Theme.easy(scheme))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }
            .padding(20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page(scheme))
        .safeAreaInset(edge: .top) {
            AppHeader(title: "Backup", onBack: { dismiss() })
                .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .onAppear { automatic = AutoBackup.existing() }
        .sheet(item: $exportURL) { url in
            ShareSheet(url: url)
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.json, .data, .item]) { outcome in
            restore(outcome)
        }
    }

    private func sizeLabel(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func makeAutomaticBackup() {
        if AutoBackup.write(profile: profile, context: context) != nil {
            automatic = AutoBackup.existing()
            show("Saved a backup on this iPad.", error: false)
        } else {
            show("Could not save a backup.", error: true)
        }
    }

    private func exportBackup() {
        do {
            exportURL = try service.writeArchiveFile(for: profile)
        } catch {
            show("Could not create the backup: \(error.localizedDescription)", error: true)
        }
    }

    private func restore(_ outcome: Result<URL, Error>) {
        switch outcome {
        case .failure(let error):
            show(error.localizedDescription, error: true)
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let summary = try service.restore(data, into: profile)
                automatic = AutoBackup.existing()
                show("Restored \(counted(summary.decksAdded, "deck")) "
                     + "and \(counted(summary.cardsAdded, "card")).", error: false)
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        isError = error
        withAnimation { message = text }
    }
}

/// URLs need identity to drive `.sheet(item:)`.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
