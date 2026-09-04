import SwiftUI
import SwiftData
import FlashcardsCore

/// The study screen: question on top, a Pencil canvas to write your answer, then the
/// real answer plus the four Anki grade buttons.
struct StudyView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @State private var session: StudySession?
    @State private var isEditingCards = false

    var body: some View {
        Group {
            if let session {
                if session.stage == .finished {
                    finishedView(session)
                } else if let card = session.currentCard {
                    studyingView(session: session, card: card)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(deck.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Cards", systemImage: "square.and.pencil") { isEditingCards = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { StatsView(deck: deck) } label: {
                    Label("Statistics", systemImage: "chart.bar")
                }
            }
            if let session, session.stage != .finished {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 14) {
                        CountPill(value: session.counts.new, color: .blue, label: "new")
                        CountPill(value: session.counts.learning, color: .orange, label: "learning")
                        CountPill(value: session.counts.review, color: .green, label: "due")
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingCards, onDismiss: { session?.rebuild() }) {
            NavigationStack { CardListView(deck: deck) }
        }
        .task {
            if session == nil {
                session = StudySession(deck: deck, context: context, config: .default)
            }
        }
    }

    // MARK: - Studying

    private func studyingView(session: StudySession, card: StoredCard) -> some View {
        VStack(spacing: 0) {
            questionPane(card)
                .frame(maxHeight: .infinity)

            Divider()

            if session.stage == .question {
                answerCanvas(session: session)
                    .frame(maxHeight: .infinity)
                Button {
                    withAnimation(.snappy) { session.revealAnswer() }
                } label: {
                    Text("Show answer").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            } else {
                answerComparison(session: session, card: card)
                    .frame(maxHeight: .infinity)
                gradeButtons(session: session, card: card)
                    .padding()
            }
        }
        // A fresh canvas per card, otherwise ink bleeds between cards.
        .id(card.id)
    }

    private func questionPane(_ card: StoredCard) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                if !card.frontText.isEmpty {
                    Text(card.frontText)
                        .font(.system(.largeTitle, design: .serif))
                        .multilineTextAlignment(.center)
                }
                if card.frontDrawing != nil {
                    DrawingThumbnail(data: card.frontDrawing, height: 200)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
    }

    private func answerCanvas(session: StudySession) -> some View {
        ZStack(alignment: .topLeading) {
            RuledPaper()
            DrawingCanvas(
                data: Binding(
                    get: { session.attemptDrawing },
                    set: { session.attemptDrawing = $0 }
                ),
                showsToolPicker: true
            )
            Text("Write your answer")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(12)
                .allowsHitTesting(false)
                .opacity(session.attemptDrawing == nil ? 1 : 0)
        }
    }

    private func answerComparison(session: StudySession, card: StoredCard) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("YOUR ANSWER").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                DrawingThumbnail(data: session.attemptDrawing, height: 180)
                    .frame(maxWidth: .infinity)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("CORRECT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(spacing: 10) {
                        if !card.backText.isEmpty {
                            Text(card.backText)
                                .font(.system(.title2, design: .serif))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if card.backDrawing != nil {
                            DrawingThumbnail(data: card.backDrawing, height: 180)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func gradeButtons(session: StudySession, card: StoredCard) -> some View {
        let scheduler = SM2Scheduler(config: .default)
        return HStack(spacing: 10) {
            ForEach(ReviewGrade.allCases, id: \.self) { grade in
                let preview = scheduler.review(card.scheduling, grade: grade, now: Date())
                Button {
                    withAnimation(.snappy) { session.grade(grade) }
                } label: {
                    VStack(spacing: 3) {
                        Text(title(for: grade)).font(.body.weight(.semibold))
                        // Showing the next interval is what makes the spacing legible.
                        Text(intervalLabel(from: preview.dueDate))
                            .font(.caption2.monospacedDigit())
                            .opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(tint(for: grade))
                .keyboardShortcut(KeyEquivalent(Character("\(grade.rawValue + 1)")), modifiers: [])
            }
        }
    }

    private func finishedView(_ session: StudySession) -> some View {
        ContentUnavailableView {
            Label("All caught up", systemImage: "checkmark.circle")
        } description: {
            Text(session.completedCount == 0
                 ? "Nothing is due in this deck right now."
                 : "^[\(session.completedCount) card](inflect: true) reviewed.")
        } actions: {
            Button("Check again") { session.rebuild() }
        }
    }

    // MARK: - Formatting

    private func title(for grade: ReviewGrade) -> String {
        switch grade {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }

    private func tint(for grade: ReviewGrade) -> Color {
        switch grade {
        case .again: .red
        case .hard: .orange
        case .good: .green
        case .easy: .blue
        }
    }

    private func intervalLabel(from due: Date) -> String {
        let seconds = max(0, due.timeIntervalSinceNow)
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60)))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        let days = seconds / 86_400
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
}

/// Faint ruled lines, so handwriting has something to sit on.
struct RuledPaper: View {
    var spacing: CGFloat = 44

    var body: some View {
        Canvas { context, size in
            var y = spacing
            while y < size.height {
                let line = Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: size.width, y: y)) }
                context.stroke(line, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
