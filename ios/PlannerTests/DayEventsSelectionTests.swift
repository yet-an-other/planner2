import Foundation
import SwiftUI
import Testing
@testable import Planner

/// The Day Events Popover's model seam (issue #100): the Events Overflow
/// marker summons a selection projecting the Date Cell's complete ordered
/// Calendar Events — visible and hidden alike — from memory-only data.
@Suite("Day Events Selection")
@MainActor
struct DayEventsSelectionTests {
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
        // in the Calendar Events suite; a locale-less calendar follows the
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

    /// The localized start-time text the model's formatter produces, so
    /// expectations never hardcode the locale's day-period separator.
    private static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = makeEnvironment().calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: date)
    }

    private func makeModel() -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter,
        FakeEventsConnectivityMonitor,
        FakeCalendarEventsCadenceScheduler
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let monitor = FakeEventsConnectivityMonitor()
        let scheduler = FakeCalendarEventsCadenceScheduler(
            now: Self.makeEnvironment().now
        )
        let model = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: adapter,
            connectivityMonitor: monitor,
            cadenceScheduler: scheduler
        )
        return (model, adapter, monitor, scheduler)
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

    @Test("The summoned day lists every Calendar Event, not just the visible ones")
    func summonedDayListsEveryEventBeyondTheVisibleCap() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)

        // The visible cap still holds: three rows plus the Events Overflow
        // marker hiding the rest.
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        let cell = model.layout(
            forWeekStarting: Self.gmt(2026, 7, 13)
        )?.cells[2]
        #expect(cell?.rows.count == 3)
        #expect(cell?.overflowCount == 3)

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(
            model.selectedDayEvents?.items.map(\.title)
                == (1...6).map { "Dense \($0)" }
        )
    }

    /// A compact shape summary for order assertions: bars and rows in
    /// list order by title.
    private func shapes(
        _ items: [CalendarEventDayItem]
    ) -> [(shape: String, title: String)] {
        items.map { item in
            switch item {
            case .bar(let bar):
                ("bar", bar.title)
            case .row(let row):
                ("row", row.title)
            }
        }
    }

    @Test("Multiday and all-day bars appear in every crossed day's list")
    func spanningBarsAppearInEveryCrossedDay() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "offsite",
                        summary: "Offsite",
                        start: .allDay(year: 2026, month: 7, day: 14),
                        end: .allDay(year: 2026, month: 7, day: 17),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "hackathon",
                        summary: "Hackathon",
                        start: .timed(Self.gmt(2026, 7, 14, 22, 0)),
                        end: .timed(Self.gmt(2026, 7, 16, 3, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        for day in 14...16 {
            model.selectDayEvents(on: Self.gmt(2026, 7, day))
            #expect(
                model.selectedDayEvents?.items.map(\.title)
                    == ["Offsite", "Hackathon"]
            )
        }
    }

    @Test("Bars hidden beyond the visible cap still list in lane order")
    func capHiddenBarsListInLaneOrder() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...5).map { index in
                    GoogleCalendarEvent(
                        id: "stacked-\(index)",
                        summary: "Stacked \(index)",
                        start: .allDay(year: 2026, month: 7, day: 15),
                        end: .allDay(year: 2026, month: 7, day: 16),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        // Lanes three and four cannot render at true lane positions
        // inside the four-slot cap: they count into the cell's Events
        // Overflow instead.
        #expect(
            model.layout(forWeekStarting: Self.gmt(2026, 7, 13))?
                .cells[2].overflowCount == 2
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(
            model.selectedDayEvents?.items.map(\.title)
                == (1...5).map { "Stacked \($0)" }
        )
    }

    @Test("The list orders bars in lane order, then rows by start time")
    func listOrdersBarsByLaneThenRowsByStartTime() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    // Lane 0: the earliest-starting bar.
                    GoogleCalendarEvent(
                        id: "week",
                        summary: "Week Bar",
                        start: .allDay(year: 2026, month: 7, day: 13),
                        end: .allDay(year: 2026, month: 7, day: 18),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Lane 1 under it, crossing Wednesday.
                    GoogleCalendarEvent(
                        id: "mid",
                        summary: "Mid Bar",
                        start: .allDay(year: 2026, month: 7, day: 14),
                        end: .allDay(year: 2026, month: 7, day: 16),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Lane 2 on Wednesday alone.
                    GoogleCalendarEvent(
                        id: "day",
                        summary: "Day Bar",
                        start: .allDay(year: 2026, month: 7, day: 15),
                        end: .allDay(year: 2026, month: 7, day: 16),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "afternoon",
                        summary: "Afternoon Row",
                        start: .timed(Self.gmt(2026, 7, 15, 14, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 15, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "morning",
                        summary: "Morning Row",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(
            shapes(model.selectedDayEvents?.items ?? []).map(\.0)
                == ["bar", "bar", "bar", "row", "row"]
        )
        #expect(
            model.selectedDayEvents?.items.map(\.title)
                == [
                    "Week Bar", "Mid Bar", "Day Bar",
                    "Morning Row", "Afternoon Row",
                ]
        )
    }

    @Test("A date heading names the Date Cell")
    func headingNamesTheDateCell() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(model.selectedDayEvents?.heading == "Wednesday, July 15")
        #expect(model.selectedDayEvents?.date == Self.gmt(2026, 7, 15))
    }

    @Test("Row items carry the dot color, localized start time, and title")
    func rowItemsCarryDotStartTimeAndTitle() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "review",
                        summary: "Design Review",
                        start: .timed(Self.gmt(2026, 7, 15, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        guard case .row(let row) = model.selectedDayEvents?.items.first else {
            Issue.record("Expected a Calendar Event Row item")
            return
        }
        #expect(row.title == "Design Review")
        #expect(row.startTimeText == Self.timeText(Self.gmt(2026, 7, 15, 13, 0)))
        #expect(row.colorHex == "#039BE5")
    }

    @Test("Bar items carry the Event Color, contrast-safe text, and title")
    func barItemsCarryColorContrastSafeTextAndTitle() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "offsite",
                        summary: "Offsite",
                        start: .allDay(year: 2026, month: 7, day: 15),
                        end: .allDay(year: 2026, month: 7, day: 16),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        guard case .bar(let bar) = model.selectedDayEvents?.items.first else {
            Issue.record("Expected a Calendar Event Bar item")
            return
        }
        #expect(bar.title == "Offsite")
        #expect(bar.colorHex == "#039BE5")
        #expect(
            bar.textTone
                == CalendarEventsModel.textTone(forHexColor: "#039BE5")
        )
    }

    @Test("Summoning the day opens from memory with no network call")
    func summoningMakesNoNetworkCall() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        let fetchCountAfterLoading = adapter.fetchCallCount

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(model.selectedDayEvents != nil)
        #expect(adapter.fetchCallCount == fetchCountAfterLoading)
    }

    @Test("Compact Day Events Popovers fill the sheet width")
    func compactDayEventsPopoversFillSheetWidth() {
        #expect(IOSDayEventsPopover.contentMaxWidth(for: .compact) == .infinity)
        #expect(IOSDayEventsPopover.contentMaxWidth(for: .regular) == 360)
    }

    @Test("Compact Day Events Popovers start at half height and can expand")
    func compactDayEventsPopoversUseAdaptiveDetents() {
        #expect(IOSDayEventsPopover.compactDetents == [.medium, .large])
    }

    @Test("Dismissal and Disconnect on This Device clear the summoned day")
    func dismissalAndDisconnectClearTheSummonedDay() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents != nil)
        model.dismissDayEvents()
        #expect(model.selectedDayEvents == nil)

        // Disconnect on This Device clears the selection with the
        // memory-only events themselves.
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents != nil)
        model.setConnected(false)
        #expect(model.selectedDayEvents == nil)
    }

    @Test("An open Day Events Popover follows edits and moves across a refresh")
    func openDayFollowsEditsAndMovesAcrossRefresh() async {
        let (model, adapter, _, _) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "offsite",
                            summary: "Offsite",
                            start: .allDay(year: 2026, month: 7, day: 15),
                            end: .allDay(year: 2026, month: 7, day: 16),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "standup",
                            summary: "Standup",
                            start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                            end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "review",
                            summary: "Design Review",
                            start: .timed(Self.gmt(2026, 7, 15, 13, 0)),
                            end: .timed(Self.gmt(2026, 7, 15, 14, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    // Edited in place: new title and explicit Event Color.
                    GoogleCalendarEvent(
                        id: "offsite",
                        summary: "Team Offsite",
                        colorId: "updated-color",
                        start: .allDay(year: 2026, month: 7, day: 15),
                        end: .allDay(year: 2026, month: 7, day: 16),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Daily Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 45)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Moved within the refreshed range, out of the open
                    // day: it leaves the day's list.
                    GoogleCalendarEvent(
                        id: "review",
                        summary: "Design Review",
                        start: .timed(Self.gmt(2026, 7, 16, 13, 0)),
                        end: .timed(Self.gmt(2026, 7, 16, 14, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    // Added into the open day.
                    GoogleCalendarEvent(
                        id: "demo",
                        summary: "Demo",
                        start: .timed(Self.gmt(2026, 7, 15, 16, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 17, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                ],
                eventColorBackgrounds: ["updated-color": "#D50000"]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(
            model.selectedDayEvents?.items.map(\.title)
                == ["Offsite", "Standup", "Design Review"]
        )

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.selectedDayEvents?.items.map(\.title)
                    == ["Team Offsite", "Daily Standup", "Demo"]
            }
        )
        // The edited bar's Event Color and the edited row's start time
        // update in place with the same successful replacement.
        guard case .bar(let bar) = model.selectedDayEvents?.items.first,
              case .row(let row) = model.selectedDayEvents?.items[1]
        else {
            Issue.record("Expected the reconciled bar and row items")
            return
        }
        #expect(bar.colorHex == "#D50000")
        #expect(row.startTimeText == Self.timeText(Self.gmt(2026, 7, 15, 9, 45)))
    }

    @Test("Deleted and declined events leave the open day's list")
    func deletedAndDeclinedEventsLeaveTheOpenDay() async {
        let (model, adapter, _, _) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "standup",
                            summary: "Standup",
                            start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                            end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "review",
                            summary: "Design Review",
                            start: .timed(Self.gmt(2026, 7, 15, 13, 0)),
                            end: .timed(Self.gmt(2026, 7, 15, 14, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                        GoogleCalendarEvent(
                            id: "sync",
                            summary: "Sync",
                            start: .timed(Self.gmt(2026, 7, 15, 15, 0)),
                            end: .timed(Self.gmt(2026, 7, 15, 16, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            // "review" is deleted (absent from the aggregate) and "sync"
            // now arrives declined: both leave the open list.
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: [
                    GoogleCalendarEvent(
                        id: "standup",
                        summary: "Standup",
                        start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                        end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    ),
                    GoogleCalendarEvent(
                        id: "sync",
                        summary: "Sync",
                        start: .timed(Self.gmt(2026, 7, 15, 15, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 16, 0)),
                        isCancelled: false,
                        isDeclinedByViewer: true
                    ),
                ]
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents?.items.count == 3)

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(
            await eventually {
                model.selectedDayEvents?.items.map(\.title) == ["Standup"]
            }
        )
    }

    @Test("The popover dismisses itself when the day's last event disappears")
    func popoverDismissesItselfWhenTheDayEmpties() async {
        let (model, adapter, _, _) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            return .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: fetchNumber == 1
                    ? [
                        GoogleCalendarEvent(
                            id: "standup",
                            summary: "Standup",
                            start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                            end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                    : []
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents != nil)

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        #expect(await eventually { model.selectedDayEvents == nil })
    }

    @Test("A failed refresh leaves the open day's list unchanged")
    func failedRefreshLeavesTheOpenDayUnchanged() async {
        let (model, adapter, _, _) = makeModel()
        var fetchNumber = 0
        adapter.fetchHandler = { _, _ in
            fetchNumber += 1
            if fetchNumber == 1 {
                return .success(
                    calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                    events: [
                        GoogleCalendarEvent(
                            id: "standup",
                            summary: "Standup",
                            start: .timed(Self.gmt(2026, 7, 15, 9, 30)),
                            end: .timed(Self.gmt(2026, 7, 15, 10, 0)),
                            isCancelled: false,
                            isDeclinedByViewer: false
                        ),
                    ]
                )
            }
            return .unavailable(.failed)
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents?.items.map(\.title) == ["Standup"])

        model.showVisibleRange(
            from: Self.gmt(2026, 7, 13),
            through: Self.gmt(2026, 7, 27)
        )
        model.refreshOnForeground()

        // The failed refresh completes without touching the open list.
        #expect(
            await eventually {
                model.status.message == CalendarEventsCopy.refreshFailed
            }
        )
        #expect(model.selectedDayEvents?.items.map(\.title) == ["Standup"])
    }

    @Test("Selecting a day-list item summons its Event Detail and closes the day list")
    func dayListItemDrillsThroughToEventDetail() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents?.items.count == 6)

        // The drill-through trigger: a cap-hidden item summons its Event
        // Detail Popover as the Day Events Popover closes.
        model.selectEvent(withID: canonicalID("dense-5"))

        #expect(model.selectedEvent?.id == canonicalID("dense-5"))
        #expect(model.selectedEvent?.detail.title == "Dense 5")
        #expect(model.selectedDayEvents == nil)
    }

    @Test("Summoning the day list closes an open Event Detail Popover")
    func summoningDayListClosesEventDetail() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        // Summoning the Event Detail Popover from a visible Calendar
        // Event Row, then tapping "+N more".
        model.selectEvent(withID: canonicalID("dense-1"))
        #expect(model.selectedEvent != nil)

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))

        #expect(model.selectedEvent == nil)
        #expect(model.selectedDayEvents?.items.count == 6)
    }

    @Test("At most one overlay is selected at a time and the day list re-opens")
    func overlaysAreMutuallyExclusiveAndTheDayListReopens() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )

        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents != nil && model.selectedEvent == nil)

        model.selectEvent(withID: canonicalID("dense-2"))
        #expect(model.selectedEvent != nil && model.selectedDayEvents == nil)

        // After the detail closes, the day list re-opens via "+N more".
        model.dismissEventDetail()
        model.selectDayEvents(on: Self.gmt(2026, 7, 15))
        #expect(model.selectedDayEvents?.items.count == 6)
        #expect(model.selectedEvent == nil)
    }

    @Test("A cap-hidden selected event is attributed to its Date Cell's day")
    func capHiddenSelectedEventIsAttributedToItsDay() async {
        let (model, adapter, _, _) = makeModel()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }

        model.setConnected(true)
        #expect(
            await eventually {
                model.layout(forWeekStarting: Self.gmt(2026, 7, 13)) != nil
            }
        )
        #expect(model.selectedEventIsAttributed(toDay: Self.gmt(2026, 7, 15)) == false)

        // "dense-5" is beyond the visible cap: it has no visible Calendar
        // Event Row to anchor its Event Detail Popover, so the marker of
        // its Date Cell anchors instead.
        model.selectEvent(withID: canonicalID("dense-5"))

        #expect(model.selectedEventIsAttributed(toDay: Self.gmt(2026, 7, 15)))
        #expect(model.selectedEventIsAttributed(toDay: Self.gmt(2026, 7, 16)) == false)
    }

    @Test("Both overlays share the compact and regular presentation policy")
    func overlaysSharePresentationPolicy() {
        #expect(IOSDayEventsPopover.compactDetents == IOSEventDetailPopover.compactDetents)
        #expect(
            IOSDayEventsPopover.contentMaxWidth(for: .compact)
                == IOSEventDetailPopover.contentMaxWidth(for: .compact)
        )
        #expect(
            IOSDayEventsPopover.contentMaxWidth(for: .regular)
                == IOSEventDetailPopover.contentMaxWidth(for: .regular)
        )
    }
}
