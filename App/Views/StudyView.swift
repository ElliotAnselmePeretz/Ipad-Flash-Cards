import SwiftUI
import SwiftData
import FlashcardsCore

/// Studying is now purely recall: look at the question, decide, reveal, and say how it
/// went. There is no writing here — writing happens when you make the card. Removing the
/// answer canvas makes a review a few seconds instead of a minute.
struct StudyView: View {
    let deck: StoredDeck

    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var session: StudySession?
    @State private var isEditingCards = false
    @State private var flipped = false
    @State private var leechNotice: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.page(scheme).ignoresSafeArea()

            Group {
                if let session {
                    if session.stage == .finished {
                        if deck.cards.filter({ $0.deletedAt == nil }).isEmpty {
                            emptyDeckView
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                        } else {
                            finishedView(session)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    } else if let card = session.currentCard {
                        studying(session: session, card: card)
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .overlay(alignment: .top) {
            if let leechNotice {
                // A card leaving the rotation is worth saying out loud, not doing silently.
                Label(leechNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.body(15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.smallCorner, style: .continuous)
                            .fill(Theme.surface(scheme))
                            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    )
                    .foregroundStyle(Theme.hard(scheme))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .top) {
            AppHeader(title: deck.name,
                      subtitle: session.map { "\($0.counts.total) waiting" },
                      onBack: { dismiss() }) {
                HeaderButton(symbol: "arrow.uturn.backward", label: "Undo",
                             isEnabled: session?.canUndo ?? false) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        flipped = true
                        session?.undoLastGrade()
                    }
                }
                NavigationLink { RapidCaptureView(deck: deck) } label: {
                    HeaderGlyph(symbol: "pencil.and.scribble", label: "Write cards",
                                tint: Theme.accent(scheme))
                }
                HeaderButton(symbol: "square.stack", label: "All cards") {
                    isEditingCards = true
                }
                NavigationLink { StatsView(deck: deck) } label: {
                    HeaderGlyph(symbol: "chart.bar", label: "Statistics")
                }
            }
            .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $isEditingCards, onDismiss: { session?.rebuild() }) {
            NavigationStack { CardListView(deck: deck) }
        }
        .task {
            if session == nil {
                session = StudySession(deck: deck, context: context, settings: .default)
            }
        }
    }

    private func counts(_ session: StudySession) -> some View {
        HStack(spacing: 14) {
            CountPill(value: session.counts.new, color: Theme.accent(scheme), label: "new")
            CountPill(value: session.counts.learning, color: Theme.medium(scheme), label: "learning")
            CountPill(value: session.counts.review, color: Theme.easy(scheme), label: "due")
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: session.counts.total)
    }

    // MARK: - The card

    private func studying(session: StudySession, card: StoredCard) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 8)

            cardFace(session: session, card: card)
                .frame(maxWidth: 720)
                .padding(.horizontal, 24)
                // A real flip: the card turns over to show its other side.
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .animation(.spring(response: 0.5, dampingFraction: 0.78), value: flipped)
                // The tap layer sits outside the 3D transform on purpose: hit-testing
                // through a rotation3DEffect is unreliable, and putting it inside meant
                // the gesture was swallowed by the animation it was supposed to start.
                .onFingertipTap {
                    if session.stage == .question { reveal(session) }
                }
                .accessibilityAddTraits(session.stage == .question ? .isButton : [])
                .accessibilityHint(session.stage == .question ? "Tap to show the answer" : "")

            Spacer(minLength: 8)

            if session.stage == .question {
                Button {
                    reveal(session)
                } label: {
                    Text("Show answer")
                        .font(Theme.label(18))
                        .frame(maxWidth: 420)
                        .padding(.vertical, 16)
                }
                .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                grading(session: session, card: card)
                    .padding(.bottom, 26)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .id(card.id)
    }

    private func cardFace(session: StudySession, card: StoredCard) -> some View {
        WarmCard(padding: 30) {
            VStack(spacing: 16) {
                Text(session.stage == .question ? "QUESTION" : "ANSWER")
                    .font(Theme.label(11))
                    .tracking(1.4)
                    .foregroundStyle(Theme.softInk(scheme))

                if session.stage == .question {
                    Text("Tap the card to show the answer")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.softInk(scheme).opacity(0.7))
                }

                side(session.stage == .question ? .front : .back, of: card)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
            // Counter-rotate the contents so text isn't mirrored mid-flip.
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
    }

    @ViewBuilder
    private func side(_ which: CardFace, of card: StoredCard) -> some View {
        let text = which == .front ? card.frontText : card.backText
        let ink = which == .front ? card.frontDrawing : card.backDrawing

        VStack(spacing: 14) {
            // Typed text only ever comes from an import; handwritten cards have none.
            if !text.isEmpty {
                Text(text)
                    .font(Theme.title(30))
                    .foregroundStyle(Theme.ink(scheme))
                    .multilineTextAlignment(.center)
            }
            if ink != nil {
                DrawingThumbnail(data: ink, height: 240)
            }
            if text.isEmpty && ink == nil {
                Text("This side is empty")
                    .font(Theme.body())
                    .foregroundStyle(Theme.softInk(scheme))
            }
        }
    }

    private enum CardFace { case front, back }

    // MARK: - Grading

    private func grading(session: StudySession, card: StoredCard) -> some View {
        let scheduler = FSRSCardScheduler(settings: .default)
        return HStack(spacing: 12) {
            ForEach(Answer.allCases) { answer in
                let preview = scheduler.review(card.scheduling, grade: answer.grade, now: Date()).state
                Button {
                    grade(session, answer)
                } label: {
                    VStack(spacing: 4) {
                        Text(answer.title).font(Theme.label(17))
                        Text(intervalLabel(from: preview.dueDate))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                }
                .buttonStyle(SpringyButtonStyle(tint: answer.color(scheme)))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(answer.title)
                .accessibilityValue(intervalLabel(from: preview.dueDate))
                .accessibilityIdentifier("grade.\(answer.rawValue)")
            }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 24)
    }

    /// The three answers the learner sees, and how they map onto the scheduler's grades.
    private enum Answer: String, CaseIterable, Identifiable {
        case hard, medium, easy

        var id: String { rawValue }

        var title: String {
            switch self {
            case .hard: "Hard"
            case .medium: "Medium"
            case .easy: "Easy"
            }
        }

        /// `Hard` maps to the scheduler's failure grade. SM-2 needs a "bring this back
        /// soon" signal, and with only three buttons this is the one that means it.
        var grade: ReviewGrade {
            switch self {
            case .hard: .again
            case .medium: .good
            case .easy: .easy
            }
        }

        func color(_ scheme: ColorScheme) -> Color {
            switch self {
            case .hard: Theme.hard(scheme)
            case .medium: Theme.medium(scheme)
            case .easy: Theme.easy(scheme)
            }
        }
    }

    // MARK: - Actions

    private func reveal(_ session: StudySession) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            flipped.toggle()
            session.revealAnswer()
        }
    }

    private func grade(_ session: StudySession, _ answer: Answer) {
        let leechesBefore = session.leechCount
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            flipped = false
            session.grade(answer.grade)
        }
        if session.leechCount > leechesBefore {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                leechNotice = "You keep forgetting that one, so it is paused. Rewrite it under Cards."
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                withAnimation { leechNotice = nil }
            }
        }
    }

    private func finishedView(_ session: StudySession) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 66))
                .foregroundStyle(Theme.easy(scheme))
                .symbolEffect(.bounce, value: session.completedCount)

            Text("All caught up")
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink(scheme))

            Text(session.completedCount == 0
                 ? "Nothing is due in this deck right now."
                 : "^[\(session.completedCount) card](inflect: true) reviewed.")
                .font(Theme.body())
                .foregroundStyle(Theme.softInk(scheme))

            HStack(spacing: 12) {
                if session.canUndo {
                    Button("Undo last answer") { session.undoLastGrade() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("study.undoFinished")
                }
                Button("Check again") { withAnimation { session.rebuild() } }
                    .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 6)

            NavigationLink {
                RapidCaptureView(deck: deck)
            } label: {
                Label("Write more cards", systemImage: "pencil.and.scribble")
                    .font(Theme.label(17))
                    .frame(minWidth: 240)
                    .padding(.vertical, 14)
            }
            .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
            .padding(.top, 10)
        }
        .padding(40)
    }

    /// Shown when a deck has no cards at all. Previously this fell through to
    /// "All caught up", which told you nothing was due in a deck that was simply empty.
    private var emptyDeckView: some View {
        VStack(spacing: 18) {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(Theme.accent(scheme))
                .softGlow(Theme.glow(scheme), maxOpacity: 0.6)

            Text("This deck is empty")
                .font(Theme.display(28))
                .foregroundStyle(Theme.ink(scheme))

            Text("Write your first card with the Pencil.")
                .font(Theme.body())
                .foregroundStyle(Theme.softInk(scheme))

            NavigationLink {
                RapidCaptureView(deck: deck)
            } label: {
                Label("Write cards", systemImage: "pencil.and.scribble")
                    .font(Theme.label(18))
                    .frame(minWidth: 260)
                    .padding(.vertical, 16)
            }
            .buttonStyle(SpringyButtonStyle(tint: Theme.accent(scheme)))
            .padding(.top, 8)
            .accessibilityIdentifier("study.writeEmpty")

            Button("Import from a file") { isEditingCards = true }
                .buttonStyle(QuietButtonStyle())
        }
        .padding(40)
    }

    private func intervalLabel(from due: Date) -> String {
        let seconds = max(0, due.timeIntervalSinceNow)
        if seconds < 3_600 { return "\(max(1, Int((seconds / 60).rounded())))m" }
        if seconds < 86_400 { return "\(max(1, Int((seconds / 3_600).rounded())))h" }
        let days = seconds / 86_400
        if days < 30 { return "\(Int(days.rounded()))d" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }
}
