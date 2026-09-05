import Foundation
import SwiftData
import FlashcardsCore

/// Keeps recent backups inside the app's own storage, without anyone having to remember.
///
/// A manual export is only as good as the habit behind it, and iCloud is not always
/// available. These files live in the app's Documents folder, survive app updates, can be
/// pulled off the device over a cable, and are visible in the Files app when the app
/// declares itself as a document provider.
enum AutoBackup {

    static let folderName = "Backups"
    /// Enough history to recover from a mistake noticed a few days late, without letting
    /// old copies of a large library accumulate forever.
    static let keepCount = 7
    private static let minimumInterval: TimeInterval = 20 * 3600

    static var folderURL: URL {
        URL.documentsDirectory.appendingPathComponent(folderName, isDirectory: true)
    }

    /// Backups on disk, newest first.
    static func existing() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return files
            .filter { $0.pathExtension == "inkrecall" }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    static func lastBackupDate() -> Date? {
        guard let newest = existing().first else { return nil }
        return try? newest.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Writes a backup unless one was written recently. Returns the file if it wrote one.
    @discardableResult
    static func runIfDue(profile: StoredProfile, context: ModelContext, now: Date = Date()) -> URL? {
        if let last = lastBackupDate(), now.timeIntervalSince(last) < minimumInterval {
            return nil
        }
        return write(profile: profile, context: context, now: now)
    }

    @discardableResult
    static func write(profile: StoredProfile, context: ModelContext, now: Date = Date()) -> URL? {
        let service = BackupService(context: context)
        guard let data = try? service.exportData(for: profile), data.count > 2 else { return nil }

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let name = ArchiveCoder().suggestedFilename(now: now)
            let url = folderURL.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            prune()
            return url
        } catch {
            return nil
        }
    }

    /// Deletes all but the most recent `keepCount` backups.
    static func prune() {
        let files = existing()
        guard files.count > keepCount else { return }
        for url in files.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
