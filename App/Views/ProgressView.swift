import SwiftUI
import SwiftData
import Charts
import FlashcardsCore

/// Everything you have done, across every deck: cards reviewed, time spent, and whether
/// you are keeping it up. `StatsView` answers "how is this deck doing?"; this answers
/// "how am I doing?".
struct OverallProgressView: View {
    let profile: StoredProfile

    @Environment(\.colorScheme) private var scheme
    @Environment(UsageTracker.self) private var usage
    @Environment(\.dismiss) private var dismiss

    // MARK: - Data

    private var liveCards: [StoredCard] {
        profile.decks.filter { $0.deletedAt == nil }
            .flatMap { $0.cards }
            .filter { $0.deletedAt == nil }
    }

    private var logs: [StoredReviewLog] {
        liveCards.flatMap(\.reviewLogs)
    }

    private var todayStart: Date { Calendar.current.startOfDay(for: Date()) }

    private var reviewsToday: Int {
        logs.filter { $0.reviewedAt >= todayStart }.count
    }

    /// Seconds spent actually looking at cards, as opposed to time with the app open.
    private var studySecondsAllTime: TimeInterval {
        logs.reduce(0) { $0 + $1.durationSeconds }
    }

    private var studySecondsToday: TimeInterval {
        logs.filter { $0.reviewedAt >= todayStart }.reduce(0) { $0 + $1.durationSeconds }
    }

    /// Days reviewed in an unbroken run ending today or yesterday. Yesterday still counts,
    /// so the streak doesn't read as broken first thing in the morning.
    private var streak: Int {
        let cal = Calendar.current
        let days = Set(logs.map { cal.startOfDay(for: $0.reviewedAt) })
        guard !days.isEmpty else { return 0 }

        var cursor = todayStart
        if !days.contains(cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while days.contains(cursor) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private struct DayPoint: Identifiable {
        let id = UUID()
        let day: Date
        let reviews: Int
        let minutes: Double
    }

    /// The last 14 days, including days with nothing, so gaps are visible.
    private var recentDays: [DayPoint] {
        let cal = Calendar.current
        return (0..<14).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let next = cal.date(byAdding: .day, value: 1, to: day) ?? day
            let dayLogs = logs.filter { $0.reviewedAt >= day && $0.reviewedAt < next }
            return DayPoint(day: day,
                            reviews: dayLogs.count,
                            minutes: usage.seconds(on: day) / 60)
        }
    }

    private var hasHistory: Bool { !logs.isEmpty || usage.totalSeconds > 0 }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                todayCard
                if hasHistory {
                    allTimeCard
                    reviewsChart
                    timeChart
                } else {
                    emptyState
                }
            }
            .padding(20)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.page(scheme))
        .safeAreaInset(edge: .top) {
            AppHeader(title: "Progress", onBack: { dismiss() })
                .background(Theme.page(scheme))
        }
        .navigationBarHidden(true)
        .onAppear { usage.commit() }
    }

    private var todayCard: some View {
        WarmCard(padding: 20) {
            VStack(spacing: 14) {
                HStack {
                    Text("Today")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.ink(scheme))
                    Spacer()
                    if streak > 0 {
                        Label("^[\(streak) day](inflect: true)", systemImage: "flame.fill")
                            .font(Theme.label(14))
                            .foregroundStyle(Theme.accent(scheme))
                    }
                }

                HStack(spacing: 10) {
                    StatChip(value: "\(reviewsToday)", label: "cards", tint: Theme.accent(scheme))
                    StatChip(value: humanDuration(usage.todaySeconds), label: "in the app", tint: Theme.easy(scheme))
                    StatChip(value: humanDuration(studySecondsToday), label: "studying", tint: Theme.medium(scheme))
                }
            }
        }
        .softGlow(Theme.glow(scheme), active: reviewsToday > 0, maxOpacity: 0.55)
    }

    private var allTimeCard: some View {
        WarmCard(padding: 20) {
            VStack(spacing: 14) {
                HStack {
                    Text("All time")
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.ink(scheme))
                    Spacer()
                }
                HStack(spacing: 10) {
                    StatChip(value: "\(logs.count)", label: "reviews", tint: Theme.accent(scheme))
                    StatChip(value: humanDuration(usage.totalSeconds), label: "in the app", tint: Theme.easy(scheme))
                    StatChip(value: "\(usage.activeDays.count)", label: "days used", tint: Theme.medium(scheme))
                }
                HStack(spacing: 10) {
                    StatChip(value: "\(liveCards.count)", label: "cards made", tint: nil)
                    StatChip(value: humanDuration(studySecondsAllTime), label: "studying", tint: nil)
                    StatChip(value: averageLabel, label: "per card", tint: nil)
                }
            }
        }
    }

    private var averageLabel: String {
        guard !logs.isEmpty else { return "—" }
        return humanDuration(studySecondsAllTime / Double(logs.count))
    }

    private var reviewsChart: some View {
        WarmCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cards reviewed, last 14 days")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.softInk(scheme))

                Chart(recentDays) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Cards", point.reviews)
                    )
                    .foregroundStyle(Theme.accent(scheme).gradient)
                    .cornerRadius(5)
                }
                .chartXScale(domain: chartDomain)
                .chartYAxis { AxisMarks(position: .trailing) }
                .frame(height: 170)
            }
        }
    }

    private var timeChart: some View {
        WarmCard(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Minutes in the app, last 14 days")
                    .font(Theme.label(15))
                    .foregroundStyle(Theme.softInk(scheme))

                Chart(recentDays) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(Theme.easy(scheme).gradient)
                    .cornerRadius(5)
                }
                .chartXScale(domain: chartDomain)
                .chartYAxis { AxisMarks(position: .trailing) }
                .frame(height: 170)
            }
        }
    }

    /// Pinned to the full window so a single day of data cannot rescale the axis to hours.
    private var chartDomain: ClosedRange<Date> {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -14, to: todayStart) ?? todayStart
        let end = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        return start...end
    }

    private var emptyState: some View {
        WarmCard(padding: 40) {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Theme.accent(scheme))
                Text("Nothing to show yet")
                    .font(Theme.display(21))
                    .foregroundStyle(Theme.ink(scheme))
                Text("Study a few cards and your progress will appear here.")
                    .font(Theme.body(15))
                    .foregroundStyle(Theme.softInk(scheme))
                    .multilineTextAlignment(.center)
            }
        }
    }
}
