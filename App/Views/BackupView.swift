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

    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var message: String?
    @State private var isError = false

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
        .navigationTitle("Backup")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { url in
            ShareSheet(url: url)
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.json, .data, .item]) { outcome in
            restore(outcome)
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
                show("Restored ^[\(summary.decksAdded) deck](inflect: true) "
                     + "and ^[\(summary.cardsAdded) card](inflect: true).", error: false)
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
