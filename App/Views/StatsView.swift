import SwiftUI
import SwiftData
import Charts
import FlashcardsCore

/// Review history and a forecast of what's coming due.
struct StatsView: View {
    let deck: StoredDeck

    private var logs: [StoredReviewLog] {
        deck.cards.flatMap(\.reviewLogs).sorted { $0.reviewedAt < $1.reviewedAt }
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
        let due = deck.cards.filter { $0.deletedAt == nil && $0.dueDate <= horizon }
        let grouped = Dictionary(grouping: due) { calendar.startOfDay(for: max($0.dueDate, Date())) }
        return grouped.map { (date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }

    private var retention: Double? {
        let graded = logs.filter { $0.intervalBefore > 0 }
        guard !graded.isEmpty else { return nil }
        return Double(graded.filter { $0.grade != .again }.count) / Double(graded.count)
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Cards", value: "\(deck.cards.filter { $0.deletedAt == nil }.count)")
                LabeledContent("Reviews", value: "\(logs.count)")
                if let retention {
                    LabeledContent("Retention", value: retention.formatted(.percent.precision(.fractionLength(0))))
                }
                let mature = deck.cards.filter { $0.intervalDays >= 21 && $0.deletedAt == nil }.count
                LabeledContent("Mature cards", value: "\(mature)")
            }

            Section("Reviews, last 30 days") {
                Chart(history, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Reviews", day.count))
                        .foregroundStyle(.green)
                }
                .frame(height: 180)
            }

            Section("Due, next 30 days") {
                Chart(forecast, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Cards", day.count))
                        .foregroundStyle(.blue)
                }
                .frame(height: 180)
            }
        }
        .navigationTitle("Statistics")
    }
}
