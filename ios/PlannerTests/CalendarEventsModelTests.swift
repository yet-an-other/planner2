import Foundation
import Testing
@testable import Planner

/// The deterministic Google Calendar events fake: it records every fetch and
/// resolves outcomes from a test-supplied handler, so Calendar Events model
/// behavior is asserted through the same product-oriented interface the
/// production adapter satisfies.
@MainActor
final class FakeGoogleCalendarEventsAdapter: GoogleCalendarEventsAdapting {
    nonisolated static let defaultCalendar = GoogleSourceCalendar(
        backgroundColorHex: "#039BE5"
    )

    var fetchCallCount = 0
    var fetchedRanges: [(start: Date, end: Date)] = []
    var fetchHandler: (Date, Date) async -> GoogleCalendarEventsOutcome = {
        _, _ in
        .success(calendar: defaultCalendar, events: [])
    }

    func fetchEvents(
        from start: Date,
        to end: Date
    ) async -> GoogleCalendarEventsOutcome {
        fetchCallCount += 1
        fetchedRanges.append((start, end))
        return await fetchHandler(start, end)
    }
}

private final class FakeEventsConnectivityMonitor:
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

@Suite("Calendar Events Model")
@MainActor
struct CalendarEventsModelTests {
    /// The deterministic environment: Wednesday 2026-07-15 at noon GMT.
    private static let now = Date(timeIntervalSince1970: 1_784_116_800)

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
        // The posix locale keeps component construction deterministic, as
        // in the Calendar Grid suite; a locale-less calendar follows the
        // device's settings and is not reliable in tests.
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

    // MARK: Connection-driven fetching

