import SwiftUI
import SwiftData
import PhotosUI
import PencilKit
import FlashcardsCore

/// Make cards out of pasted text, written in the user's own hand.
///
/// The text can be almost anything that holds questions and answers — QUESTION / ANSWER
/// labels, an Anki export, a two-column table, blocks with a blank line between them. It
/// is read as it is pasted and the count updates live, so what will be made is never a
/// surprise. With an alphabet captured, every card arrives already written out.
struct PasteCardsView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var text = ""
    @State private var inMyHand = true
    @State private var skipDuplicates = true
    @State private var added: Int?

    private var handwriting: HandwritingStore { HandwritingStore(context: context) }
    private var canWrite: Bool { handwriting.capturedCount() > 0 }

    /// Worked out when the text changes rather than in `body`.
    ///
    /// Parsing, composing handwriting and fetching the glyph library are all far too heavy
    /// to sit in a view body, which runs on every keystroke and every frame of an animation.
    @State private var parsed = PastedCards(cards: [], format: .empty)
    @State private var preview: (question: Data?, answer: Data?) = (nil, nil)
    @State private var missing: [Character] = []
    @State private var chosenPhotos: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var readingProblem: String?

    private var existingQuestions: Set<String> {
        Set(deck.cards.filter { $0.deletedAt == nil }.map { $0.frontText.lowercased() })
    }

    private var cards: [PastedCard] {
        guard skipDuplicates else { return parsed.cards }
        var seen = existingQuestions
        return parsed.cards.filter { seen.insert($0.question.lowercased()).inserted }
    }

    private var duplicates: Int { parsed.cards.count - cards.count }

    /// Reads the text, and writes out the first card so it can be seen before committing.
    private func reread() {
        parsed = PastedCardParser.parse(text)
        guard inMyHand, canWrite, let first = cards.first else {
            preview = (nil, nil)
            missing = []
            return
        }
        preview = (handwriting.compose(first.question, maxWidth: 640).drawing.dataRepresentation(),
                   first.answer.isEmpty ? nil
                    : handwriting.compose(first.answer, maxWidth: 640).drawing.dataRepresentation())
        let have = Set(handwriting.samples().keys)
        let needed = Set(cards.flatMap { ($0.question + $0.answer) }.filter { !$0.isWhitespace })
        missing = needed.subtracting(have).sorted()
    }

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    editor
                    if isReading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Reading the screenshots…")
                                .font(Theme.body(14))
                                .foregroundStyle(Theme.softInk(scheme))
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                    }
                    if let readingProblem {
                        Text(readingProblem)
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.hard(scheme))
                            .padding(.horizontal, 6)
                    }
                    if !text.isEmpty { reading }
                    if preview.question != nil { previewCard }
                    options
                }
                .frame(maxWidth: 760)
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top) {
            AppHeader(title: "Paste cards", subtitle: deck.name, onBack: { dismiss() }) {
                PhotosPicker(selection: $chosenPhotos, matching: .images, photoLibrary: .shared()) {
                    HeaderGlyph(symbol: "text.viewfinder", label: "Read screenshots")
                }
                .accessibilityIdentifier("paste.photos")
                HeaderButton(symbol: "doc.on.clipboard", label: "Paste from clipboard") {
                    if let clip = UIPasteboard.general.string { text = clip }
                }
            }
            .background(Theme.page(scheme))
        }
        .safeAreaInset(edge: .bottom) { addButton }
        .navigationBarHidden(true)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: cards.count)
        .task {
            // Dev seam: the screen can be opened with text already in it, so the reading and
            // the handwritten preview can be checked without a keyboard.
            if text.isEmpty, let seeded = ProcessInfo.processInfo.environment["PASTE_TEXT"] {
                text = seeded
            }
            // Dev seam: the photo picker cannot be driven from a test, so a picture can be
            // handed straight to the same recognition path.
            if text.isEmpty, let path = ProcessInfo.processInfo.environment["SCAN_IMAGE"],
               let image = UIImage(contentsOfFile: path) {
                text = await Task.detached(priority: .userInitiated) {
                    TextFromImages.studyText(from: [image])
                }.value
            }
            reread()
        }
        .onChange(of: text) { _, _ in reread() }
        .onChange(of: chosenPhotos) { _, picked in
            guard !picked.isEmpty else { return }
            Task { await readPhotos(picked) }
        }
        .onChange(of: inMyHand) { _, _ in reread() }
    }

    // MARK: - Pieces

    private var editor: some View {
        WarmCard(padding: 16) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Paste questions and answers here, or tap the scan button above to read them off screenshots.\n\nQUESTION: … / ANSWER: … lines, an Anki export, two columns, or a blank line between each pair — all work.")
                        .font(Theme.body(15))
                        .foregroundStyle(Theme.softInk(scheme).opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.ink(scheme))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 220)
                    .accessibilityIdentifier("paste.text")
            }
        }
    }

    private var reading: some View {
        HStack(spacing: 8) {
            Image(systemName: cards.isEmpty ? "questionmark.circle" : "checkmark.circle.fill")
                .foregroundStyle(cards.isEmpty ? Theme.medium(scheme) : Theme.easy(scheme))
            Text(summary)
                .font(Theme.body(14))
                .foregroundStyle(Theme.softInk(scheme))
            Spacer()
        }
        .padding(.horizontal, 6)
        .accessibilityIdentifier("paste.summary")
    }

    private var summary: String {
        switch parsed.format {
        case .empty: return "Nothing to read yet."
        case .labelled: return "\(counted(cards.count, "card")) from QUESTION / ANSWER labels\(duplicateNote)"
        case .anki: return "\(counted(cards.count, "card")) from Anki\(duplicateNote)"
        case .table: return "\(counted(cards.count, "card")) from two columns\(duplicateNote)"
        case .blocks: return "\(counted(cards.count, "card")), one per block of text\(duplicateNote)"
        }
    }

    private var duplicateNote: String {
        duplicates > 0 ? " · \(duplicates) already in this deck" : ""
    }

    private var previewCard: some View {
        WarmCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("FIRST CARD, IN YOUR HAND")
                    .font(Theme.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.softInk(scheme))
                DrawingThumbnail(data: preview.question, height: 70)
                if let answer = preview.answer {
                    Rectangle().fill(Theme.softInk(scheme).opacity(0.15)).frame(height: 1)
                    DrawingThumbnail(data: answer, height: 200)
                }
                if !missing.isEmpty {
                    Text("Not in your alphabet yet, so left out: \(missing.map(String.init).joined(separator: " "))")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.medium(scheme))
                }
            }
        }
    }

    private var options: some View {
        AppSection(title: nil) {
            if canWrite {
                AppToggle(title: "Write them in my handwriting", isOn: $inMyHand)
            } else {
                Text("Capture your alphabet first and pasted cards can arrive already written in your hand.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.softInk(scheme))
            }
            AppToggle(title: "Skip questions already in this deck", isOn: $skipDuplicates)
        }
    }

    private var addButton: some View {
        Button {
            add()
        } label: {
            Text(cards.isEmpty ? "Add cards" : "Add \(counted(cards.count, "card"))")
                .font(Theme.label(17))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
        .disabled(cards.isEmpty)
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .background(Theme.page(scheme))
        .accessibilityIdentifier("paste.add")
    }

    /// Reads the chosen pictures and adds what they say to whatever is already here.
    ///
    /// Recognition runs off the main thread: a page of text takes long enough that doing it
    /// inline would freeze the screen mid-tap.
    private func readPhotos(_ picked: [PhotosPickerItem]) async {
        isReading = true
        readingProblem = nil
        defer { isReading = false; chosenPhotos = [] }

        var images: [UIImage] = []
        for item in picked {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            readingProblem = "Those could not be opened as pictures."
            return
        }

        let scanned = await Task.detached(priority: .userInitiated) {
            TextFromImages.studyText(from: images)
        }.value

        guard !scanned.isEmpty else {
            readingProblem = "No words could be read from \(counted(images.count, "screenshot"))."
            return
        }
        text = text.isEmpty ? scanned : text + "\n\n" + scanned
    }

    // MARK: - Actions

    private func add() {
        let now = Date()
        for (offset, pasted) in cards.enumerated() {
            let card = StoredCard(deck: deck, frontText: pasted.question, backText: pasted.answer)
            // Staggered so the queue introduces them in the order they were pasted.
            card.createdAt = now.addingTimeInterval(Double(offset) / 1000)
            if inMyHand, canWrite {
                card.frontDrawing = handwriting.compose(pasted.question, maxWidth: 680).drawing.dataRepresentation()
                if !pasted.answer.isEmpty {
                    card.backDrawing = handwriting.compose(pasted.answer, maxWidth: 680).drawing.dataRepresentation()
                }
            }
            context.insert(card)
        }
        try? context.save()
        dismiss()
    }
}
