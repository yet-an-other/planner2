import Foundation
import Testing
@testable import Planner

/// Coverage of the Calendar Data coordinator's wiring: the release
/// gate, the disclosure-gated Stored Calendar Events presentation, the
/// Sources-first account publication, and forbidden/not-found recovery —
/// each proven end-to-end through the real modules against faked
/// boundaries.
@Suite("Calendar Data Coordinator")
@MainActor
struct CalendarDataCoordinatorTests {
    private static let primary = GoogleSourceCalendar(
        id: "primary@example.com",
        summary: "Primary",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    )

    private static func makeEnvironment() -> CalendarEnvironment {
        CalendarEnvironment(
            now: gmt(2026, 7, 15, 12),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
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

    private static let configured = GoogleAccountConnectionConfiguration
        .configured(
            GoogleAccountConnectionConfiguration.Configured(
                clientID: "test-client-id",
                reversedClientID: "com.googleusercontent.apps.test",
                privacyPolicyURL: URL(string: "https://example.com/privacy")!
            )
        )

    @MainActor
    private static func makeCoordinator(
        api: FakeCalendarDataAPI = FakeCalendarDataAPI(),
        eventStore: FakeStoredCalendarEventsStore? = nil,
        disclosureStore: FakeGoogleConnectionDisclosureStore =
            FakeGoogleConnectionDisclosureStore(),
        signInAdapter: FakeGoogleSignInAdapter = FakeGoogleSignInAdapter()
    ) -> CalendarDataCoordinator {
        let selectionStore = UserDefaultsSelectedSourceCalendarsStore(
            defaults: makeEphemeralUserDefaults()
        )
        return CalendarDataCoordinator(
            configuration: configured,
            environment: makeEnvironment(),
            makeCalendarAPI: { api },
            makeConnectivityMonitor: { FakeEventsConnectivityMonitor() },
            eventStore: eventStore,
            selectionStore: selectionStore,
            disclosureStore: disclosureStore,
            makeSignInAdapter: { _ in signInAdapter },
            makeInstallationBoundary: { store in
                GoogleConnectionInstallationBoundary(
                    defaults: makeEphemeralUserDefaults(),
                    deviceMarkerStore: FakeDeviceMarkerStore(),
                    selectedSourceCalendarsStore: store
                )
            }
        )
    }

    /// A sign-in adapter whose saved account restores with the Calendar
    /// read scope, so the connection publishes the account through the
    /// coordinator once the current disclosure is acknowledged.
    private static func makeRestoringSignInAdapter() -> FakeGoogleSignInAdapter {
        let adapter = FakeGoogleSignInAdapter()
        adapter.restoreHandler = {
            .restored(
                GoogleAuthorizedAccount(
                    stableAccountID: "google-account-1",
                    displayName: nil,
                    imageURL: nil,
                    grantedScopes: [
                        "https://www.googleapis.com/auth/calendar.readonly"
                    ]
                )
            )
        }
        return adapter
    }

    private func eventually(
        _ condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<200 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test("The release gate's off position builds no module")
    func gatedOffBuildsNothing() {
        let coordinator = CalendarDataCoordinator(configuration: nil)
        #expect(coordinator.connection == nil)
        #expect(coordinator.sourceCalendars == nil)
        #expect(coordinator.events == nil)
    }

    @Test("The account publication flows Source Calendars first, then Calendar Events")
    func accountPublicationFlowsSourcesThenEvents() async {
        let api = FakeCalendarDataAPI()
        let coordinator = Self.makeCoordinator(
            api: api,
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion:
                    GoogleAccountConnection.currentDisclosureVersion
            ),
            signInAdapter: Self.makeRestoringSignInAdapter()
        )
        #expect(coordinator.connection != nil)

        // Restoration publishes the account through the connection and
        // coordinator; the events fetch carries the selection the Source
        // Calendars module published — the order the flow exists to
        // protect.
        #expect(
            await eventually {
                api.fetchedEventsSourceCalendars == [Self.primary]
            }
        )
    }

    @Test("Stored Calendar Events present only for a current disclosure acknowledgement")
    func storedPresentationIsDisclosureGated() {
        let acknowledgedStore = FakeStoredCalendarEventsStore()
        acknowledgedStore.snapshot = Self.storedSnapshot()
        let acknowledged = Self.makeCoordinator(
            eventStore: acknowledgedStore,
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion:
                    GoogleAccountConnection.currentDisclosureVersion
            )
        )
        #expect(
            acknowledged.events?.layout(
                forWeekStarting: Self.gmt(2026, 7, 13)
            ) != nil
        )

