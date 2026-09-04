import Foundation
import SwiftData
import FlashcardsCore

/// An end-to-end check of backup and restore against the real SwiftData store.
///
/// The unit tests prove the archive format round-trips. They cannot prove that the app
/// reads and writes the actual database correctly, which is where a backup would really
/// fail. This runs the whole path — build data, export, restore, compare — and is invoked
/// with a launch argument so it can be run on device or simulator without a test target.
enum BackupSelfTest {

    static func runIfRequested(context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-selftest-backup") else { return }
        run(context: context)
    }

    private nonisolated(unsafe) static var lines: [String] = []

    private static func log(_ pass: Bool, _ message: String) {
        let line = "\(pass ? "PASS" : "FAIL"): \(message)"
        lines.append(line)
        print("SELFTEST \(line)")
    }

    /// stdout is not captured on device, so results are also written to a file the host
    /// can read out of the app container.
    private static func writeResults() {
        let failures = lines.filter { $0.hasPrefix("FAIL") }.count
        let summary = ["RESULT: \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")",
                       "checks: \(lines.count)"] + lines
        let text = summary.joined(separator: "\n")
        let url = URL.documentsDirectory.appendingPathComponent("selftest.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    static func run(context: ModelContext) {
        lines = []
        print("SELFTEST BEGIN")

        // 1. Build a profile with ink, scheduling state and review history.
        let profile = StoredProfile(name: "SelfTest")
        context.insert(profile)

        let deck = StoredDeck(name: "SelfTest Deck", profile: profile)
        deck.newCardsPerDay = 17
        context.insert(deck)

        let frontInk = Data((0..<1024).map { UInt8($0 % 256) })
        let backInk = Data((0..<777).map { UInt8(($0 * 7) % 256) })

        let card = StoredCard(deck: deck, frontText: "imported question", backText: "")
        card.frontDrawing = frontInk
        card.backDrawing = backInk
        var scheduling = SchedulingState.new()
        scheduling.phase = .review
        scheduling.intervalDays = 9.5
        scheduling.repetitions = 3
        scheduling.lapses = 1
        scheduling.memory = MemoryState(stability: 9.5, difficulty: 5.5)
        scheduling.isLeech = true
        scheduling.isSuspended = true
        card.scheduling = scheduling
        context.insert(card)

        let logEntry = StoredReviewLog(
            card: card, reviewedAt: Date(timeIntervalSince1970: 1_700_000_000),
            grade: .hard, intervalBefore: 6, intervalAfter: 9.5,
            easeAfter: 2.4, durationSeconds: 4.5, attemptDrawing: nil
        )
        context.insert(logEntry)
        try? context.save()

        let service = BackupService(context: context)

        // 2. Export.
        guard let data = try? service.exportData(for: profile) else {
            log(false, "export threw")
            writeResults()
            return
        }
        log(data.count > 1000, "exported \(data.count) bytes")

        // 3. Restore into a *different* profile, which is the real-world case: a new
        //    device, or a library that has been lost.
        let target = StoredProfile(name: "SelfTest Restored")
        context.insert(target)
        try? context.save()

        guard let summary = try? service.restore(data, into: target) else {
            log(false, "restore threw")
            writeResults()
            return
        }

        log(summary.decksAdded == 1, "decks restored: \(summary.decksAdded)")
        log(summary.cardsAdded == 1, "cards restored: \(summary.cardsAdded)")
        log(summary.reviewsAdded == 1, "reviews restored: \(summary.reviewsAdded)")

        // 4. Compare what came back against what went in.
        guard let restoredDeck = target.decks.first(where: { $0.deletedAt == nil }),
              let restoredCard = restoredDeck.cards.first else {
            log(false, "restored deck or card missing")
            writeResults()
            return
        }

        log(restoredDeck.name == "SelfTest Deck", "deck name: \(restoredDeck.name)")
        log(restoredDeck.newCardsPerDay == 17, "deck settings: \(restoredDeck.newCardsPerDay)")
        log(restoredCard.frontText == "imported question", "front text preserved")
        log(restoredCard.frontDrawing == frontInk,
            "front handwriting byte-identical (\(restoredCard.frontDrawing?.count ?? -1) bytes)")
        log(restoredCard.backDrawing == backInk,
            "back handwriting byte-identical (\(restoredCard.backDrawing?.count ?? -1) bytes)")

        let s = restoredCard.scheduling
        log(s.phase == .review, "phase preserved: \(s.phase)")
        log(s.intervalDays == 9.5, "interval preserved: \(s.intervalDays)")
        log(s.repetitions == 3 && s.lapses == 1, "counts preserved")
        log(s.memory?.stability == 9.5 && s.memory?.difficulty == 5.5, "FSRS memory preserved")
        log(s.isLeech && s.isSuspended, "leech and paused state preserved")
        log(restoredCard.reviewLogs.count == 1, "review history preserved")
        log(restoredCard.reviewLogs.first?.grade == .hard, "review grade preserved")

        // 5. Corrupt input must be refused, not silently half-applied.
        let before = target.decks.count
        let junk = Data("not a backup".utf8)
        do {
            _ = try service.restore(junk, into: target)
            log(false, "garbage was accepted")
        } catch {
            log(target.decks.count == before, "garbage refused without changing anything")
        }

        writeResults()
        print("SELFTEST END")
    }
}
