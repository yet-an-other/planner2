import Foundation
import Testing
@testable import Planner

/// Contract coverage for the production Stored Calendar Events adapter.
/// The platform attributes — Application Support location, backup
/// exclusion, and Data Protection class — are pinned directly here (the
/// same discipline as the popover detent policy), because they carry the
/// ADR 0007 boundary: Stored Calendar Events exist only on the device and
/// installation that fetched them, encrypted until first unlock.
@Suite("Stored Calendar Events Store")
struct StoredCalendarEventsStoreTests {
    private static let accountID = "google-account-1"

    private static func makeBaseDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: true
        )
        return base
    }

    private static func richSnapshot() -> StoredCalendarEventsSnapshot {
        let source = GoogleSourceCalendar(
            id: "primary@example.com",
            summary: "Primary",
            backgroundColorHex: "#039BE5",
            isPrimary: true
        )
        let bar = CalendarEvent(
            id: "ical:uid-conference@google.com:occurrence:date-2026-7-20",
            sourceCalendar: source,
            title: "Conference",
            colorHex: "#039BE5",
            textTone: .light,
            kind: .bar(
                startDate: Date(timeIntervalSince1970: 1_784_396_800),
                endDate: Date(timeIntervalSince1970: 1_784_569_600),
                startsAt: Date(timeIntervalSince1970: 1_784_396_800)
            ),
            detail: CalendarEventDetail(
                title: "Conference",
                colorHex: "#039BE5",
                timingText: "All day · Jul 20, 2026 – Jul 22, 2026",
                location: "Berlin",
                googleLink: "https://calendar.google.com/event?eid=abc",
                notes: "Bring badge",
                attendees: [
                    CalendarEventAttendee(label: "Ada", status: .accepted),
                    CalendarEventAttendee(
                        label: "grace@example.com",
                        status: .invited
                    ),
                ],
                hiddenAttendeeCount: 3
            )
        )
        let row = CalendarEvent(
            id: "src:primary@example.com:event:standup",
            sourceCalendar: source,
            title: "Standup",
            colorHex: "#7CB342",
            textTone: .dark,
            kind: .row(
                date: Date(timeIntervalSince1970: 1_784_396_800),
                startsAt: Date(timeIntervalSince1970: 1_784_432_400),
                startTimeText: "9:00 AM"
            ),
            detail: CalendarEventDetail(
                title: "Standup",
                colorHex: "#7CB342",
                timingText: "Mon, Jul 20, 2026 · 9:00 – 9:15 AM"
            )
        )
        return StoredCalendarEventsSnapshot(
            accountID: accountID,
            events: [bar, row]
        )
    }

    @Test("A saved snapshot round-trips through a fresh adapter instance")
    func snapshotRoundTrip() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let snapshot = Self.richSnapshot()
        FileStoredCalendarEventsStore(baseDirectory: base)
            .saveSnapshot(snapshot)

        let relaunched = FileStoredCalendarEventsStore(baseDirectory: base)
        #expect(relaunched.loadSnapshot() == snapshot)
    }

    @Test("The adapter pins its platform storage attributes")
    func platformAttributes() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        // The default location is the app's Application Support directory:
        // never Caches, so the system cannot purge Stored Calendar Events
        // under storage pressure.
        let defaultBase = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        #expect(
            FileStoredCalendarEventsStore()?.baseDirectory == defaultBase
        )

        let store = FileStoredCalendarEventsStore(baseDirectory: base)
        store.saveSnapshot(Self.richSnapshot())

        // Backup exclusion keeps events on the device and installation that
        // fetched them: they never travel through iCloud or device backups.
        let resourceValues = try store.directoryURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        #expect(resourceValues.isExcludedFromBackup == true)

        // Data Protection class Complete Until First User Authentication
        // encrypts Stored Calendar Events against a powered-off or
        // never-unlocked device without foreclosing background refresh.
        // The simulator filesystem does not report the attribute, so the
        // class the adapter applies to its directory and files is pinned
        // directly (the same discipline as the popover detent policy).
        #expect(
            FileStoredCalendarEventsStore.fileProtection
                == .completeUntilFirstUserAuthentication
        )
    }

    @Test("A corrupted snapshot fails safe to absence")
    func corruptedSnapshot() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let store = FileStoredCalendarEventsStore(baseDirectory: base)
        store.saveSnapshot(Self.richSnapshot())
        let files = try FileManager.default.contentsOfDirectory(
            at: store.directoryURL,
            includingPropertiesForKeys: nil
        )
        try Data("not-json".utf8).write(to: try #require(files.first))

        #expect(store.loadSnapshot() == nil)
    }

    @Test("Snapshots never cross accounts: a save replaces any other account's")
    func singleAccountInvariant() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let store = FileStoredCalendarEventsStore(baseDirectory: base)
        store.saveSnapshot(Self.richSnapshot())
        let replacement = StoredCalendarEventsSnapshot(
            accountID: "google-account-2",
            events: []
        )
        store.saveSnapshot(replacement)

        let files = try FileManager.default.contentsOfDirectory(
            at: store.directoryURL,
            includingPropertiesForKeys: nil
        )
        #expect(files.count == 1)
        #expect(store.loadSnapshot() == replacement)
    }

    @Test("Wiping removes every Stored Calendar Event from the device")
    func wipe() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let store = FileStoredCalendarEventsStore(baseDirectory: base)
        store.saveSnapshot(Self.richSnapshot())
        store.wipeSnapshots()

        #expect(store.loadSnapshot() == nil)
        #expect(
            !FileManager.default.fileExists(atPath: store.directoryURL.path)
        )
    }

    @Test("A blank account identifier writes nothing")
    func blankAccountID() throws {
        let base = try Self.makeBaseDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let store = FileStoredCalendarEventsStore(baseDirectory: base)
        store.saveSnapshot(
            StoredCalendarEventsSnapshot(accountID: "   ", events: [])
        )

        #expect(store.loadSnapshot() == nil)
        #expect(
            !FileManager.default.fileExists(atPath: store.directoryURL.path)
        )
    }
}
