import Foundation
@testable import Planner

// Shared deterministic Calendar Events test support: the fakes and
// conveniences every Calendar Events model suite drives through the same
// product-oriented seams the production adapters satisfy — the fake
// Google Calendar API adapter, the fake connectivity monitor, and the
// controllable cadence scheduling clock.

/// The deterministic Google Calendar events fake: it records every fetch and
/// resolves outcomes from a test-supplied handler, so Calendar Events model
/// behavior is asserted through the same product-oriented interface the
/// production adapter satisfies.
@MainActor
final class FakeGoogleCalendarEventsAdapter: GoogleCalendarEventsAdapting {
    nonisolated static let defaultCalendar = GoogleSourceCalendar(
        id: "primary@example.com",
        summary: "Primary",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    )

    var primarySourceCalendarOutcome: GoogleSourceCalendarOutcome = .success(
        defaultCalendar
    )
    var primarySourceCalendarHandler: (() async -> GoogleSourceCalendarOutcome)?
    var primarySourceCalendarFetchCallCount = 0
    var fetchCallCount = 0
    var fetchedSourceCalendars: [[GoogleSourceCalendar]] = []
    var fetchedRanges: [(start: Date, end: Date)] = []
    var fetchHandler: (Date, Date) async -> GoogleCalendarEventsOutcome = {
        _, _ in
        .success(calendar: defaultCalendar, events: [])
    }

    func fetchPrimarySourceCalendar() async -> GoogleSourceCalendarOutcome {
        primarySourceCalendarFetchCallCount += 1
        if let primarySourceCalendarHandler {
            return await primarySourceCalendarHandler()
        }
        return primarySourceCalendarOutcome
    }

    func fetchEvents(
        from sourceCalendars: [GoogleSourceCalendar],
        start: Date,
        end: Date
    ) async -> GoogleCalendarEventsOutcome {
        fetchCallCount += 1
        fetchedSourceCalendars.append(sourceCalendars)
        fetchedRanges.append((start, end))
        return await fetchHandler(start, end)
    }
}

/// The canonical identity a test event without an `iCalUID` takes when
/// fetched through the default test Source Calendar — the production
/// fallback form, spelled out so assertions pin it.
func canonicalID(
    _ eventID: String,
    source: GoogleSourceCalendar = FakeGoogleCalendarEventsAdapter
        .defaultCalendar
) -> String {
    "src:\(source.id):event:\(eventID)"
}

/// Test convenience: a success without event color metadata, so the many
/// tests that never exercise explicit Google event colors stay terse.
extension GoogleCalendarEventsOutcome {
    static func success(
        calendar: GoogleSourceCalendar,
        events: [GoogleCalendarEvent],
        eventColorBackgrounds: [String: String] = [:]
    ) -> GoogleCalendarEventsOutcome {
        .success(
            events: events.map {
                GoogleSourceCalendarEvent(
                    sourceCalendar: calendar,
                    event: $0
                )
            },
            eventColorBackgrounds: eventColorBackgrounds
        )
    }
}

@MainActor
final class FakeCalendarEventsCadenceScheduler:
    CalendarEventsCadenceScheduling
{
    private(set) var now: Date

    init(now: Date) {
        self.now = now
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }

    @MainActor
    final class Schedule: CalendarEventsCadenceSchedule {
        private(set) var isCancelled = false
        private var action: (@MainActor @Sendable () -> Void)?

        init(action: @escaping @MainActor @Sendable () -> Void) {
            self.action = action
        }

        func cancel() {
            isCancelled = true
            action = nil
        }

        func fire() {
            guard !isCancelled, let action else {
                return
            }
            self.action = nil
            action()
        }

        var isPending: Bool {
            !isCancelled && action != nil
        }
    }

    private(set) var scheduledDelays: [Duration] = []
    private(set) var schedules: [Schedule] = []

    func schedule(
        after delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> any CalendarEventsCadenceSchedule {
        scheduledDelays.append(delay)
        let schedule = Schedule(action: action)
        schedules.append(schedule)
        return schedule
    }

    var pendingCount: Int {
        schedules.count(where: \.isPending)
    }

    func fireNext() {
        schedules.first(where: \.isPending)?.fire()
    }
}

/// The deterministic Stored Calendar Events fake: an in-memory snapshot
/// with recorded writes and wipes, so Stored Calendar Events behavior is
/// asserted through the same product-oriented boundary the production
/// file adapter satisfies (ADR 0007).
final class FakeStoredCalendarEventsStore: StoredCalendarEventsStoring {
    var snapshot: StoredCalendarEventsSnapshot?
    private(set) var savedSnapshots: [StoredCalendarEventsSnapshot] = []
    private(set) var wipeCallCount = 0

    func loadSnapshot() -> StoredCalendarEventsSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: StoredCalendarEventsSnapshot) {
        savedSnapshots.append(snapshot)
        self.snapshot = snapshot
    }

    func wipeSnapshots() {
        wipeCallCount += 1
        snapshot = nil
    }
}

final class FakeEventsConnectivityMonitor:
    GoogleConnectionConnectivityMonitoring
{
    private var onConnectivityReturn: (@MainActor () -> Void)?
    var startCallCount = 0
    var stopCallCount = 0

    func start(onConnectivityReturn: @escaping @MainActor () -> Void) {
        startCallCount += 1
        self.onConnectivityReturn = onConnectivityReturn
    }

    func stop() {
        stopCallCount += 1
        onConnectivityReturn = nil
    }

    @MainActor
    func simulateConnectivityReturn() {
        onConnectivityReturn?()
    }
}
