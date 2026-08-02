import Foundation
import SwiftUI
import Testing
@testable import Planner

/// Test convenience for Primary Source Calendars whose identity and summary
/// are irrelevant to the behavior under test.
private extension GoogleSourceCalendar {
    init(backgroundColorHex: String) {
        self.init(
            id: "primary@example.com",
            summary: "Primary",
            backgroundColorHex: backgroundColorHex,
            isPrimary: true
        )
    }
}

/// The deterministic Source Calendar recovery fake: it records each live
/// reload request and resolves the reconciled selection from a
/// test-supplied handler, so forbidden/not-found recovery is asserted
/// through the same interface the Source Calendars module satisfies.
@MainActor
private final class FakeSourceCalendarRecovery: SourceCalendarRecoveryHandling {
    var callCount = 0
    var handler: () async -> [GoogleSourceCalendar]? = { nil }

    func reconcileSelectionAfterSourceFailure() async
        -> [GoogleSourceCalendar]?
    {
        callCount += 1
        return await handler()
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

    // MARK: Cross-calendar occurrence identity

    /// Two Source Calendars used throughout the cross-calendar identity
    /// tests: the default Primary and a secondary Family calendar.
    private static let familySource = GoogleSourceCalendar(
        id: "family",
        summary: "Family",
        backgroundColorHex: "#7CB342",
        isPrimary: false
    )

    private static func duplicateCopy(
        source: GoogleSourceCalendar,
        id: String,
        iCalUID: String?,
        summary: String,
        originalStartTime: GoogleCalendarEventTime? = nil,
        start: GoogleCalendarEventTime,
        end: GoogleCalendarEventTime
    ) -> GoogleSourceCalendarEvent {
        GoogleSourceCalendarEvent(
            sourceCalendar: source,
            event: GoogleCalendarEvent(
                id: id,
                iCalUID: iCalUID,
                originalStartTime: originalStartTime,
                summary: summary,
                start: start,
                end: end,
                isCancelled: false,
                isDeclinedByViewer: false
            )
        )
    }

    @Test("Refresh keeps Event Detail current when the winning copy changes")
    func refreshTracksWinningCopyChange() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let family = Self.familySource
        let (model, adapter) = makeModel()
        var primaryCopyPresent = true
        adapter.fetchHandler = { _, _ in
            var events = [
                Self.duplicateCopy(
                    source: family,
                    id: "invite-family",
                    iCalUID: "uid-invite@google.com",
                    summary: "Family copy",
                    start: .timed(Self.gmt(2026, 7, 21, 9)),
                    end: .timed(Self.gmt(2026, 7, 21, 10))
                ),
            ]
            if primaryCopyPresent {
                events.append(
                    Self.duplicateCopy(
                        source: primary,
                        id: "invite-primary",
                        iCalUID: "uid-invite@google.com",
                        summary: "Primary copy",
                        start: .timed(Self.gmt(2026, 7, 21, 9)),
                        end: .timed(Self.gmt(2026, 7, 21, 10))
                    )
                )
            }
            return .success(events: events, eventColorBackgrounds: [:])
        }

        model.setSelectedSourceCalendars([primary, family])
        let layout = await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        )
        guard let canonicalRowID = layout?.cells[1].rows.first?.id else {
            Issue.record("Expected one canonical row")
            return
        }
        model.selectEvent(withID: canonicalRowID)
        #expect(model.selectedEvent?.sourceCalendar == primary)
        #expect(model.selectedEvent?.detail.title == "Primary copy")