    @Test("A disconnected model fetches nothing and publishes no layouts")
    func disconnectedFetchesNothing() async {
        let (model, adapter) = makeModel()

        model.setConnected(false)

        #expect(adapter.fetchCallCount == 0)
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil
        )
    }

    @Test("Becoming connected fetches the initial window around Today")
    func connectedFetchesInitialWindow() async {
        let (model, adapter) = makeModel()

        model.setConnected(true)

        #expect(await eventually { adapter.fetchCallCount == 1 })
        let range = adapter.fetchedRanges.first
        // Today is 2026-07-15; the window runs three months back from its
        // start of day through three months ahead, inclusive of that day.
        #expect(range?.start.timeIntervalSince1970 == Self.gmt(2026, 4, 15).timeIntervalSince1970)
        #expect(range?.end.timeIntervalSince1970 == Self.gmt(2026, 10, 16).timeIntervalSince1970)
    }

    @Test("A timed single-day event appears as a row with localized start time")
    func timedSingleDayEventAppearsAsRow() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 20, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 20, 10, 15)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        // 2026-07-20 is a Monday, so it is the first cell of its Week Row.
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) != nil
            }
        )
        // The localized short time form comes from the same formatter the
        // model uses, so ICU spacing (such as narrow no-break spaces)
        // never makes identical text compare unequal.
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = Self.makeEnvironment().calendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let layout = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))
        #expect(
            layout?.cells[0].rows == [
                CalendarEventRowItem(
                    id: "standup",
                    title: "Standup",
                    startTimeText: timeFormatter.string(
                        from: Self.gmt(2026, 7, 20, 9, 30)
                    ),
                    colorHex: "#039BE5"
                ),
            ]
        )
    }

    // MARK: Bar classification

    @Test("An all-day single-day event appears as a one-cell bar")
    func allDaySingleDayAppearsAsBar() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "holiday",
                        summary: "Holiday",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)
        let layout = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))
        #expect(
            layout?.bars == [
                CalendarEventBarSegment(
                    id: "holiday",
                    title: "Holiday",
                    colorHex: "#039BE5",
                    textTone: .light,
                    lane: 0,
                    startColumn: 2,
                    endColumn: 2,
                    isStartTruncated: false,
                    isEndTruncated: false
                ),
            ]
        )
        #expect(layout?.cells[2].maxBarLane == 0)
        #expect(layout?.cells[2].rows == [])
    }

    @Test("An all-day multiday event spans its cells with an inclusive end")
    func allDayMultidaySpansCells() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "trip",
                        summary: "Trip",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        // Google's exclusive end: the event's last day is
                        // 2026-07-24, spanning Wednesday through Friday.
                        end: .allDay(year: 2026, month: 7, day: 25),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)
        let bar = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))?.bars.first
        #expect(bar?.startColumn == 2)
        #expect(bar?.endColumn == 4)
        #expect(bar?.isStartTruncated == false)
        #expect(bar?.isEndTruncated == false)
    }

    @Test("A bar crossing a week boundary splits into truncated segments")
    func barCrossingWeekBoundarySplits() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "conference",
                        summary: "Conference",
                        start: .allDay(year: 2026, month: 7, day: 24),
                        // Friday 2026-07-24 through Tuesday 2026-07-28.
                        end: .allDay(year: 2026, month: 7, day: 29),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 27)) != nil)
        let firstWeek = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))?.bars.first
        #expect(firstWeek?.startColumn == 4)
        #expect(firstWeek?.endColumn == 6)
        #expect(firstWeek?.isStartTruncated == false)
        #expect(firstWeek?.isEndTruncated == true)

        let secondWeek = model.layout(forWeekStarting: Self.gmt(2026, 7, 27))?.bars.first
        #expect(secondWeek?.startColumn == 0)
        #expect(secondWeek?.endColumn == 1)
        #expect(secondWeek?.isStartTruncated == true)
        #expect(secondWeek?.isEndTruncated == false)
    }

    @Test("A timed event spanning local midnight becomes a multiday bar")
    func timedMultidayBecomesBar() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "hackathon",
                        summary: "Hackathon",
                        start: .timed(Self.gmt(2026, 7, 21, 22, 0)),
                        end: .timed(Self.gmt(2026, 7, 23, 2, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)
        let bar = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))?.bars.first
        #expect(bar?.startColumn == 1)
        #expect(bar?.endColumn == 3)
    }

    @Test("A timed event ending at local midnight spans into that day")
    func timedEventEndingAtMidnightSpansIntoThatDay() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "release",
                        summary: "Release",
                        start: .timed(Self.gmt(2026, 7, 21, 10, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 0, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)
        let bar = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))?.bars.first
        #expect(bar?.startColumn == 1)
        #expect(bar?.endColumn == 2)
    }

    @Test("An all-day event whose inclusive end precedes its start is dropped")
    func invertedAllDayEventIsDropped() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "broken",
                        summary: "Broken",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 22),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil)
    }

    // MARK: Lane ordering

    @Test("Bars order lanes by start date, then start time")
    func barLanesOrderByStartDateThenStartTime() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    // Starts latest on its start date: lands in the deepest
                    // lane even though it is listed first.
                    GoogleCalendarEvent(
                        id: "late",
                        summary: "Late",
                        start: .timed(Self.gmt(2026, 7, 22, 8, 0)),
                        end: .timed(Self.gmt(2026, 7, 23, 9, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Same start date as "late" but at local midnight:
                    // earlier start time, so a shallower lane.
                    GoogleCalendarEvent(
                        id: "allday",
                        summary: "All Day",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 24),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // The earliest start date wins the shallowest lane.
                    GoogleCalendarEvent(
                        id: "early",
                        summary: "Early",
                        start: .timed(Self.gmt(2026, 7, 21, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.map(\.id) == ["early", "allday", "late"])
        #expect(layout?.bars.map(\.lane) == [0, 1, 2])
    }

    @Test("Bars with the same start order longer duration first")
    func sameStartBarsOrderLongerFirst() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "short",
                        summary: "Short",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 24),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "long",
                        summary: "Long",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 26),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.map(\.id) == ["long", "short"])
        #expect(layout?.bars.map(\.lane) == [0, 1])
    }

    @Test("Non-overlapping bars share a lane")
    func nonOverlappingBarsShareLane() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "first-half",
                        summary: "First Half",
                        start: .allDay(year: 2026, month: 7, day: 20),
                        end: .allDay(year: 2026, month: 7, day: 22),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "second-half",
                        summary: "Second Half",
                        start: .allDay(year: 2026, month: 7, day: 23),
                        end: .allDay(year: 2026, month: 7, day: 25),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.map(\.lane) == [0, 0])
        #expect(layout?.cells[0].maxBarLane == 0)
        #expect(layout?.cells[4].maxBarLane == 0)
        #expect(layout?.cells[2].maxBarLane == -1)
    }

    @Test("Rows order by start time within their Date Cell")
    func rowsOrderByStartTime() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "afternoon",
                        summary: "Afternoon",
                        start: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 15, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "morning",
                        summary: "Morning",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].rows.map(\.id) == ["morning", "afternoon"])
    }

    // MARK: Filtering, titles, and color tone

    @Test("Cancelled and declined events are hidden")
    func cancelledAndDeclinedAreHidden() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "cancelled",
                        summary: "Cancelled",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: true,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "declined",
                        summary: "Declined",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: true
                    ),
                    GoogleCalendarEvent(
                        id: "kept",
                        summary: "Kept",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].rows.map(\.id) == ["kept"])
    }

    @Test("Blank and missing titles become Busy, padded titles trim")
    func titleFallbacks() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "missing",
                        summary: nil,
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "blank",
                        summary: "   ",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "padded",
                        summary: "  Trip  ",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(
            layout?.cells[2].rows.map(\.title) == ["Busy", "Busy", "Trip"]
        )
    }

    @Test("Text tone follows the Source Calendar color")
    func textToneFollowsCalendarColor() async {
        let (darkModel, darkAdapter) = makeModel()
        darkAdapter.fetchHandler = { _, _ in
            .success(
                calendar: GoogleSourceCalendar(backgroundColorHex: "#000000"),
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        let (lightModel, lightAdapter) = makeModel()
        lightAdapter.fetchHandler = { _, _ in
            .success(
                calendar: GoogleSourceCalendar(backgroundColorHex: "#FFFFFF"),
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        darkModel.setConnected(true)
        lightModel.setConnected(true)

        let darkLayout = await layoutEventually(
            darkModel,
            weekStart: Self.gmt(2026, 7, 20)
        )
        let lightLayout = await layoutEventually(
            lightModel,
            weekStart: Self.gmt(2026, 7, 20)
        )
        #expect(darkLayout?.bars.first?.textTone == .light)
        #expect(lightLayout?.bars.first?.textTone == .dark)
    }

    // MARK: Connection lifecycle

    @Test("Disconnecting clears every event and reconnecting fetches fresh")
    func disconnectClearsAndReconnectRefetches() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)

        model.setConnected(false)
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil)

        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20)) != nil)
    }

    @Test("A failed fetch publishes nothing")
    func failedFetchPublishesNothing() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in .unavailable(.failed) }

        model.setConnected(true)

        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil)
    }

    @Test("A model without an adapter stays inert")
    func nilAdapterStaysInert() async {
        let model = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: nil
        )

        model.setConnected(true)
        model.setConnected(false)

        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil)
    }

    @Test("A fetch completing after Disconnect on This Device stays cleared")
    func staleFetchCompletionStaysCleared() async {
        let (model, adapter) = makeModel()
        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }

        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        model.setConnected(false)
        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "stale",
                        summary: "Stale",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        // The stale completion must never republish events over the user's
        // Disconnect on This Device.
        #expect(
            await neverHappens {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) != nil
            }
        )
    }

    @Test("Classification follows the environment's local days, not GMT")
    func classificationFollowsEnvironmentLocalDays() async {
        // Pacific/Kiritimati is UTC+14: an event from 23:30 to 00:30 GMT is
        // 13:30–14:30 on a single local day there, so it presents as an
        // intraday row; in GMT it would span midnight and become a bar.
        guard let kiritimati = TimeZone(identifier: "Pacific/Kiritimati")
        else {
            preconditionFailure("Kiritimati must be available")
        }
        let environment = CalendarEnvironment(
            now: Self.now,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: kiritimati
        )
        let (model, adapter) = makeModel(environment: environment)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "island-time",
                        summary: "Island Time",
                        start: .timed(Self.gmt(2026, 7, 21, 23, 30)),
                        end: .timed(Self.gmt(2026, 7, 22, 0, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        // The local Monday of the event's week is 2026-07-20 in Kiritimati.
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.locale = Locale(identifier: "en_US_POSIX")
        localCalendar.timeZone = kiritimati
        let weekStart = localCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20)
        )!

        let layout = await layoutEventually(model, weekStart: weekStart)
        // Locally the event is Wednesday 13:30–14:30: a row, never a bar.
        #expect(layout?.bars == [])
        #expect(layout?.cells[2].rows.map(\.id) == ["island-time"])
    }

    // MARK: Fetched Window expansion

    @Test("Approaching the latest edge fetches a two-month forward slab")
    func forwardEdgeApproachFetchesSlab() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })
        // Initial window: [2026-04-15, 2026-10-16).

        // Visible through early October: within one month of the last
        // fetched day (2026-10-15).
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(await eventually { adapter.fetchCallCount == 2 })
        let slab = adapter.fetchedRanges.last
        #expect(slab?.start == Self.gmt(2026, 10, 16))
        #expect(slab?.end == Self.gmt(2026, 12, 16))
    }

    @Test("Approaching the earliest edge fetches a two-month backward slab")
    func backwardEdgeApproachFetchesSlab() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        // Visible from early May: within one month of the first fetched
        // day (2026-04-15).
        model.showVisibleRange(
            from: Self.gmt(2026, 5, 4),
            through: Self.gmt(2026, 6, 1)
        )

        #expect(await eventually { adapter.fetchCallCount == 2 })
        let slab = adapter.fetchedRanges.last
        #expect(slab?.start == Self.gmt(2026, 2, 15))
        #expect(slab?.end == Self.gmt(2026, 4, 15))
    }

    @Test("Browsing far from the edges fetches nothing more")
    func middleRangeFetchesNothingMore() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 8, 17)
        )

        #expect(await neverHappens { adapter.fetchCallCount > 1 })
    }

    @Test("A fetched range is never refetched while scrolling back and forth")
    func fetchedRangeNeverRefetches() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })

        // Same approach again, plus one deep into the new window: no more
        // fetches until the new edge comes within one month.
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        model.showVisibleRange(
            from: Self.gmt(2026, 10, 12),
            through: Self.gmt(2026, 11, 9)
        )

        #expect(await neverHappens { adapter.fetchCallCount > 2 })
    }

    @Test("Repeated approaches while a slab is in flight fetch once")
    func inFlightSlabDoesNotDuplicate() async {
        let (model, adapter) = makeModel()
        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }

        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })
        model.showVisibleRange(
            from: Self.gmt(2026, 9, 7),
            through: Self.gmt(2026, 10, 12)
        )

        #expect(await neverHappens { adapter.fetchCallCount > 2 })
        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        )
    }

    @Test("Slab events merge into the boundary Week Row")
    func slabEventsMergeIntoBoundaryWeek() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { start, _ in
            // The initial window carries an event on its last day; the slab
            // carries one three days later — both land in the same
            // Monday-first Week Row (2026-10-12 … 2026-10-18).
            if start == Self.gmt(2026, 4, 15) {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "initial-event",
                            summary: "Initial Event",
                            start: .timed(Self.gmt(2026, 10, 15, 9, 0)),
                            end: .timed(Self.gmt(2026, 10, 15, 10, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "slab-event",
                        summary: "Slab Event",
                        start: .timed(Self.gmt(2026, 10, 18, 9, 0)),
                        end: .timed(Self.gmt(2026, 10, 18, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        model.setConnected(true)
        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 10, 12)) != nil)

        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 10, 12))?
                    .cells.flatMap(\.rows).map(\.id)
                    == ["initial-event", "slab-event"]
            }
        )
    }

    @Test("A failed slab leaves the range empty and retries on the next approach")
    func failedSlabRetriesOnNextApproach() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        adapter.fetchHandler = { _, _ in .unavailable(.failed) }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 11, 2)) == nil)

        // The window never grew, so the next approach retries the slab.
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "recovered",
                        summary: "Recovered",
                        start: .timed(Self.gmt(2026, 11, 4, 9, 0)),
                        end: .timed(Self.gmt(2026, 11, 4, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 9, 7),
            through: Self.gmt(2026, 10, 12)
        )

        #expect(await eventually { adapter.fetchCallCount == 3 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 11, 2)) != nil
            }
        )
    }

    @Test("A slab completing after Disconnect on This Device stays cleared")
    func staleSlabCompletionStaysCleared() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "initial-event",
                        summary: "Initial Event",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        model.setConnected(true)
        #expect(
            await layoutEventually(model, weekStart: Self.gmt(2026, 7, 13))
                != nil
        )

        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })

        model.setConnected(false)
        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "stale-slab",
                        summary: "Stale Slab",
                        start: .timed(Self.gmt(2026, 11, 4, 9, 0)),
                        end: .timed(Self.gmt(2026, 11, 4, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        #expect(
            await neverHappens {
                model.layout(forWeekStarting: Self.gmt(2026, 11, 2)) != nil
            }
        )
    }

    @Test("A redundant connected report does not duplicate the initial fetch")
    func redundantConnectedDoesNotDuplicateInitialFetch() async {
        let (model, adapter) = makeModel()
        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }

        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        // The Calendar Screen can report the same state again while the
        // connection republishes; nothing about the fetch may change.
        model.setConnected(true)
        #expect(await neverHappens { adapter.fetchCallCount > 1 })

        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) != nil
            }
        )
    }

    @Test("A redundant connected report leaves an in-flight slab applicable")
    func redundantConnectedKeepsInFlightSlab() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })

        // A redundant report mid-slab must neither discard the slab nor
        // wedge the direction.
        model.setConnected(true)
        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "slab-event",
                        summary: "Slab Event",
                        start: .timed(Self.gmt(2026, 11, 4, 9, 0)),
                        end: .timed(Self.gmt(2026, 11, 4, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 11, 2)) != nil
            }
        )

        // The direction keeps working: approaching the new edge fetches.
        model.showVisibleRange(
            from: Self.gmt(2026, 11, 2),
            through: Self.gmt(2026, 12, 7)
        )
        #expect(await eventually { adapter.fetchCallCount == 3 })
    }

    // MARK: Visible cap and Events Overflow

    @Test("A Date Cell with four or fewer events shows all of them")
    func fourOrFewerEventsShowAll() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "first",
                        summary: "First",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "second",
                        summary: "Second",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "third",
                        summary: "Third",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "fourth",
                        summary: "Fourth",
                        start: .timed(Self.gmt(2026, 7, 22, 15, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 16, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].rows.map(\.id) == ["first", "second", "third", "fourth"])
        #expect(layout?.cells[2].overflowCount == nil)
    }

    @Test("A day beyond the cap shows three items and an inert count")
    func beyondCapShowsThreePlusOverflow() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (0..<5).map { index in
                    GoogleCalendarEvent(
                        id: "row-\(index)",
                        summary: "Row \(index)",
                        start: .timed(Self.gmt(2026, 7, 22, 9 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10 + index, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].rows.map(\.id) == ["row-0", "row-1", "row-2"])
        #expect(layout?.cells[2].overflowCount == 2)
    }

    @Test("Bars and rows fill the cap in bar-then-row order")
    func mixedItemsCapInBarThenRowOrder() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "bar-a",
                        summary: "Bar A",
                        start: .allDay(year: 2026, month: 7, day: 21),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "bar-b",
                        summary: "Bar B",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 24),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-a",
                        summary: "Row A",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-b",
                        summary: "Row B",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-c",
                        summary: "Row C",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        // Two lanes cross Wednesday, then rows: the cell shows one row and
        // counts the remaining two.
        #expect(layout?.cells[2].maxBarLane == 1)
        #expect(layout?.cells[2].rows.map(\.id) == ["row-a"])
        #expect(layout?.cells[2].overflowCount == 2)
    }

    @Test("A fourth bar lane renders when every crossed Date Cell fits")
    func fourthLaneRendersWhenCellsFit() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (0..<4).map { index in
                    GoogleCalendarEvent(
                        id: "bar-\(index)",
                        summary: "Bar \(index)",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        // Four bars, nothing else: the fourth lane fits the fixed 96-point
        // Week Row, so the cell shows all four events.
        #expect(layout?.bars.map(\.lane) == [0, 1, 2, 3])
        #expect(layout?.cells[2].maxBarLane == 3)
        #expect(layout?.cells[2].rows == [])
        #expect(layout?.cells[2].overflowCount == nil)
    }

    @Test("A fourth lane joins the overflow when a crossed Date Cell overflows")
    func fourthLaneJoinsOverflowWhenCellsOverflow() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (0..<4).map { index in
                    GoogleCalendarEvent(
                        id: "bar-\(index)",
                        summary: "Bar \(index)",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                } + [
                    GoogleCalendarEvent(
                        id: "row-a",
                        summary: "Row A",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        // Five items in the cell: three lanes render, the fourth lane and
        // the row count into the overflow.
        #expect(layout?.bars.map(\.lane) == [0, 1, 2])
        #expect(layout?.cells[2].maxBarLane == 2)
        #expect(layout?.cells[2].rows == [])
        #expect(layout?.cells[2].overflowCount == 2)
    }

    @Test("Three lanes and one row fit without overflow")
    func threeLanesAndOneRowFit() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "bar-a",
                        summary: "Bar A",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "bar-b",
                        summary: "Bar B",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "bar-c",
                        summary: "Bar C",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-a",
                        summary: "Row A",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].maxBarLane == 2)
        #expect(layout?.cells[2].rows.map(\.id) == ["row-a"])
        #expect(layout?.cells[2].overflowCount == nil)
    }

    @Test("Overflow in one Date Cell leaves its neighbors untouched")
    func overflowLeavesNeighborsUntouched() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (0..<5).map { index in
                    GoogleCalendarEvent(
                        id: "row-\(index)",
                        summary: "Row \(index)",
                        start: .timed(Self.gmt(2026, 7, 22, 9 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10 + index, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                } + [
                    GoogleCalendarEvent(
                        id: "quiet",
                        summary: "Quiet",
                        start: .timed(Self.gmt(2026, 7, 23, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 23, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[2].overflowCount == 2)
        #expect(layout?.cells[3].rows.map(\.id) == ["quiet"])
        #expect(layout?.cells[3].overflowCount == nil)
    }

    @Test("Gapped lanes never push rows or the marker past the Week Row")
    func gappedLanesKeepMarkerInsideRow() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    // Starts the day before, so it takes lane 0, clipped
                    // to Monday and Tuesday of this Week Row.
                    GoogleCalendarEvent(
                        id: "early",
                        summary: "Early",
                        start: .timed(Self.gmt(2026, 7, 19, 23, 0)),
                        end: .timed(Self.gmt(2026, 7, 21, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Lane 1 across the whole week.
                    GoogleCalendarEvent(
                        id: "long",
                        summary: "Long",
                        start: .allDay(year: 2026, month: 7, day: 20),
                        end: .allDay(year: 2026, month: 7, day: 25),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Lane 2 across Monday through Wednesday, leaving a
                    // lane-0 gap at Wednesday.
                    GoogleCalendarEvent(
                        id: "mid",
                        summary: "Mid",
                        start: .allDay(year: 2026, month: 7, day: 20),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-a",
                        summary: "Row A",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "row-b",
                        summary: "Row B",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        // Wednesday crosses lanes 0 and 2 with a gap at lane 1; rows would
        // paint past the 96-point Week Row, so both join the overflow
        // instead, leaving the marker as the cell's last visible item.
        #expect(layout?.cells[2].maxBarLane == 2)
        #expect(layout?.cells[2].rows == [])
        #expect(layout?.cells[2].overflowCount == 2)
    }

    // MARK: Header Status messaging and offline recovery

    @Test("Fetching the initial window announces progress and clears on success")
    func initialFetchAnnouncesProgress() async {
        let (model, adapter) = makeModel()

        model.setConnected(true)

        #expect(
            model.status
                == CalendarEventsStatus(
                    message: CalendarEventsCopy.loading,
                    tone: .info
                )
        )
        #expect(
            await eventually {
                adapter.fetchCallCount == 1
                    && model.status.message == nil
            }
        )
    }

    @Test("An offline initial fetch warns and retries on connectivity return")
    func offlineInitialFetchWarnsAndRetries() async {
        let (model, adapter, monitor) = makeModelWithMonitor()
        adapter.fetchHandler = { _, _ in .unavailable(.offline) }

        model.setConnected(true)

        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.offline,
                        tone: .warning
                    )
            }
        )
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)

        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        monitor.simulateConnectivityReturn()

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
                    && model.status.message == nil
            }
        )
    }

    @Test("A failed initial fetch reports an error and keeps the bare grid")
    func failedInitialFetchReportsError() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in .unavailable(.failed) }

        model.setConnected(true)

        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.failed,
                        tone: .error
                    )
            }
        )
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)
    }

    @Test("A slab fetch announces progress and clears on success")
    func slabFetchAnnouncesProgress() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { model.status.message == nil })

        var release: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { release = $0 }
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.loading,
                        tone: .info
                    )
            }
        )
        // The status flips synchronously; the fetch itself lands a turn
        // later, so wait for it before releasing.
        #expect(await eventually { adapter.fetchCallCount == 2 })

        release?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        )
        #expect(await eventually { model.status.message == nil })
    }

    @Test("An offline slab failure keeps events, warns, and recovers on return")
    func offlineSlabKeepsEventsAndRecovers() async {
        let (model, adapter, monitor) = makeModelWithMonitor()
        adapter.fetchHandler = { _, _ in .success(calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar, events: [Self.initialEvent]) }
        model.setConnected(true)
        #expect(
            await layoutEventually(model, weekStart: Self.gmt(2026, 7, 13))
                != nil
        )

        adapter.fetchHandler = { _, _ in .unavailable(.offline) }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.offlinePartial,
                        tone: .warning
                    )
            }
        )
        // Already-fetched events stay visible.
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil)

        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "slab-event",
                        summary: "Slab Event",
                        start: .timed(Self.gmt(2026, 11, 4, 9, 0)),
                        end: .timed(Self.gmt(2026, 11, 4, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        monitor.simulateConnectivityReturn()

        #expect(await eventually { adapter.fetchCallCount == 3 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 11, 2)) != nil
                    && model.status.message == nil
            }
        )
    }

    @Test("A failed slab warns without hiding fetched events")
    func failedSlabWarns() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in .success(calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar, events: [Self.initialEvent]) }
        model.setConnected(true)
        #expect(
            await layoutEventually(model, weekStart: Self.gmt(2026, 7, 13))
                != nil
        )

        adapter.fetchHandler = { _, _ in .unavailable(.failed) }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.failedPartial,
                        tone: .warning
                    )
            }
        )
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil)
    }

    @Test("Disconnect on This Device clears the events status")
    func disconnectClearsStatus() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in .unavailable(.failed) }

        model.setConnected(true)
        #expect(
            await eventually {
                model.status
                    == CalendarEventsStatus(
                        message: CalendarEventsCopy.failed,
                        tone: .error
                    )
            }
        )

        model.setConnected(false)

        #expect(model.status.message == nil)
    }

    // MARK: Helpers

    private static var initialEvent: GoogleCalendarEvent {
        GoogleCalendarEvent(
            id: "initial-event",
            summary: "Initial Event",
            start: .timed(gmt(2026, 7, 15, 9, 0)),
            end: .timed(gmt(2026, 7, 15, 10, 0)),
            isCancelled: false,
            isDeclinedByViewer: false
        )
    }

    private func makeModel(
        environment: CalendarEnvironment = Self.makeEnvironment()
    ) -> (CalendarEventsModel, FakeGoogleCalendarEventsAdapter) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let model = CalendarEventsModel(environment: environment, adapter: adapter)
        return (model, adapter)
    }

    private func makeModelWithMonitor(
        environment: CalendarEnvironment = Self.makeEnvironment()
    ) -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter,
        FakeEventsConnectivityMonitor
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let monitor = FakeEventsConnectivityMonitor()
        let model = CalendarEventsModel(
            environment: environment,
            adapter: adapter,
            connectivityMonitor: monitor
        )
        return (model, adapter, monitor)
    }

    private func layoutEventually(
        _ model: CalendarEventsModel,
        weekStart: Date
    ) async -> CalendarEventWeekLayout? {
        _ = await eventually { model.layout(forWeekStarting: weekStart) != nil }
        return model.layout(forWeekStarting: weekStart)
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

    /// The mirror of `eventually`: holds for a short window that a condition
    /// never becomes true, for stale-completion and no-fetch assertions.
    private func neverHappens(
        timeout: Duration = .milliseconds(200),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}
