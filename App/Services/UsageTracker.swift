import Foundation
import SwiftUI

/// Records how long the app is actually open, per day.
///
/// Review logs already say how long each card took, but that only counts seconds spent
/// looking at a card — not time browsing decks or writing new ones. This measures
/// foreground time, which is what "time spent on the app" usually means.
///
/// Kept in `UserDefaults` rather than SwiftData: it is a small dictionary of numbers, it
/// is written on every backgrounding, and losing it would cost nothing important.
@Observable
final class UsageTracker {
    private let key = "dailyUsageSeconds"
    private let defaults: UserDefaults
    private var foregroundedAt: Date?

    /// Day (start-of-day) to seconds spent in the app.
    private(set) var daily: [Date: TimeInterval] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Lifecycle

    func appDidEnterForeground(now: Date = Date()) {
        foregroundedAt = now
    }

    func appDidEnterBackground(now: Date = Date()) {
        commit(now: now)
        foregroundedAt = nil
    }

    /// Folds the time since the app came to the front into today's total. Called when the
    /// app leaves the foreground, and whenever a screen needs an up-to-date figure.
    func commit(now: Date = Date()) {
        guard let start = foregroundedAt else { return }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed > 0 else { return }

        // A session that crosses midnight is split, so each day gets its own share.
        var cursor = start
        while cursor < now {
            let day = Calendar.current.startOfDay(for: cursor)
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? now
            let sliceEnd = min(nextDay, now)
            daily[day, default: 0] += sliceEnd.timeIntervalSince(cursor)
            cursor = sliceEnd
        }

        foregroundedAt = now
        save()
    }

    // MARK: - Reading

    func seconds(on day: Date) -> TimeInterval {
        daily[Calendar.current.startOfDay(for: day)] ?? 0
    }

    var todaySeconds: TimeInterval { seconds(on: Date()) }

    var totalSeconds: TimeInterval { daily.values.reduce(0, +) }

    /// Days with any recorded time, most recent first.
    var activeDays: [Date] { daily.keys.sorted(by: >) }

    // MARK: - Persistence

    private func load() {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        for (key, value) in raw {
            if let date = formatter.date(from: key) {
                daily[Calendar.current.startOfDay(for: date)] = value
            }
        }
    }

    private func save() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        var raw: [String: Double] = [:]
        for (day, seconds) in daily {
            raw[formatter.string(from: day)] = seconds
        }
        defaults.set(raw, forKey: key)
    }
}

/// Formats a duration the way a person would say it: "12m", "1h 20m", "3h".
func humanDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total)s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
}