        // The Primary copy disappears; the Family copy becomes the winner
        // under the same canonical identity, so the open popover updates
        // instead of dismissing.
        primaryCopyPresent = false
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.selectedEvent?.detail.title == "Family copy"
            }
        )
        #expect(model.selectedEvent?.id == canonicalRowID)
        #expect(model.selectedEvent?.sourceCalendar == family)
    }

    @Test("Refresh dismisses Event Detail when the occurrence disappears")
    func refreshDismissesRemovedOccurrence() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let family = Self.familySource
        let (model, adapter) = makeModel()
        var occurrencePresent = true
        adapter.fetchHandler = { _, _ in
            .success(
                events: occurrencePresent
                    ? [
                        Self.duplicateCopy(
                            source: primary,
                            id: "invite-primary",
                            iCalUID: "uid-invite@google.com",
                            summary: "Primary copy",
                            start: .timed(Self.gmt(2026, 7, 21, 9)),
                            end: .timed(Self.gmt(2026, 7, 21, 10))
                        ),
                        Self.duplicateCopy(
                            source: family,
                            id: "invite-family",
                            iCalUID: "uid-invite@google.com",
                            summary: "Family copy",
                            start: .timed(Self.gmt(2026, 7, 21, 9)),
                            end: .timed(Self.gmt(2026, 7, 21, 10))
                        ),
                    ]
                    : [],
                eventColorBackgrounds: [:]
            )
        }

        model.setSelectedSourceCalendars([primary, family])
        let layout = await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        )
        guard let canonicalRowID = layout?.cells[1].rows.first?.id else {
            Issue.record("Expected one canonical row")
            return
        }
        model.selectEvent(withID: canonicalRowID)
        #expect(model.selectedEvent != nil)

        occurrencePresent = false
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(await eventually { model.selectedEvent == nil })
    }

    // MARK: Connection-driven fetching

    @Test("Opaque Source Calendar IDs occupy one Google API path segment")
    func opaqueSourceCalendarIDIsOnePathSegment() {
        #expect(
            GoogleCalendarAPIPath.events(
                sourceCalendarID: "team/shared#calendar@example.com"
            ) == "/calendar/v3/calendars/team%2Fshared%23calendar@example.com/events"
        )
    }

    @Test("A disconnected model fetches nothing and publishes no layouts")
    func disconnectedFetchesNothing() async {
        let (model, adapter) = makeModel()

        model.setConnected(false)

        #expect(adapter.fetchCallCount == 0)
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil
        )
    }

    @Test("Becoming connected fetches the initial window from the explicit Primary Source Calendar")
    func connectedFetchesInitialWindow() async {
        let (model, adapter) = makeModel()

        model.setConnected(true)

        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(adapter.primarySourceCalendarFetchCallCount == 1)
        #expect(
            adapter.fetchedSourceCalendars
                == [[FakeGoogleCalendarEventsAdapter.defaultCalendar]]
        )
        let range = adapter.fetchedRanges.first
        // Today is 2026-07-15; the window runs three months back from its
        // start of day through three months ahead, inclusive of that day.
        #expect(range?.start.timeIntervalSince1970 == Self.gmt(2026, 4, 15).timeIntervalSince1970)
        #expect(range?.end.timeIntervalSince1970 == Self.gmt(2026, 10, 16).timeIntervalSince1970)
    }

    @Test("A reconciled selection starts events without Primary discovery")
    func reconciledSelectionStartsEventsDirectly() async {
        let sourceCalendar = GoogleSourceCalendar(
            id: "fallback@example.com",
            summary: "Fallback",
            backgroundColorHex: "#7CB342",
            isPrimary: false
        )
        let (model, adapter) = makeModel()

        model.setSelectedSourceCalendars([sourceCalendar])

        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(adapter.primarySourceCalendarFetchCallCount == 0)
        #expect(adapter.fetchedSourceCalendars == [[sourceCalendar]])
    }

    @Test("Changed picker dismissal atomically replaces around visible dates")
    func changedPickerDismissalReplacesVisibleWindow() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let family = GoogleSourceCalendar(
            id: "family",
            summary: "Family",
            backgroundColorHex: "#7CB342",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        var releaseReplacement:
            CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: primary,
                    events: [
                        GoogleCalendarEvent(
                            id: "old",
                            summary: "Old snapshot",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return await withCheckedContinuation { releaseReplacement = $0 }
        }

        model.setSelectedSourceCalendars([primary])
        let weekStart = Self.gmt(2026, 7, 20)
        #expect(await layoutEventually(model, weekStart: weekStart) != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 26)
        )

        model.sourceCalendarPickerDidOpen()
        model.sourceCalendarPickerDidClose(
            selectedSourceCalendars: [primary, family],
            selectionChanged: true
        )

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(adapter.fetchedSourceCalendars.last == [primary, family])
        #expect(adapter.fetchedRanges.last?.start == Self.gmt(2026, 4, 13))
        #expect(adapter.fetchedRanges.last?.end == Self.gmt(2026, 10, 27))
        #expect(model.status.message == CalendarEventsCopy.updatingSelection)
        #expect(
            model.layout(forWeekStarting: weekStart)?
                .cells[0].rows.map(\.id) == [canonicalID("old")]
        )

        releaseReplacement?.resume(
            returning: .success(
                events: [
                    GoogleSourceCalendarEvent(
                        sourceCalendar: family,
                        event: GoogleCalendarEvent(
                            id: "new",
                            summary: "New snapshot",
                            start: .timed(Self.gmt(2026, 7, 20, 11)),
                            end: .timed(Self.gmt(2026, 7, 20, 12)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        )
                    ),
                ],
                eventColorBackgrounds: [:]
            )
        )

        #expect(
            await eventually {
                model.layout(forWeekStarting: weekStart)?
                    .cells[0].rows.map(\.id) == [canonicalID("new", source: family)]
            }
        )
        #expect(model.status.message == nil)
    }

    @Test("Failed selection replacement retains the prior atomic snapshot")
    func failedSelectionReplacementRetainsSnapshot() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let family = GoogleSourceCalendar(
            id: "family",
            summary: "Family",
            backgroundColorHex: "#7CB342",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: primary,
                    events: [
                        GoogleCalendarEvent(
                            id: "old",
                            summary: "Old snapshot",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return .unavailable(.failed)
        }

        model.setSelectedSourceCalendars([primary])
        let weekStart = Self.gmt(2026, 7, 20)
        #expect(await layoutEventually(model, weekStart: weekStart) != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 26)
        )
        model.sourceCalendarPickerDidOpen()
        model.sourceCalendarPickerDidClose(
            selectedSourceCalendars: [primary, family],
            selectionChanged: true
        )

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.refreshFailed
            }
        )
        #expect(
            model.layout(forWeekStarting: weekStart)?
                .cells[0].rows.map(\.id) == [canonicalID("old")]
        )
    }

    @Test("A later changed dismissal wins over an older replacement")
    func latestSelectionReplacementWins() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let family = GoogleSourceCalendar(
            id: "family",
            summary: "Family",
            backgroundColorHex: "#7CB342",
            isPrimary: false
        )
        let work = GoogleSourceCalendar(
            id: "work",
            summary: "Work",
            backgroundColorHex: "#7986CB",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        var releaseOlder:
            CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            switch fetchNumber {
            case 1:
                return .success(calendar: primary, events: [])
            case 2:
                return await withCheckedContinuation { releaseOlder = $0 }
            default:
                return .success(
                    calendar: work,
                    events: [
                        GoogleCalendarEvent(
                            id: "latest",
                            summary: "Latest",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
        }

        model.setSelectedSourceCalendars([primary])
        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(await eventually { model.status.message == nil })
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 26)
        )
        model.sourceCalendarPickerDidOpen()
        model.sourceCalendarPickerDidClose(
            selectedSourceCalendars: [primary, family],
            selectionChanged: true
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })

        model.sourceCalendarPickerDidOpen()
        model.sourceCalendarPickerDidClose(
            selectedSourceCalendars: [work],
            selectionChanged: true
        )
        releaseOlder?.resume(
            returning: .success(
                calendar: family,
                events: [
                    GoogleCalendarEvent(
                        id: "stale",
                        summary: "Stale",
                        start: .timed(Self.gmt(2026, 7, 20, 11)),
                        end: .timed(Self.gmt(2026, 7, 20, 12)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        #expect(await eventually { adapter.fetchCallCount == 3 })
        #expect(adapter.fetchedSourceCalendars.last == [work])
        let layout = await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        )
        #expect(layout?.cells[0].rows.map(\.id) == [canonicalID("latest", source: work)])
    }

    @Test("Source Calendar identity and presentation remain on Calendar Events")
    func sourceCalendarIdentityRemainsOnCalendarEvents() async {
        let sourceCalendar = GoogleSourceCalendar(
            id: "team@example.com",
            summary: "Team",
            backgroundColorHex: "#7CB342",
            isPrimary: true
        )
        let (model, adapter) = makeModel()
        adapter.primarySourceCalendarOutcome = .success(sourceCalendar)
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: sourceCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "planning",
                        summary: "Planning",
                        start: .timed(Self.gmt(2026, 7, 20, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 20, 10, 15)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        )
        let row = layout?.cells[0].rows.first
        #expect(row?.sourceCalendar == sourceCalendar)
        #expect(row?.colorHex == sourceCalendar.backgroundColorHex)

        model.selectEvent(withID: canonicalID("planning", source: sourceCalendar))
        #expect(model.selectedEvent?.sourceCalendar == sourceCalendar)
    }

    @Test("A forbidden selected source reloads, reconciles, and retries once")
    func sourceUnavailableRecoversAndRetriesOnce() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let work = GoogleSourceCalendar(
            id: "work",
            summary: "Work",
            backgroundColorHex: "#7986CB",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        let recovery = FakeSourceCalendarRecovery()
        // The live reload confirms Work is unavailable.
        recovery.handler = { [primary] }
        model.sourceCalendarRecovery = recovery

        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .unavailable(.sourceUnavailable)
            }
            return .success(
                calendar: primary,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9)),
                        end: .timed(Self.gmt(2026, 7, 15, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setSelectedSourceCalendars([primary, work])

        #expect(await eventually { adapter.fetchCallCount == 2 })
        // One live reload and one aggregate retry against the reconciled
        // selection.
        #expect(recovery.callCount == 1)
        #expect(adapter.fetchedSourceCalendars == [[primary, work], [primary]])
        let layout = await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 13)
        )
        #expect(layout?.cells.flatMap(\.rows).map(\.id) == [canonicalID("standup")])
        #expect(model.status.message == nil)
    }

    @Test("A repeated forbidden failure stops after one aggregate retry")
    func sourceUnavailableRetriesOnlyOnce() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let work = GoogleSourceCalendar(
            id: "work",
            summary: "Work",
            backgroundColorHex: "#7986CB",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        let recovery = FakeSourceCalendarRecovery()
        recovery.handler = { [primary] }
        model.sourceCalendarRecovery = recovery
        adapter.fetchHandler = { _, _ in .unavailable(.sourceUnavailable) }

        model.setSelectedSourceCalendars([primary, work])

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.failed
            }
        )
        #expect(adapter.fetchCallCount == 2)
        #expect(recovery.callCount == 1)
    }

    @Test("A failed recovery reload retains the selection and reports failure")
    func failedRecoveryReloadRetainsSelection() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let work = GoogleSourceCalendar(
            id: "work",
            summary: "Work",
            backgroundColorHex: "#7986CB",
            isPrimary: false
        )
        let (model, adapter) = makeModel()
        let recovery = FakeSourceCalendarRecovery()
        // The live reload cannot confirm anything.
        recovery.handler = { nil }
        model.sourceCalendarRecovery = recovery
        adapter.fetchHandler = { _, _ in .unavailable(.sourceUnavailable) }

        model.setSelectedSourceCalendars([primary, work])

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.failed
            }
        )
        // No aggregate retry without a confirmed reconciliation; the
        // durable selection remains for the next attempt.
        #expect(recovery.callCount == 1)
        #expect(adapter.fetchCallCount == 1)
        #expect(adapter.fetchedSourceCalendars == [[primary, work]])
    }

    @Test("Without a recovery handler a forbidden failure is a plain failure")
    func sourceUnavailableWithoutRecoveryIsPlainFailure() async {
        let primary = FakeGoogleCalendarEventsAdapter.defaultCalendar
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in .unavailable(.sourceUnavailable) }

        model.setSelectedSourceCalendars([primary])

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.failed
            }
        )
        #expect(adapter.fetchCallCount == 1)
    }

    @Test("A Primary Source Calendar failure starts no Calendar Event request")
    func primarySourceCalendarFailureStartsNoEventRequest() async {
        let (model, adapter) = makeModel()
        adapter.primarySourceCalendarOutcome = .unavailable(.failed)

        model.setConnected(true)

        #expect(
            await eventually {
                adapter.primarySourceCalendarFetchCallCount == 1
                    && model.status.message == CalendarEventsCopy.failed
            }
        )
        #expect(adapter.fetchCallCount == 0)
        #expect(model.weekLayouts.isEmpty)
    }

    @Test("Primary discovery completing after Disconnect starts no event request")
    func stalePrimarySourceCalendarCompletionStartsNoEventRequest() async {
        let (model, adapter) = makeModel()
        var release: CheckedContinuation<GoogleSourceCalendarOutcome, Never>?
        adapter.primarySourceCalendarHandler = {
            await withCheckedContinuation { release = $0 }
        }

        model.setConnected(true)
        #expect(
            await eventually {
                adapter.primarySourceCalendarFetchCallCount == 1
            }
        )

        model.setConnected(false)
        release?.resume(
            returning: .success(
                FakeGoogleCalendarEventsAdapter.defaultCalendar
            )
        )

        #expect(await neverHappens { adapter.fetchCallCount > 0 })
        #expect(model.weekLayouts.isEmpty)
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
                    id: canonicalID("standup"),
                    sourceCalendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
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
                    id: canonicalID("holiday"),
                    sourceCalendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    title: "Holiday",
                    colorHex: "#039BE5",
                    // White out-reads Planner's ink on this blue (APCA).
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
        #expect(layout?.bars.map(\.id) == ["early", "allday", "late"].map { canonicalID($0) })
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
        #expect(layout?.bars.map(\.id) == ["long", "short"].map { canonicalID($0) })
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
        #expect(layout?.cells[2].rows.map(\.id) == ["morning", "afternoon"].map { canonicalID($0) })
    }

    // MARK: Filtering, titles, and color tone

    // MARK: Event Color

    @Test("A colors-metadata failure silently degrades to the Source Calendar color")
    func colorsMetadataFailureDegradesSilently() async {
        let (model, adapter) = makeModel()
        // The adapter maps a failed colors fetch to empty metadata.
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: GoogleSourceCalendar(backgroundColorHex: "#039BE5"),
                events: [
                    GoogleCalendarEvent(
                        id: "recolored",
                        summary: "Recolored",
                        colorId: "9",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        end: .allDay(year: 2026, month: 7, day: 23),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ],
                eventColorBackgrounds: [:]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.first?.colorHex == "#039BE5")
        // Silent: the cosmetic degradation never reaches the iOS Header
        // Status.
        #expect(model.status.message == nil)
    }

    @Test("An intraday row's dot carries the explicit Google event color")
    func rowDotCarriesExplicitEventColor() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: GoogleSourceCalendar(backgroundColorHex: "#039BE5"),
                events: [
                    GoogleCalendarEvent(
                        id: "recolored",
                        summary: "Recolored",
                        colorId: "9",
                        start: .timed(Self.gmt(2026, 7, 20, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 20, 10, 15)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ],
                eventColorBackgrounds: ["9": "#5484ED"]
            )
        }

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.cells[0].rows.first?.colorHex == "#5484ED")
    }

    @Test("Bar text tone picks the higher-contrast candidate for the Event Color")
    func textTonePicksHigherContrastCandidate() async {
        let (model, adapter) = makeModel()
        // Google palette Blueberry: white out-reads Planner's ink on it
        // (APCA Lc 66 vs 42) — the WCAG 2.x ratio ranks ink higher here,
        // which is exactly the mis-ranking iOS ADR 0004 retires.
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: GoogleSourceCalendar(backgroundColorHex: "#5484ED"),
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

        model.setConnected(true)

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.first?.textTone == .light)
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

    // MARK: Calendar Event Refresh

    @Test("Foreground refresh silently replaces an edited event after success")
    func foregroundRefreshSilentlyReplacesEditedEvent() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        var releaseRefresh: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "event",
                            summary: "Before",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return await withCheckedContinuation { releaseRefresh = $0 }
        }

        model.setConnected(true)
        let weekStart = Self.gmt(2026, 7, 20)
        #expect(await layoutEventually(model, weekStart: weekStart)?
            .cells[0].rows.first?.title == "Before")
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )

        model.refreshOnForeground()
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(model.status.message == nil)
        #expect(model.layout(forWeekStarting: weekStart)?
            .cells[0].rows.first?.title == "Before")

        releaseRefresh?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "After",
                        start: .timed(Self.gmt(2026, 7, 20, 11)),
                        end: .timed(Self.gmt(2026, 7, 20, 12)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        #expect(
            await eventually {
                model.layout(forWeekStarting: weekStart)?
                    .cells[0].rows.first?.title == "After"
            }
        )
    }

    @Test("An open Event Detail Popover follows a canonical edit and move")
    func selectedEventFollowsCanonicalEditAndMove() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "selected",
                            summary: "Before",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false,
                            googleLink: "https://calendar.google.com/before",
                            location: "Room 1",
                            notes: "Old notes",
                            attendees: [
                                GoogleCalendarEventAttendee(
                                    displayName: "Ada",
                                    email: "ada@example.com",
                                    responseStatus: "needsAction"
                                ),
                            ]
                        ),
                    ]
                )
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "selected",
                        summary: "After",
                        colorId: "updated-color",
                        start: .timed(Self.gmt(2026, 7, 21, 11)),
                        end: .timed(Self.gmt(2026, 7, 21, 12, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        googleLink: "https://calendar.google.com/after",
                        location: "Room 2",
                        notes: "<p>New <b>notes</b></p>",
                        attendees: [
                            GoogleCalendarEventAttendee(
                                displayName: "Ada Lovelace",
                                email: "ada@example.com",
                                responseStatus: "accepted"
                            ),
                            GoogleCalendarEventAttendee(
                                displayName: nil,
                                email: "grace@example.com",
                                responseStatus: "tentative"
                            ),
                        ]
                    ),
                ],
                eventColorBackgrounds: ["updated-color": "#D50000"]
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        model.selectEvent(withID: canonicalID("selected"))
        #expect(model.selectedEvent?.id == canonicalID("selected"))
        #expect(model.selectedEvent?.detail.title == "Before")

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.selectedEvent?.detail.title == "After"
            }
        )
        let detail = model.selectedEvent?.detail
        #expect(model.selectedEvent?.id == canonicalID("selected"))
        #expect(detail?.colorHex == "#D50000")
        #expect(
            detail?.timingText
                == "\(Self.fullDateText(Self.gmt(2026, 7, 21))) · "
                    + Self.timeText(Self.gmt(2026, 7, 21, 11))
                    + " – "
                    + Self.timeText(Self.gmt(2026, 7, 21, 12, 30))
        )
        #expect(detail?.location == "Room 2")
        #expect(detail?.notes == "New notes")
        #expect(
            detail?.attendees == [
                CalendarEventAttendee(label: "Ada Lovelace", status: .accepted),
                CalendarEventAttendee(label: "grace@example.com", status: .tentative),
            ]
        )
        #expect(detail?.googleLink == "https://calendar.google.com/after")
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 20))?
                .cells[1].rows.map(\.id) == [canonicalID("selected")]
        )
    }

    @Test("Bounded replacement dismisses a selected event that disappears")
    func boundedReplacementDismissesSelectedEventThatDisappears() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: fetchNumber == 1
                    ? [
                        GoogleCalendarEvent(
                            id: "selected",
                            summary: "Selected",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                    : []
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        model.selectEvent(withID: canonicalID("selected"))
        #expect(model.selectedEvent != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(await eventually { model.selectedEvent == nil })
    }

    @Test("A declined canonical replacement dismisses its selected event")
    func declinedReplacementDismissesSelectedEvent() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "selected",
                        summary: "Selected",
                        start: .timed(Self.gmt(2026, 7, 20, 9)),
                        end: .timed(Self.gmt(2026, 7, 20, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: fetchNumber > 1
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        model.selectEvent(withID: canonicalID("selected"))
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(await eventually { model.selectedEvent == nil })
    }

    @Test("A failed refresh leaves the selected detail unchanged")
    func failedRefreshLeavesSelectedDetailUnchanged() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber > 1 {
                return .unavailable(.failed)
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "selected",
                        summary: "Selected",
                        start: .timed(Self.gmt(2026, 7, 20, 9)),
                        end: .timed(Self.gmt(2026, 7, 20, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        notes: "Keep this"
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        model.selectEvent(withID: canonicalID("selected"))
        let selectedBeforeRefresh = model.selectedEvent
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.refreshFailed
            }
        )
        #expect(model.selectedEvent == selectedBeforeRefresh)
    }

    @Test("Refresh moves one event into range and removes a newly declined event")
    func refreshMovesAndDeclinesEvents() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: fetchNumber == 1
                    ? [
                        GoogleCalendarEvent(
                            id: "moved",
                            summary: "Moved",
                            start: .timed(Self.gmt(2026, 9, 21, 9)),
                            end: .timed(Self.gmt(2026, 9, 21, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "declined",
                            summary: "Declined",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                    : [
                        GoogleCalendarEvent(
                            id: "moved",
                            summary: "Moved",
                            start: .timed(Self.gmt(2026, 7, 21, 11)),
                            end: .timed(Self.gmt(2026, 7, 21, 12)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "declined",
                            summary: "Declined",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: true
                        ),
                    ]
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 9, 21)
        ) != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        let julyWeek = Self.gmt(2026, 7, 20)
        #expect(
            await eventually {
                model.layout(forWeekStarting: julyWeek)?
                    .cells[1].rows.map(\.id) == [canonicalID("moved")]
            }
        )
        #expect(model.layout(forWeekStarting: julyWeek)?
            .cells[0].rows.isEmpty == true)
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 9, 21)) == nil)
    }

    @Test("Removing a multiday event clears every old Week Row segment")
    func removingMultidayEventClearsEveryOldSegment() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: fetchNumber == 1
                    ? [
                        GoogleCalendarEvent(
                            id: "trip",
                            summary: "Trip",
                            start: .allDay(year: 2026, month: 6, day: 1),
                            end: .allDay(year: 2026, month: 9, day: 2),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                    : []
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 6, 1)
        ) != nil)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 8, 31)
        ) != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 6, 1)) == nil
                    && model.layout(
                        forWeekStarting: Self.gmt(2026, 8, 31)
                    ) == nil
            }
        )
    }

    @Test("A failed foreground refresh retains events with a warning")
    func failedRefreshRetainsEventsWithWarning() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 2 {
                return .unavailable(.failed)
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "event",
                        summary: "Event",
                        start: .timed(Self.gmt(2026, 7, 20, 9)),
                        end: .timed(Self.gmt(2026, 7, 20, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        let weekStart = Self.gmt(2026, 7, 20)
        #expect(await layoutEventually(model, weekStart: weekStart) != nil)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.refreshFailed
            }
        )
        #expect(model.status.tone == .warning)
        #expect(model.layout(forWeekStarting: weekStart) != nil)
    }

    @Test("A refresh completion after reconnect cannot replace newer events")
    func staleRefreshAfterReconnectCannotReplaceNewerEvents() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        var releaseRefresh: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            switch fetchNumber {
            case 1:
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: []
                )
            case 2:
                return await withCheckedContinuation { releaseRefresh = $0 }
            default:
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "new",
                            summary: "New connection",
                            start: .timed(Self.gmt(2026, 7, 20, 11)),
                            end: .timed(Self.gmt(2026, 7, 20, 12)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
        }

        model.setConnected(true)
        #expect(await eventually { model.status.message == nil })
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()
        #expect(await eventually { releaseRefresh != nil })

        model.setConnected(false)
        model.setConnected(true)
        // The reconnect queues its initial fetch behind the physically
        // in-flight obsolete refresh instead of overlapping Google requests.
        #expect(await neverHappens { adapter.fetchCallCount > 2 })

        releaseRefresh?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "stale",
                        summary: "Stale connection",
                        start: .timed(Self.gmt(2026, 7, 20, 9)),
                        end: .timed(Self.gmt(2026, 7, 20, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        )

        #expect(await eventually { adapter.fetchCallCount == 3 })
        let weekStart = Self.gmt(2026, 7, 20)
        #expect(
            await eventually {
                model.layout(forWeekStarting: weekStart)?
                    .cells[0].rows.map(\.id) == [canonicalID("new")]
            }
        )
        #expect(
            model.layout(forWeekStarting: weekStart)?
                .cells[0].rows.contains(where: { $0.id == canonicalID("stale") })
                == false
        )
    }

    @Test("A successful empty refresh removes in-range events only")
    func emptyRefreshRemovesInRangeEventsOnly() async {
        let (model, adapter) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: fetchNumber == 1
                    ? [
                        GoogleCalendarEvent(
                            id: "visible",
                            summary: "Visible",
                            start: .timed(Self.gmt(2026, 7, 20, 9)),
                            end: .timed(Self.gmt(2026, 7, 20, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "off-range",
                            summary: "Off range",
                            start: .timed(Self.gmt(2026, 9, 21, 9)),
                            end: .timed(Self.gmt(2026, 9, 21, 10)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                    : []
            )
        }

        model.setConnected(true)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 9, 21)
        ) != nil)

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil
            }
        )
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 9, 21)) != nil
        )
    }

    // MARK: Browsing freshness

    // MARK: Foreground refresh cadence

    @Test("Active cadence starts five minutes after initial fetching completes")
    func activeCadenceStartsAfterInitialCompletion() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        var releaseInitial: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { releaseInitial = $0 }
        }

        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)

        #expect(await eventually { adapter.fetchCallCount == 1 })
        #expect(scheduler.pendingCount == 0)
        releaseInitial?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        )

        #expect(await eventually { scheduler.pendingCount == 1 })
        #expect(scheduler.scheduledDelays == [.seconds(5 * 60)])

        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        }
        scheduler.fireNext()

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await eventually { scheduler.pendingCount == 1 })
    }

    @Test("Slow periodic work starts its next interval only after completion")
    func periodicCadenceIsCompletionRelative() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        var releaseRefresh: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { releaseRefresh = $0 }
        }
        scheduler.fireNext()

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(scheduler.pendingCount == 0)
        #expect(scheduler.scheduledDelays.count == 1)

        releaseRefresh?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        )
        #expect(await eventually { scheduler.pendingCount == 1 })
        #expect(scheduler.scheduledDelays.count == 2)
    }

    @Test("Inactive scenes cancel cadence and reactivate with an immediate refresh")
    func inactivePausesAndForegroundResumesCadence() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        model.setSceneActive(false)
        #expect(scheduler.pendingCount == 0)
        scheduler.fireNext()
        #expect(await neverHappens { adapter.fetchCallCount > 1 })

        model.setSceneActive(true)
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await eventually { scheduler.pendingCount == 1 })
    }

    @Test("Disconnect cancels cadence and reconnect restores it for the visible range")
    func disconnectCancelsAndReconnectRestoresCadence() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        model.setConnected(false)
        #expect(scheduler.pendingCount == 0)
        scheduler.fireNext()

        #expect(await neverHappens { adapter.fetchCallCount > 1 })
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) == nil)

        // The Calendar Screen has not scrolled or changed geometry. Its last
        // visible range still lets the active reconnection establish cadence
        // after the new initial request completes.
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await eventually { scheduler.pendingCount == 1 })
    }

    @Test("A failed periodic refresh retries at the next active interval")
    func failedPeriodicRefreshRetriesAtNextInterval() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 2 {
                return .unavailable(.failed)
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        }
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        scheduler.fireNext()
        #expect(
            await eventually {
                adapter.fetchCallCount == 2
                    && model.status.message == CalendarEventsCopy.refreshFailed
                    && scheduler.pendingCount == 1
            }
        )

        scheduler.fireNext()
        #expect(
            await eventually {
                adapter.fetchCallCount == 3
                    && model.status.message == nil
                    && scheduler.pendingCount == 1
            }
        )
    }

    @Test("A no-overlap cadence decision stays owed and re-arms its interval")
    func noOverlapRefreshRearmsCadence() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        adapter.fetchHandler = { _, _ in .unavailable(.failed) }
        model.showVisibleRange(
            from: Self.gmt(2027, 1, 4),
            through: Self.gmt(2027, 2, 1)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(await eventually { scheduler.pendingCount == 1 })

        let scheduleCount = scheduler.scheduledDelays.count
        scheduler.fireNext()

        #expect(await neverHappens { adapter.fetchCallCount > 2 })
        #expect(scheduler.pendingCount == 1)
        #expect(scheduler.scheduledDelays.count == scheduleCount + 1)

        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        #expect(await eventually { adapter.fetchCallCount == 3 })
    }

    @Test("A slab resets cadence until the slab attempt completes")
    func slabCompletionResetsCadence() async {
        let (model, adapter, scheduler) = makeModelWithScheduler()
        model.setSceneActive(true)
        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        var releaseSlab: CheckedContinuation<GoogleCalendarEventsOutcome, Never>?
        adapter.fetchHandler = { _, _ in
            await withCheckedContinuation { releaseSlab = $0 }
        }
        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )

        #expect(await eventually { adapter.fetchCallCount == 2 })
        #expect(scheduler.pendingCount == 0)
        releaseSlab?.resume(
            returning: .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: []
            )
        )
        #expect(await eventually { scheduler.pendingCount == 1 })
    }

    @Test("Model teardown cancels cadence and connectivity observation")
    func teardownCancelsCadenceAndObservation() async {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let monitor = FakeEventsConnectivityMonitor()
        let scheduler = FakeCalendarEventsCadenceScheduler(now: Self.now)
        var model: CalendarEventsModel? = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: adapter,
            connectivityMonitor: monitor,
            cadenceScheduler: scheduler
        )
        model?.setSceneActive(true)
        model?.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model?.setConnected(true)
        #expect(await eventually { scheduler.pendingCount == 1 })

        weak let weakModel = model
        model = nil

        #expect(weakModel == nil)
        #expect(scheduler.pendingCount == 0)
        #expect(monitor.stopCallCount == 1)
    }

    @Test("Disconnected and release-gated-off models own no cadence")
    func inertModelsOwnNoCadence() {
        let scheduler = FakeCalendarEventsCadenceScheduler(now: Self.now)
        let disconnected = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: FakeGoogleCalendarEventsAdapter(),
            cadenceScheduler: scheduler
        )
        disconnected.setSceneActive(true)
        disconnected.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )

        let gatedOff = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: nil,
            cadenceScheduler: scheduler
        )
        gatedOff.setSceneActive(true)
        gatedOff.setConnected(true)

        #expect(scheduler.pendingCount == 0)
        #expect(scheduler.scheduledDelays.isEmpty)
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

    @Test("Inactive browsing does not refetch an expanded range")
    func inactiveBrowsingDoesNotRefetchExpandedRange() async {
        let (model, adapter) = makeModel()
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })

        // The inactive scene performs no browsing refresh. The same approach
        // and one deep in the expanded window therefore issue no request.
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
                    == ["initial-event", "slab-event"].map { canonicalID($0) }
            }
        )
    }

    @Test("A slab re-delivering a boundary-spanning event keeps one bar per Week Row")
    func boundarySpanningEventKeepsOneBarPerWeek() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            // Google returns every event overlapping the requested range,
            // so an event spanning the initial-window/slab boundary
            // arrives in both responses.
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "spanning-event",
                        summary: "Spanning Event",
                        start: .allDay(year: 2026, month: 10, day: 14),
                        end: .allDay(year: 2026, month: 10, day: 21),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }
        model.setConnected(true)
        #expect(await eventually { adapter.fetchCallCount == 1 })

        // Before the slab, the boundary Week Row holds the event's one
        // segment.
        _ = await layoutEventually(model, weekStart: Self.gmt(2026, 10, 12))
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 10, 12))?
                .bars.map(\.id) == [canonicalID("spanning-event")]
        )

        model.showVisibleRange(
            from: Self.gmt(2026, 8, 31),
            through: Self.gmt(2026, 10, 5)
        )
        #expect(await eventually { adapter.fetchCallCount == 2 })
        // The slab's completion clears the loading status, so a nil
        // message proves the model has processed the slab.
        #expect(await eventually { model.status.message == nil })

        // The re-delivered event must not duplicate: duplicate segment ids
        // break SwiftUI's ForEach identity within the Week Row.
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 10, 12))?
                .bars.map(\.id) == [canonicalID("spanning-event")]
        )
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 10, 19))?
                .bars.map(\.id) == [canonicalID("spanning-event")]
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
        #expect(layout?.cells[2].rows.map(\.id) == ["first", "second", "third", "fourth"].map { canonicalID($0) })
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
        #expect(layout?.cells[2].rows.map(\.id) == ["row-0", "row-1", "row-2"].map { canonicalID($0) })
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
        #expect(layout?.cells[2].rows.map(\.id) == [canonicalID("row-a")])
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
        #expect(layout?.cells[2].rows.map(\.id) == [canonicalID("row-a")])
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
        #expect(layout?.cells[3].rows.map(\.id) == [canonicalID("quiet")])
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

    // MARK: Event Detail Popover payload

    @Test("A bar segment selects canonical detail with the all-day timing line")
    func barSegmentSelectsAllDayDetail() async {
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

        let layout = await layoutEventually(model, weekStart: Self.gmt(2026, 7, 20))
        #expect(layout?.bars.first?.id == canonicalID("holiday"))
        #expect(
            selectedDetail(model, id: canonicalID("holiday"))
                == CalendarEventDetail(
                    title: "Holiday",
                    colorHex: "#039BE5",
                    timingText:
                        "All day · \(Self.fullDateText(Self.gmt(2026, 7, 22)))"
                )
        )
    }

    @Test("An all-day multiday event's timing line spans its inclusive dates")
    func allDayMultidayTimingLine() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "trip",
                        summary: "Trip",
                        start: .allDay(year: 2026, month: 7, day: 22),
                        // Google's exclusive end: the last day is 2026-07-24.
                        end: .allDay(year: 2026, month: 7, day: 25),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(
            selectedDetail(model, id: canonicalID("trip"))?.timingText
                == "All day · \(Self.dayMonthYearText(Self.gmt(2026, 7, 22)))"
                    + " – \(Self.dayMonthYearText(Self.gmt(2026, 7, 24)))"
        )
    }

    @Test("A timed multiday event's timing line carries date and time on both ends")
    func timedMultidayTimingLine() async {
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

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(
            selectedDetail(model, id: canonicalID("hackathon"))?.timingText
                == "\(Self.dayMonthYearText(Self.gmt(2026, 7, 21))), "
                    + "\(Self.timeText(Self.gmt(2026, 7, 21, 22, 0)))"
                    + " – \(Self.dayMonthYearText(Self.gmt(2026, 7, 23))), "
                    + "\(Self.timeText(Self.gmt(2026, 7, 23, 2, 0)))"
        )
    }

    @Test("Every segment of a week-crossing bar carries one canonical identity")
    func weekCrossingBarSegmentsCarryCanonicalIdentity() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "conference",
                        summary: "Conference",
                        start: .allDay(year: 2026, month: 7, day: 24),
                        end: .allDay(year: 2026, month: 7, day: 29),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(model, weekStart: Self.gmt(2026, 7, 27)) != nil)
        let firstWeek = model.layout(forWeekStarting: Self.gmt(2026, 7, 20))
        let secondWeek = model.layout(forWeekStarting: Self.gmt(2026, 7, 27))
        #expect(firstWeek?.bars.first?.id == canonicalID("conference"))
        #expect(secondWeek?.bars.first?.id == canonicalID("conference"))
        #expect(selectedDetail(model, id: canonicalID("conference"))?.title == "Conference")
    }

    @Test("The timing line follows the environment's timezone")
    func timingLineFollowsEnvironmentTimeZone() async {
        // Pacific/Kiritimati is UTC+14: the event is 13:30–14:30 on a
        // single local day there, and the timing line must read so.
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

        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.locale = Locale(identifier: "en_US_POSIX")
        localCalendar.timeZone = kiritimati
        let weekStart = localCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20)
        )!
        let localDate = localCalendar.date(
            from: DateComponents(year: 2026, month: 7, day: 22)
        )!
        let fullDateFormatter = DateFormatter()
        fullDateFormatter.calendar = localCalendar
        fullDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        fullDateFormatter.timeZone = kiritimati
        fullDateFormatter.setLocalizedDateFormatFromTemplate("yMMMEd")

        #expect(await layoutEventually(model, weekStart: weekStart) != nil)
        // Locally Wednesday 13:30–14:30: a row reading the local day and
        // times, never the GMT dates.
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = localCalendar
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = kiritimati
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let timingText = selectedDetail(model, id: canonicalID("island-time"))?.timingText
        #expect(
            timingText
                == fullDateFormatter.string(from: localDate)
                    + " · \(timeFormatter.string(from: Self.gmt(2026, 7, 21, 23, 30)))"
                    + " – \(timeFormatter.string(from: Self.gmt(2026, 7, 22, 0, 30)))"
        )
    }

    @Test("Disconnect on This Device clears event detail together with the events")
    func disconnectClearsEventDetail() async {
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
        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        model.selectEvent(withID: canonicalID("event"))
        #expect(model.selectedEvent != nil)

        model.setConnected(false)

        // Canonical Calendar Events and their identity-based presentation
        // selection clear together (iOS ADRs 0003 and 0005).
        #expect(model.layout(forWeekStarting: Self.gmt(2026, 7, 20)) == nil)
        #expect(model.selectedEvent == nil)
    }

    @Test("An event's detail carries its trimmed location and its Google link")
    func detailCarriesLocationAndGoogleLink() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "review",
                        summary: "Design Review",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        googleLink: "https://www.google.com/calendar/event?eid=abc123",
                        location: "  Studio 4, King Street  "
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let detail = selectedDetail(model, id: canonicalID("review"))
        #expect(detail?.location == "Studio 4, King Street")
        #expect(
            detail?.googleLink
                == "https://www.google.com/calendar/event?eid=abc123"
        )
    }

    @Test("Absent or blank location and Google link stay absent from the detail")
    func absentLocationAndGoogleLinkStayAbsent() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "sparse",
                        summary: "Sparse",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "blank-location",
                        summary: "Blank Location",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        location: "   "
                    ),
                    GoogleCalendarEvent(
                        id: "blank-link",
                        summary: "Blank Link",
                        start: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        googleLink: "  "
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let details = ["sparse", "blank-location", "blank-link"].compactMap {
            selectedDetail(model, id: canonicalID($0))
        }
        // Sparse events stay clean: no Where section, no footer.
        #expect(details.map(\.location) == [nil, nil, nil])
        #expect(details.map(\.googleLink) == [nil, nil, nil])
    }

    @Test("HTML notes render as plain text with tags and entities resolved")
    func htmlNotesRenderAsPlainText() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "picnic",
                        summary: "Picnic",
                        start: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 13, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        notes:
                            "<p>Bring <b>snacks</b> &amp; water.<br>See https://example.com/plan</p>"
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(
            selectedDetail(model, id: canonicalID("picnic"))?.notes
                == "Bring snacks & water.\nSee https://example.com/plan"
        )
    }

    @Test("Plain-text flight notes preserve their authored line breaks")
    func plainTextFlightNotesPreserveLineBreaks() async {
        let (model, adapter) = makeModel()
        let notes = """
            Flight OS 368 (Austrian Airlines)
            Class: Economy (T)
            Baggage: 1PC
            Departure: 20:15
            Arrival: 22:10
            PNR: ONSQLU
            """
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "flight-os-368",
                        summary: "Paris → Vienna (OS 368)",
                        start: .timed(Self.gmt(2026, 7, 22, 20, 15)),
                        end: .timed(Self.gmt(2026, 7, 22, 22, 10)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        notes: notes
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(selectedDetail(model, id: canonicalID("flight-os-368"))?.notes == notes)
    }

    @Test("Compact Event Detail Popovers fill the sheet width")
    func compactEventDetailPopoversFillSheetWidth() {
        #expect(IOSEventDetailPopover.contentMaxWidth(for: .compact) == .infinity)
        #expect(IOSEventDetailPopover.contentMaxWidth(for: .regular) == 360)
    }

    @Test("Compact Event Detail Popovers start at half height and can expand")
    func compactEventDetailPopoversUseAdaptiveDetents() {
        #expect(IOSEventDetailPopover.compactDetents == [.medium, .large])
    }

    @Test("Event dots clear a first-of-month leading rule")
    func eventDotsClearFirstOfMonthLeadingRule() {
        #expect(DateCellView.eventRowsLeadingPadding(hasMonthMarker: false) == 3)
        #expect(DateCellView.eventRowsLeadingPadding(hasMonthMarker: true) == 5)
    }

    @Test("Google's auto-created-event boilerplate is stripped from notes")
    func autoCreatedBoilerplateIsStripped() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "flight",
                        summary: "Flight to Copenhagen",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        notes:
                            "Flight to Copenhagen, CPH arrival 11:05.<br><br>To see detailed information for automatically created events like this one, use the official Google Calendar app. https://g.co/calendar"
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        #expect(
            selectedDetail(model, id: canonicalID("flight"))?.notes
                == "Flight to Copenhagen, CPH arrival 11:05."
        )
    }

    @Test("Absent, blank, or markup-only notes stay absent from the detail")
    func emptyNotesStayAbsent() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "no-notes",
                        summary: "No Notes",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "markup-only",
                        summary: "Markup Only",
                        start: .timed(Self.gmt(2026, 7, 22, 11, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 12, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        notes: "<p><br></p>"
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let notes = ["no-notes", "markup-only"].compactMap {
            selectedDetail(model, id: $0)?.notes
        }
        #expect(notes.isEmpty)
    }

    @Test("Attendees map display-name primary with email fallback and status text")
    func attendeesMapNamesAndStatuses() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "workshop",
                        summary: "Workshop",
                        start: .timed(Self.gmt(2026, 7, 22, 14, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 15, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        attendees: [
                            GoogleCalendarEventAttendee(
                                displayName: "Ada Lovelace",
                                email: "ada@example.com",
                                responseStatus: "accepted"
                            ),
                            // No display name: the email is the label.
                            GoogleCalendarEventAttendee(
                                displayName: nil,
                                email: "grace@example.com",
                                responseStatus: "declined"
                            ),
                            GoogleCalendarEventAttendee(
                                displayName: "  ",
                                email: "alan@example.com",
                                responseStatus: "tentative"
                            ),
                            // Google's needsAction reads as invited.
                            GoogleCalendarEventAttendee(
                                displayName: "Edsger Dijkstra",
                                email: nil,
                                responseStatus: "needsAction"
                            ),
                            // An unrecognized status collapses to unknown.
                            GoogleCalendarEventAttendee(
                                displayName: "Katherine Johnson",
                                email: "katherine@example.com",
                                responseStatus: "maybe"
                            ),
                            // No displayable identity: dropped.
                            GoogleCalendarEventAttendee(
                                displayName: nil,
                                email: nil,
                                responseStatus: "accepted"
                            ),
                        ]
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let detail = selectedDetail(model, id: canonicalID("workshop"))
        #expect(
            detail?.attendees == [
                CalendarEventAttendee(label: "Ada Lovelace", status: .accepted),
                CalendarEventAttendee(label: "grace@example.com", status: .declined),
                CalendarEventAttendee(label: "alan@example.com", status: .tentative),
                CalendarEventAttendee(label: "Edsger Dijkstra", status: .invited),
                CalendarEventAttendee(label: "Katherine Johnson", status: .unknown),
            ]
        )
        #expect(
            detail?.attendees.map(\.status.displayText)
                == ["accepted", "declined", "tentative", "invited", "unknown"]
        )
        #expect(detail?.hiddenAttendeeCount == 0)
    }

    @Test("Six or more attendees cap at five with a hidden count")
    func attendeesCapAtFive() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "all-hands",
                        summary: "All Hands",
                        start: .timed(Self.gmt(2026, 7, 22, 16, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 17, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        attendees: (1...7).map { index in
                            GoogleCalendarEventAttendee(
                                displayName: "Person \(index)",
                                email: "person\(index)@example.com",
                                responseStatus: "accepted"
                            )
                        }
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let detail = selectedDetail(model, id: canonicalID("all-hands"))
        #expect(detail?.attendees.map(\.label) == (1...5).map { "Person \($0)" })
        #expect(detail?.hiddenAttendeeCount == 2)
    }

    @Test("An event without attendees publishes no Attendees section")
    func noAttendeesPublishesNoSection() async {
        let (model, adapter) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "focus",
                        summary: "Focus Time",
                        start: .timed(Self.gmt(2026, 7, 22, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 22, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)

        #expect(await layoutEventually(
            model,
            weekStart: Self.gmt(2026, 7, 20)
        ) != nil)
        let detail = selectedDetail(model, id: canonicalID("focus"))
        #expect(detail?.attendees == [])
        #expect(detail?.hiddenAttendeeCount == 0)
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

    /// The popover timing line's full-date form (weekday, month, day,
    /// year) under the suite's fixed locale and timezone, from the same
    /// formatter discipline the model uses.
    private static func fullDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = makeEnvironment().calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("yMMMEd")
        return formatter.string(from: date)
    }

    /// The popover timing line's month-day-year form under the suite's
    /// fixed locale and timezone.
    private static func dayMonthYearText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = makeEnvironment().calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter.string(from: date)
    }

    /// The localized short time form under the suite's fixed locale and
    /// timezone, from the same template the model uses.
    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = makeEnvironment().calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: date)
    }

    private func makeModel(
        environment: CalendarEnvironment = Self.makeEnvironment()
    ) -> (CalendarEventsModel, FakeGoogleCalendarEventsAdapter) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let model = CalendarEventsModel(
            environment: environment,
            adapter: adapter,
            cadenceScheduler: FakeCalendarEventsCadenceScheduler(
                now: environment.now
            )
        )
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
            connectivityMonitor: monitor,
            cadenceScheduler: FakeCalendarEventsCadenceScheduler(
                now: environment.now
            )
        )
        return (model, adapter, monitor)
    }

    private func makeModelWithScheduler(
        environment: CalendarEnvironment = Self.makeEnvironment()
    ) -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter,
        FakeCalendarEventsCadenceScheduler
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let scheduler = FakeCalendarEventsCadenceScheduler(
            now: environment.now
        )
        let model = CalendarEventsModel(
            environment: environment,
            adapter: adapter,
            cadenceScheduler: scheduler
        )
        return (model, adapter, scheduler)
    }

    private func makeModelWithMonitorAndScheduler(
        environment: CalendarEnvironment = Self.makeEnvironment()
    ) -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter,
        FakeEventsConnectivityMonitor,
        FakeCalendarEventsCadenceScheduler
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let monitor = FakeEventsConnectivityMonitor()
        let scheduler = FakeCalendarEventsCadenceScheduler(
            now: environment.now
        )
        let model = CalendarEventsModel(
            environment: environment,
            adapter: adapter,
            connectivityMonitor: monitor,
            cadenceScheduler: scheduler
        )
        return (model, adapter, monitor, scheduler)
    }

    private func selectedDetail(
        _ model: CalendarEventsModel,
        id: String
    ) -> CalendarEventDetail? {
        model.selectEvent(withID: id)
        return model.selectedEvent?.detail
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
