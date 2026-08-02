import Foundation

/// One account's complete Stored Calendar Events: the device-local mirror
/// of the Fetched Window. The store holds at most one account's snapshot
/// at a time — Stored Calendar Events never cross accounts (ADR 0007).
///
/// A Stored Calendar Event is the Calendar Event itself: the full
/// normalized model exactly as the surface renders it — canonical
/// identity, winning Source Calendar identity, title, timing, Event
/// Color, location, notes (plain text, post-normalization), attendees,
/// and Google link. Raw Google API responses never cross into this
/// record (ADR 0007).
struct StoredCalendarEventsSnapshot: Equatable, Sendable, Codable {
    /// Google's stable opaque identifier of the account that fetched the
    /// events.
    let accountID: String
    let events: [CalendarEvent]
}

/// The persistence boundary for Stored Calendar Events (ADR 0007). The
/// observable Calendar Events model reads the snapshot at process start,
/// writes through every successful initial, slab, or Calendar Event
/// Refresh response, and wipes on Disconnect on This Device. Only the
/// normalized Calendar Event model crosses this seam — never raw Google
/// payloads, credentials, or profile fields.
protocol StoredCalendarEventsStoring {
    /// The stored snapshot, or `nil` when none exists or the stored state
    /// is unreadable. Corrupted state fails safe to absence; the next
    /// successful fetch writes a fresh snapshot.
    func loadSnapshot() -> StoredCalendarEventsSnapshot?

    /// Replaces the stored snapshot, removing any other account's.
    func saveSnapshot(_ snapshot: StoredCalendarEventsSnapshot)

    /// Removes every Stored Calendar Event from the device.
    func wipeSnapshots()
}

/// The production Stored Calendar Events store (ADR 0007).
///
/// One JSON file per Google account lives in
/// `Application Support/StoredCalendarEvents`: never Caches, so the system
/// cannot purge the store under storage pressure. The directory carries
/// the backup-exclusion resource so Stored Calendar Events exist only on
/// the device and installation that fetched them, and every file carries
/// Data Protection class Complete Until First User Authentication, so a
/// powered-off or never-unlocked device keeps them encrypted without
/// foreclosing future background refresh.
struct FileStoredCalendarEventsStore: StoredCalendarEventsStoring {
    /// The Data Protection class the store directory and every stored
    /// file carry (ADR 0007): Complete Until First User Authentication
    /// encrypts Stored Calendar Events against a powered-off or
    /// never-unlocked device without foreclosing future background
    /// refresh. Pinned directly by the adapter contract test.
    static let fileProtection: FileProtectionType =
        .completeUntilFirstUserAuthentication

    /// The directory the store resolves its account files under.
    let baseDirectory: URL

    private let fileManager: FileManager

    /// Builds the store rooted at an explicit base directory
    /// (deterministic tests supply a temporary one).
    init(
        fileManager: FileManager = .default,
        baseDirectory: URL
    ) {
        self.fileManager = fileManager
        self.baseDirectory = baseDirectory
    }

    /// Builds the production store rooted at the app's Application
    /// Support directory. `nil` when that directory cannot be resolved:
    /// failing safe to no store keeps Calendar Events memory-only rather
    /// than silently downgrading to a purgeable or backed-up location
    /// (ADR 0007).
    init?(fileManager: FileManager = .default) {
        guard
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }
        self.init(
            fileManager: fileManager,
            baseDirectory: applicationSupport
        )
    }

    /// The store's own directory beneath the base: one JSON file per
    /// Google account, named from the opaque account identifier.
    var directoryURL: URL {
        baseDirectory.appendingPathComponent(
            "StoredCalendarEvents",
            isDirectory: true
        )
    }

    func loadSnapshot() -> StoredCalendarEventsSnapshot? {
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ).filter({ $0.pathExtension == "json" }),
            files.count == 1,
            let file = files.first,
            let data = try? Data(contentsOf: file),
            let snapshot = try? JSONDecoder().decode(
                StoredCalendarEventsSnapshot.self,
                from: data
            ),
            Self.isValidIdentifier(snapshot.accountID)
        else {
            return nil
        }
        return snapshot
    }

    func saveSnapshot(_ snapshot: StoredCalendarEventsSnapshot) {
        guard Self.isValidIdentifier(snapshot.accountID) else {
            return
        }
        do {
            try prepareDirectory()
            // Stored Calendar Events never cross accounts: the store holds
            // one account at a time, so a save removes any other account's
            // file before writing.
            let stale = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            for file in stale where file != fileURL(for: snapshot.accountID) {
                try? fileManager.removeItem(at: file)
            }
            let data = try JSONEncoder().encode(snapshot)
            let file = fileURL(for: snapshot.accountID)
            do {
                try data.write(to: file, options: .atomic)
                try fileManager.setAttributes(
                    [.protectionKey: Self.fileProtection],
                    ofItemAtPath: file.path
                )
            } catch {
                // A snapshot without its Data Protection class is worse
                // than none: remove the partial write and leave the prior
                // snapshot's absence for the next write-through.
                try? fileManager.removeItem(at: file)
                throw error
            }
        } catch {
            // A failed write leaves the prior snapshot in place; the next
            // successful response writes through again. Raw errors never
            // surface or log account data.
        }
    }

    func wipeSnapshots() {
        try? fileManager.removeItem(at: directoryURL)
    }

    /// Creates the store directory with its Data Protection class and
    /// backup exclusion — the two platform attributes ADR 0007 pins.
    private func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: Self.fileProtection]
        )
        var excluded = directoryURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excluded.setResourceValues(values)
    }

    /// The one file holding one account's snapshot. The opaque account
    /// identifier is base64url-encoded so any Google identifier maps to a
    /// safe single path component without persisting it readably.
    private func fileURL(for accountID: String) -> URL {
        let encoded = Data(accountID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return directoryURL.appendingPathComponent(
            "\(encoded).json",
            isDirectory: false
        )
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
