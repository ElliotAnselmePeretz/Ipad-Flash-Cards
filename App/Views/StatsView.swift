import SwiftUI
import SwiftData
import Charts
import FlashcardsCore

/// Review history and a forecast of what's coming due.
struct StatsView: View {
    let deck: StoredDeck

    /// Cards that still count: soft-deleted ones are excluded everywhere.
    private var liveCards: [StoredCard] {
        deck.cards.filter { $0.deletedAt == nil }
    }

    private var logs: [StoredReviewLog] {
        // Deleting a card removes its history from the statistics too, so the review
        // count can never disagree with the card count.
        liveCards.flatMap(\.reviewLogs).sorted { $0.reviewedAt < $1.reviewedAt }
    }

    /// Reviews per day over the last 30 days.
    private var history: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let grouped = Dictionary(grouping: logs.filter { $0.reviewedAt >= cutoff }) {
            calendar.startOfDay(for: $0.reviewedAt)
        }
        return grouped.map { (date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }

    /// How many cards fall due on each of the next 30 days.
    private var forecast: [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        let due = liveCards.filter { $0.dueDate <= horizon }
        let grouped = Dictionary(grouping: due) { calendar.startOfDay(for: max($0.dueDate, Date())) }
        return grouped.map { (date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }

    private var thirtyDaysAgo: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private var thirtyDaysAhead: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 30, to: cal.startOfDay(for: Date())) ?? Date()
    }

    private var retention: Double? {
        let graded = logs.filter { $0.intervalBefore > 0 }
        guard !graded.isEmpty else { return nil }
        return Double(graded.filter { $0.grade != .again }.count) / Double(graded.count)
    }

    /// One summary line. The value carries its own identifier so tests can read it
    /// without depending on how SwiftUI flattens a LabeledContent's accessibility.
    private func statRow(_ title: String, value: String, id: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit().accessibilityIdentifier(id)
        } label: {
            Text(title)
        }
    }

    var body: some View {
        List {
            Section("Summary") {
                statRow("Cards", value: "\(liveCards.count)", id: "stat.cards")
                statRow("Reviews", value: "\(logs.count)", id: "stat.reviews")
                // Always shown, so the row doesn't appear and disappear between sessions.
                statRow("Retention",
                        value: retention.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                        id: "stat.retention")
                statRow("Mature cards",
                        value: "\(liveCards.filter { $0.intervalDays >= 21 }.count)",
                        id: "stat.mature")
            }

            Section("Reviews, last 30 days") {
                if history.isEmpty {
                    Text("No reviews yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Chart(history, id: \.date) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Reviews", day.count))
                            .foregroundStyle(.green)
                    }
                    // Without an explicit domain a single day of data rescales the axis to
                    // hours and stretches one bar across the whole chart.
                    .chartXScale(domain: thirtyDaysAgo...Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400))
                    .chartYAxis { AxisMarks(position: .trailing) }
                    .frame(height: 180)
                }
            }

            Section("Due, next 30 days") {
                if forecast.isEmpty {
                    Text("Nothing scheduled in the next 30 days.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Chart(forecast, id: \.date) { day in
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Cards", day.count))
                            .foregroundStyle(.blue)
                    }
                    .chartXScale(domain: Calendar.current.startOfDay(for: Date())...thirtyDaysAhead)
                    .chartYAxis { AxisMarks(position: .trailing) }
                    .frame(height: 180)
                }
            }
        }
        .navigationTitle("Statistics")
    }
}
