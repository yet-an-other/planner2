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

    private func makeModel() -> (
        CalendarEventsModel,
        FakeGoogleCalendarEventsAdapter
    ) {
        let adapter = FakeGoogleCalendarEventsAdapter()
        let model = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: adapter
        )
        return (model, adapter)
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        #expect(row.startTimeText == "1:00 PM")
        #expect(row.colorHex == "#039BE5")
    }

    @Test("Bar items carry the Event Color, contrast-safe text, and title")
    func barItemsCarryColorContrastSafeTextAndTitle() async {
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
        let (model, adapter) = makeModel()
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
}