        let unacknowledgedStore = FakeStoredCalendarEventsStore()
        unacknowledgedStore.snapshot = Self.storedSnapshot()
        let unacknowledged = Self.makeCoordinator(
            eventStore: unacknowledgedStore,
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion: nil
            )
        )
        #expect(
            unacknowledged.events?.layout(
                forWeekStarting: Self.gmt(2026, 7, 13)
            ) == nil
        )
    }

    @Test("A forbidden selected source recovers through the Source Calendars module")
    func recoveryIsWiredEndToEnd() async {
        let api = FakeCalendarDataAPI()
        var eventFetchCount = 0
        api.eventsHandler = { _, _ in
            eventFetchCount += 1
            if eventFetchCount == 1 {
                return .unavailable(.sourceUnavailable)
            }
            return .success(
                events: [
                    GoogleSourceCalendarEvent(
                        sourceCalendar: Self.primary,
                        event: GoogleCalendarEvent(
                            id: "recovered",
                            summary: "Recovered",
                            start: .timed(Self.gmt(2026, 7, 15, 9)),
                            end: .timed(Self.gmt(2026, 7, 15, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        )
                    )
                ],
                eventColorBackgrounds: [:]
            )
        }
        let coordinator = Self.makeCoordinator(
            api: api,
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion:
                    GoogleAccountConnection.currentDisclosureVersion
            ),
            signInAdapter: Self.makeRestoringSignInAdapter()
        )

        // The event failure triggers one live Source Calendar reload and
        // one aggregate retry, which lands the event.
        #expect(
            await eventually {
                coordinator.events?.layout(
                    forWeekStarting: Self.gmt(2026, 7, 13)
                ) != nil
            }
        )
        #expect(api.fetchSourceCalendarsCallCount >= 2)
        #expect(eventFetchCount == 2)
    }

    private static func storedSnapshot() -> StoredCalendarEventsSnapshot {
        StoredCalendarEventsSnapshot(
            accountID: "google-account-1",
            events: [
                CalendarEvent(
                    id: "src:primary@example.com:event:stored",
                    sourceCalendar: primary,
                    title: "Stored",
                    colorHex: "#039BE5",
                    textTone: .light,
                    kind: .row(
                        date: gmt(2026, 7, 15),
                        startsAt: gmt(2026, 7, 15, 9),
                        startTimeText: "9:00 AM"
                    ),
                    detail: CalendarEventDetail(
                        title: "Stored",
                        colorHex: "#039BE5",
                        timingText: "Wed, Jul 15, 2026 · 9:00 – 10:00 AM"
                    )
                )
            ]
        )
    }
}

/// The deterministic Calendar Data API fake: one adapter satisfying both
/// the Calendar Events and Source Calendars seams, recording what the
/// coordinator-wired modules request of it.
@MainActor
private final class FakeCalendarDataAPI: GoogleCalendarEventsAdapting,
    GoogleSourceCalendarsAdapting
{
    var fetchSourceCalendarsCallCount = 0
    var fetchedEventsSourceCalendars: [GoogleSourceCalendar] = []
    var sourceCalendarsHandler: () async -> GoogleSourceCalendarsOutcome = {
        .success([
            GoogleSourceCalendar(
                id: "primary@example.com",
                summary: "Primary",
                backgroundColorHex: "#039BE5",
                isPrimary: true
            )
        ])
    }
    var eventsHandler: (Date, Date) async -> GoogleCalendarEventsOutcome = {
        _, _ in
        .success(events: [], eventColorBackgrounds: [:])
    }

    func fetchPrimarySourceCalendar() async -> GoogleSourceCalendarOutcome {
        .success(
            GoogleSourceCalendar(
                id: "primary@example.com",
                summary: "Primary",
                backgroundColorHex: "#039BE5",
                isPrimary: true
            )
        )
    }

    func fetchEvents(
        from sourceCalendars: [GoogleSourceCalendar],
        start: Date,
        end: Date
    ) async -> GoogleCalendarEventsOutcome {
        fetchedEventsSourceCalendars = sourceCalendars
        return await eventsHandler(start, end)
    }

    func fetchSourceCalendars() async -> GoogleSourceCalendarsOutcome {
        fetchSourceCalendarsCallCount += 1
        return await sourceCalendarsHandler()
    }
}
