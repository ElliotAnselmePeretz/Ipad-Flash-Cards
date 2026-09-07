import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import FlashcardsCore

/// Bulk-adds cards from a CSV or tab-separated file.
///
/// The default is deliberately "questions only, answers handwritten": for a Pencil deck
/// the useful thing to import is the list of prompts, not typed answers.
struct ImportView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fileText: String?
    @State private var fileName: String?
    @State private var preview: ImportPreview?
    @State private var isPickingFile = false
    @State private var handwriteAnswers = true
    @State private var frontColumn = 0
    @State private var backColumn = 1
    @State private var skipDuplicates = true
    @State private var inMyHand = true
    @State private var errorMessage: String?

    private let importer = CardImporter()

    private var plan: ImportPlan {
        ImportPlan(
            hasHeaderRow: preview?.looksLikeHeaderRow ?? false,
            frontColumn: frontColumn,
            backColumn: handwriteAnswers ? nil : backColumn,
            skipDuplicates: skipDuplicates
        )
    }

    private var existingFronts: Set<String> {
        Set(deck.cards.filter { $0.deletedAt == nil }.map { $0.frontText.lowercased() })
    }

    private var result: ImportResult? {
        guard let fileText, let deckProfile = deck.profile else { return nil }
        return importer.makeCards(
            text: fileText, plan: plan,
            deckID: deck.id, profileID: deckProfile.id,
            existingFronts: skipDuplicates ? existingFronts : []
        )
    }

    var body: some View {
        Form {
            Section {
                Button {
                    isPickingFile = true
                } label: {
                    Label(fileName ?? "Choose a CSV file", systemImage: "doc.badge.plus")
                }
                .accessibilityIdentifier("import.chooseFile")
            } footer: {
                Text("A CSV or tab-separated file. One card per row.")
            }

            if let preview, !preview.columnNames.isEmpty {
                Section("Questions") {
                    Picker("Question column", selection: $frontColumn) {
                        ForEach(Array(preview.columnNames.enumerated()), id: \.offset) { i, name in
                            Text(name).tag(i)
                        }
                    }
                }

                Section {
                    Toggle("Write answers by hand", isOn: $handwriteAnswers)
                        .accessibilityIdentifier("import.handwriteToggle")

                    if !handwriteAnswers {
                        Picker("Answer column", selection: $backColumn) {
                            ForEach(Array(preview.columnNames.enumerated()), id: \.offset) { i, name in
                                Text(name).tag(i)
                            }
                        }
                    }
                } footer: {
                    Text(handwriteAnswers
                         ? "Cards arrive with the question filled in and the answer blank, ready to write with your Pencil."
                         : "Answers are taken from the file as typed text.")
                }

                Section("Options") {
                    Toggle("Skip questions already in this deck", isOn: $skipDuplicates)
                    if HandwritingStore(context: context).capturedCount() > 0 {
                        Toggle("Write the text in my handwriting", isOn: $inMyHand)
                            .accessibilityIdentifier("import.inMyHand")
                    }
                }

                Section("Preview") {
                    ForEach(Array(preview.sampleRows.prefix(4).enumerated()), id: \.offset) { _, row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(frontColumn < row.count ? row[frontColumn] : "—")
                                .font(.body)
                            Text(handwriteAnswers
                                 ? "handwritten"
                                 : (backColumn < row.count ? row[backColumn] : "—"))
                                .font(.caption)
                                .foregroundStyle(handwriteAnswers ? .tertiary : .secondary)
                                .italic(handwriteAnswers)
                        }
                    }
                }

                if let result {
                    Section {
                        LabeledContent("Will import") {
                            Text("\(result.importedCount)").accessibilityIdentifier("import.count")
                        }
                        if result.skippedDuplicates > 0 {
                            LabeledContent("Skipped as duplicates", value: "\(result.skippedDuplicates)")
                        }
                        if result.skippedEmpty > 0 {
                            LabeledContent("Skipped as blank", value: "\(result.skippedEmpty)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Import cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                let count = result?.importedCount ?? 0
                Button(count > 0 ? "Import \(count)" : "Import") { performImport() }
                    .disabled(count == 0)
                    .accessibilityIdentifier("import.confirm")
            }
        }
        .task {
            // Test seam: the system file picker cannot be driven by UI tests, so tests
            // inject the file's contents and exercise everything downstream of it.
            if fileText == nil, let injected = ProcessInfo.processInfo.environment["UITEST_CSV"] {
                fileText = injected
                fileName = "test.csv"
                let p = importer.preview(text: injected)
                preview = p
                frontColumn = 0
                backColumn = min(1, max(0, p.columnNames.count - 1))
            }
        }
        .fileImporter(isPresented: $isPickingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { outcome in
            load(outcome)
        }
        .alert("Could not read that file", isPresented: .init(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load(_ outcome: Result<URL, Error>) {
        switch outcome {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            // Files chosen through the picker live outside the sandbox.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .isoLatin1) else {
                    errorMessage = "The file isn't readable as text."
                    return
                }
                fileText = text
                fileName = url.lastPathComponent
                let p = importer.preview(text: text)
                preview = p
                frontColumn = 0
                backColumn = min(1, max(0, p.columnNames.count - 1))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func performImport() {
        guard let result else { return }
        let handwriting = HandwritingStore(context: context)
        let write = inMyHand && handwriting.capturedCount() > 0
        for card in result.cards {
            let stored = StoredCard(deck: deck, frontText: card.front.text, backText: card.back.text)
            stored.createdAt = card.createdAt
            if write {
                stored.frontDrawing = handwriting.compose(card.front.text, maxWidth: 680).drawing.dataRepresentation()
                if !card.back.text.isEmpty {
                    stored.backDrawing = handwriting.compose(card.back.text, maxWidth: 680).drawing.dataRepresentation()
                }
            }
            context.insert(stored)
        }
        try? context.save()
        dismiss()
    }
}
