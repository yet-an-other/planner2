import Foundation
import Testing
@testable import Planner

/// Stored Calendar Events coverage through the observable Calendar Events
/// model seam with a fake event store — the same seam every gated Calendar
/// Events behavior uses — plus the fake store itself. Asserts only external
/// behavior: what the surface presents, what the store contains after
/// observable operations, and what survives process death.
@Suite("Stored Calendar Events")
@MainActor
struct StoredCalendarEventsTests {
    /// The deterministic environment: Wednesday 2026-07-15 at noon GMT.
    private static let now = Date(timeIntervalSince1970: 1_784_116_800)

    private static let accountID = "google-account-1"

    private static func makeEnvironment() -> CalendarEnvironment {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("GMT must be available for deterministic tests")
        }
        return CalendarEnvironment(
            now: now,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }

    private static func gmt(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    private func makeModel(
        store: FakeStoredCalendarEventsStore
    ) -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter,
        FakeEventsConnectivityMonitor
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let monitor = FakeEventsConnectivityMonitor()
        let model = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: adapter,
            connectivityMonitor: monitor,
            cadenceScheduler: FakeCalendarEventsCadenceScheduler(now: Self.now),
            eventStore: store
        )
        return (model, adapter, monitor)
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    @Test("Stored Calendar Events present immediately at process start")
    func launchPresentation() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)

        // One successful run writes the store through the model…
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9)),
                        end: .timed(Self.gmt(2026, 7, 15, 9, 15)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars([
            FakeGoogleCalendarEventsAdapter.defaultCalendar,
        ])
        #expect(await eventually { store.savedSnapshots.count == 1 })

        // …and a new process presents it before any fetch begins.
        let (relaunched, relaunchedAdapter, _) = makeModel(store: store)
        relaunchedAdapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        }
        relaunched.presentStoredCalendarEvents()

        let weekStart = Self.gmt(2026, 7, 13)
        let layout = relaunched.layout(forWeekStarting: weekStart)
        #expect(layout?.cells[2].rows.first?.title == "Standup")
        // Presented as always stale: no fetch has run in the new process,
        // so nothing has replaced the stored view yet.
        #expect(relaunchedAdapter.fetchCallCount == 0)
    }

    private static let primary = FakeGoogleCalendarEventsAdapter
        .defaultCalendar

    private static let family = GoogleSourceCalendar(
        id: "family",
        summary: "Family",
        backgroundColorHex: "#7CB342",
        isPrimary: false
    )

    private static func event(
        _ id: String,
        summary: String,
        startHour: Int = 9,
        day: Int = 15,
        month: Int = 7
    ) -> GoogleCalendarEvent {
        GoogleCalendarEvent(
            id: id,
            summary: summary,
            start: .timed(gmt(2026, month, day, startHour)),
            end: .timed(gmt(2026, month, day, startHour + 1)),
            isCancelled: false,
            isDeclinedByViewer: false
        )
    }

    /// Connects the account and its selection and awaits the first
    /// write-through of a successful initial Fetched Window fetch.
    @discardableResult
    private func connectAndAwaitInitialWrite(
        _ model: CalendarEventsModel,
        adapter: FakeGoogleCalendarEventsAdapter,
        store: FakeStoredCalendarEventsStore,
        selection: [GoogleSourceCalendar]? = nil
    ) async -> Bool {
        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars(selection ?? [Self.primary])
        return await eventually { store.savedSnapshots.count == 1 }
    }

    @Test("An empty store leaves the bare, usable Calendar Grid")
    func emptyStorePresentsBareGrid() {
        let store = FakeStoredCalendarEventsStore()
        let (model, _, _) = makeModel(store: store)

        model.presentStoredCalendarEvents()

        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
        #expect(model.status.message == nil)
    }

    @Test("Every successful slab fetch writes the whole in-memory model through")
    func slabSuccessWritesThrough() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { start, _ in
            if start == Self.gmt(2026, 4, 15) {
                return .success(
                    calendar: Self.primary,
                    events: [Self.event("july-event", summary: "July")]
                )
            }
            return .success(
                calendar: Self.primary,
                events: [
                    Self.event(
                        "november-event",
                        summary: "November",
                        day: 10,
                        month: 11
                    ),
                ]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )

        // Approaching within one month of the Fetched Window's forward edge
        // fetches the two-month expansion slab once.
        model.showVisibleRange(
            from: Self.gmt(2026, 9, 7),
            through: Self.gmt(2026, 9, 21)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await eventually { store.savedSnapshots.count == 2 })

        // The store mirrors the grown Fetched Window: the slab's events and
        // the initial window's events together.
        #expect(
            store.snapshot?.events.map(\.id)
                == [canonicalID("july-event"), canonicalID("november-event")]
        )
        #expect(store.snapshot?.accountID == Self.accountID)
    }

    @Test("A successful refresh atomically replaces the stored view")
    func refreshReplacementWritesThrough() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: Self.primary,
                    events: [
                        Self.event("kept", summary: "Before"),
                        Self.event("removed", summary: "Leaving", day: 16),
                    ]
                )
            }
            return .success(
                calendar: Self.primary,
                events: [Self.event("kept", summary: "After")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )

        model.refreshOnForeground()
        #expect(await eventually { store.savedSnapshots.count == 2 })

        // The edit lands and the deletion made elsewhere disappears — the
        // store holds exactly the refreshed in-memory model.
        #expect(store.snapshot?.events.map(\.id) == [canonicalID("kept")])
        #expect(store.snapshot?.events.first?.title == "After")

        // A new process therefore never resurrects the pre-refresh state.
        let (relaunched, _, _) = makeModel(store: store)
        relaunched.presentStoredCalendarEvents()
        let rows = relaunched.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
            .cells[2].rows ?? []
        #expect(rows.map(\.title) == ["After"])
    }

    @Test("A failed refresh retains the stored events and never writes")
    func failedRefreshRetainsStoredView() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return fetchNumber == 1
                ? .success(
                    calendar: Self.primary,
                    events: [Self.event("kept", summary: "Kept")]
                )
                : .unavailable(.failed)
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )

        model.refreshOnForeground()
        #expect(await eventually { model.status.message != nil })

        #expect(store.savedSnapshots.count == 1)
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Kept"
        )
        #expect(model.status.message == CalendarEventsCopy.refreshFailed)
    }

    @Test("An offline launch retains stored events with a warning and recovers on connectivity return")
    func offlineLaunchRetainsAndRetries() async {
        let store = FakeStoredCalendarEventsStore()
        let (first, firstAdapter, _) = makeModel(store: store)
        firstAdapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("stored", summary: "Stored")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                first,
                adapter: firstAdapter,
                store: store
            )
        )

        // A new process presents the stored events immediately, then the
        // offline initial fetch keeps them with an offline warning.
        let (model, adapter, monitor) = makeModel(store: store)
        var online = false
        adapter.fetchHandler = { _, _ in
            online
                ? .success(
                    calendar: Self.primary,
                    events: [Self.event("fresh", summary: "Fresh")]
                )
                : .unavailable(.offline)
        }
        model.presentStoredCalendarEvents()
        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars([Self.primary])
        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(await eventually { model.status.message != nil })

        #expect(model.status.message == CalendarEventsCopy.offline)
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Stored"
        )
        #expect(store.savedSnapshots.count == 1)

        // Connectivity return retries event-driven and the success
        // atomically replaces the stored view, on disk as in memory.
        online = true
        monitor.simulateConnectivityReturn()
        #expect(await eventually { store.savedSnapshots.count == 2 })
        #expect(store.snapshot?.events.map(\.id) == [canonicalID("fresh")])
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Fresh"
        )
    }

    @Test("Events that fell out of the Fetched Window disappear on the next write")
    func fetchedWindowFallout() async {
        let store = FakeStoredCalendarEventsStore()
        // A snapshot from months ago: the January event sits outside the
        // Fetched Window a new process fetches (Today ± 3 months).
        store.snapshot = StoredCalendarEventsSnapshot(
            accountID: Self.accountID,
            events: [
                CalendarEvent(
                    id: canonicalID("january-event"),
                    sourceCalendar: Self.primary,
                    title: "January",
                    colorHex: Self.primary.backgroundColorHex,
                    textTone: .light,
                    kind: .row(
                        date: Self.gmt(2026, 1, 12),
                        startsAt: Self.gmt(2026, 1, 12, 9),
                        startTimeText: "9:00 AM"
                    ),
                    detail: CalendarEventDetail(
                        title: "January",
                        colorHex: Self.primary.backgroundColorHex,
                        timingText: "Mon, Jan 12, 2026 · 9:00 – 10:00 AM"
                    )
                ),
            ]
        )
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("july-event", summary: "July")]
            )
        }
        model.presentStoredCalendarEvents()
        // The stored mirror presents as it was left…
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 1, 12))?
                .cells[0].rows.first?.title == "January"
        )

        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars([Self.primary])
        #expect(await eventually { store.savedSnapshots.count == 1 })

        // …and the first successful response's write-through drops what
        // fell out of the Fetched Window — no separate eviction policy.
        #expect(
            store.snapshot?.events.map(\.id) == [canonicalID("july-event")]
        )
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 1, 12)) == nil)
    }

    @Test("Events from deselected Source Calendars disappear on the next write")
    func deselectedSourceRemoval() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            // The initial aggregate covers both selected sources; the
            // selection-triggered replacement covers only Primary.
            let sources = fetchNumber == 1
                ? [Self.primary, Self.family]
                : [Self.primary]
            return .success(
                events: sources.map {
                    GoogleSourceCalendarEvent(
                        sourceCalendar: $0,
                        event: Self.event(
                            "event-\($0.id)",
                            summary: "From \($0.summary)"
                        )
                    )
                },
                eventColorBackgrounds: [:]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store,
                selection: [Self.primary, Self.family]
            )
        )
        #expect(
            Set(store.snapshot?.events.map(\.id) ?? [])
                == [
                    canonicalID("event-primary@example.com"),
                    canonicalID("event-family", source: Self.family),
                ]
        )
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )

        // Deselecting Family replaces the snapshot around the visible
        // dates; its write mirrors the new selection only.
        model.sourceCalendarPickerDidOpen()
        model.sourceCalendarPickerDidClose(
            selectedSourceCalendars: [Self.primary],
            selectionChanged: true
        )
        #expect(await eventually { store.savedSnapshots.count == 2 })
        #expect(
            store.snapshot?.events.map(\.id)
                == [canonicalID("event-primary@example.com")]
        )
    }

    @Test("The zero-source exception empties the store with the events")
    func zeroSourceEmptiesStore() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("kept", summary: "Kept")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )

        model.setSelectedSourceCalendars([])

        #expect(store.snapshot?.events == [])
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
    }

    @Test("Disconnect on This Device wipes the store")
    func disconnectWipesStore() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("kept", summary: "Kept")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )

        model.setCalendarDataAccountID(nil)

        #expect(store.wipeCallCount == 1)
        #expect(store.snapshot == nil)
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)

        // Reconnecting refetches fresh: no stored view returns.
        model.setCalendarDataAccountID(Self.accountID)
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
    }

    @Test("Stored Calendar Events never cross accounts")
    func perAccountIsolation() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("account-a-event", summary: "A's event")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                model,
                adapter: adapter,
                store: store
            )
        )
        model.setCalendarDataAccountID(nil)

        // A different account's session starts from an empty store and
        // never presents the previous account's events.
        model.setCalendarDataAccountID("google-account-2")
        #expect(store.snapshot == nil)
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
        model.setSelectedSourceCalendars([Self.primary])
        #expect(await eventually { store.savedSnapshots.count == 2 })
        #expect(store.snapshot?.accountID == "google-account-2")

        // Defensively, a foreign snapshot left on disk is wiped rather
        // than presented to another account.
        let foreign = FakeStoredCalendarEventsStore()
        foreign.snapshot = StoredCalendarEventsSnapshot(
            accountID: "google-account-1",
            events: [
                CalendarEvent(
                    id: canonicalID("account-a-event"),
                    sourceCalendar: Self.primary,
                    title: "A's event",
                    colorHex: Self.primary.backgroundColorHex,
                    textTone: .light,
                    kind: .row(
                        date: Self.gmt(2026, 7, 15),
                        startsAt: Self.gmt(2026, 7, 15, 9),
                        startTimeText: "9:00 AM"
                    ),
                    detail: CalendarEventDetail(
                        title: "A's event",
                        colorHex: Self.primary.backgroundColorHex,
                        timingText: "Wed, Jul 15, 2026 · 9:00 – 10:00 AM"
                    )
                ),
            ]
        )
        let (other, _, _) = makeModel(store: foreign)
        other.setCalendarDataAccountID("google-account-2")
        #expect(foreign.snapshot == nil)
        #expect(other.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
    }

    @Test("Without a disclosure-acknowledged account, no fetch ever writes the store")
    func olderDisclosureNeverWrites() async {
        let store = FakeStoredCalendarEventsStore()
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("kept", summary: "Kept")]
            )
        }

        // An installation that acknowledged only an older disclosure keeps
        // Calendar Events memory-only: the Calendar-data boundary never
        // publishes an account to it, so fetching works but nothing
        // persists.
        model.setSelectedSourceCalendars([Self.primary])
        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        #expect(store.savedSnapshots.isEmpty)
        #expect(store.snapshot == nil)
    }

    @Test("Stored presentation never suppresses fetching: coverage starts empty")
    func storedPresentationIsAlwaysStale() async {
        let store = FakeStoredCalendarEventsStore()
        let (first, firstAdapter, _) = makeModel(store: store)
        firstAdapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("stored", summary: "Stored")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                first,
                adapter: firstAdapter,
                store: store
            )
        )

        // The stored view presents at process start…
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("stored", summary: "Stored")]
            )
        }
        model.presentStoredCalendarEvents()
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
        )

        // …but the ordinary fetching rules schedule requests exactly as if
        // no events existed: stored events carry no freshness, so the
        // initial fetch runs even though identical events are visible.
        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars([Self.primary])
        #expect(await eventually { adapter.fetchCallCount == 1 })
    }

    @Test("A transitional nil selection publication never blanks stored events at launch")
    func transitionalNilPublicationRetainsStoredEvents() async {
        let store = FakeStoredCalendarEventsStore()
        let (first, firstAdapter, _) = makeModel(store: store)
        firstAdapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("stored", summary: "Stored")]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                first,
                adapter: firstAdapter,
                store: store
            )
        )

        // The production launch sequence: the composition root presents the
        // stored events; the restored account then reaches the Source
        // Calendars module first, whose reset publishes a transitional nil
        // selection before the account itself arrives.
        let (model, adapter, _) = makeModel(store: store)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [Self.event("fresh", summary: "Fresh")]
            )
        }
        model.presentStoredCalendarEvents()
        model.setSelectedSourceCalendars(nil)
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Stored"
        )

        // The account and its selection follow; the stored view stays on
        // the surface until the first success replaces it.
        model.setCalendarDataAccountID(Self.accountID)
        model.setSelectedSourceCalendars([Self.primary])
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Stored"
        )
        #expect(await eventually { store.savedSnapshots.count == 2 })
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].rows.first?.title == "Fresh"
        )
    }

    @Test("The hub publishes the disclosure-gated account to every Calendar-data module in order")
    func hubFansOutAccountPublication() {
        final class RecordingConsumer: CalendarDataAccountConsuming {
            var received: [String?] = []
            func setCalendarDataAccountID(_ accountID: String?) {
                received.append(accountID)
            }
        }
        let sources = RecordingConsumer()
        let events = RecordingConsumer()
        let hub = CalendarDataAccountConsumerHub(
            consumers: [sources, events]
        )

        hub.setCalendarDataAccountID("google-account-1")
        hub.setCalendarDataAccountID(nil)

        #expect(sources.received == ["google-account-1", nil])
        #expect(events.received == ["google-account-1", nil])
    }

    @Test("Stored events open their detail and day list offline")
    func storedEventsSupportPopoversOffline() async {
        let store = FakeStoredCalendarEventsStore()
        let (first, firstAdapter, _) = makeModel(store: store)
        firstAdapter.fetchHandler = { _, _ in
            .success(
                calendar: Self.primary,
                events: [
                    GoogleCalendarEvent(
                        id: "detailed",
                        summary: "Detailed",
                        start: .timed(Self.gmt(2026, 7, 15, 9)),
                        end: .timed(Self.gmt(2026, 7, 15, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        googleLink: "https://calendar.google.com/event?eid=x",
                        location: "Berlin",
                        notes: "Bring badge",
                        attendees: [
                            GoogleCalendarEventAttendee(
                                displayName: "Ada",
                                email: "ada@example.com",
                                responseStatus: "accepted"
                            ),
                        ]
                    ),
                ]
            )
        }
        #expect(
            await connectAndAwaitInitialWrite(
                first,
                adapter: firstAdapter,
                store: store
            )
        )

        let (model, adapter, _) = makeModel(store: store)
        model.presentStoredCalendarEvents()

        // The Event Detail Popover opens from the stored event with every
        // field intact, and the Day Events Popover lists it — no network.
        let id = canonicalID("detailed")
        model.selectEvent(withID: id)
        #expect(model.selectedEvent?.detail.location == "Berlin")
        #expect(model.selectedEvent?.detail.notes == "Bring badge")
        #expect(
            model.selectedEvent?.detail.googleLink
                == "https://calendar.google.com/event?eid=x"
        )
        #expect(model.selectedEvent?.detail.attendees.count == 1)
        #expect(model.selectedEvent?.sourceCalendar == Self.primary)

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents?.items.map(\.id) == [id])
        #expect(adapter.fetchCallCount == 0)
    }
}
