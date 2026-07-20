import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Planner

@Suite("Calendar Grid")
@MainActor
struct CalendarGridModelTests {
    @Test("A fixed Today produces its Monday-through-Sunday Week Row")
    func fixedTodayProducesMondayThroughSundayWeekRow() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let environment = CalendarEnvironment(
            now: now,
            calendar: calendar,
            locale: calendar.locale ?? Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )

        let model = CalendarGridModel(environment: environment)

        let localDates = model.todayWeek.dateCells.map { dateCell in
            calendar.dateComponents([.year, .month, .day, .weekday], from: dateCell.date)
        }

        #expect(localDates.map(\.year) == Array(repeating: 2026, count: 7))
        #expect(localDates.map(\.month) == Array(repeating: 7, count: 7))
        #expect(localDates.map(\.day) == [13, 14, 15, 16, 17, 18, 19])
        #expect(localDates.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(model.todayWeek.dateCells.map(\.isToday) == [false, false, true, false, false, false, false])
    }

    @Test("The Extended Calendar Range contains complete boundary Week Rows and Today")
    func extendedCalendarRangeContainsBoundariesAndToday() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(model.weekRows.count == 1_045)
        #expect(model.todayWeekIndex == 522)
        #expect(yearMonthDay(of: try #require(model.weekRows.first?.start), calendar: calendar) == [2016, 7, 11])
        #expect(yearMonthDay(of: try #require(model.weekRows.last?.start), calendar: calendar) == [2036, 7, 14])
        #expect(yearMonthDay(of: model.todayWeek.start, calendar: calendar) == [2026, 7, 13])
        #expect(model.weekRows[model.todayWeekIndex] == model.todayWeek)
    }

    @Test("February 29 clamps ten-year endpoints to February 28")
    func leapDayClampsExtendedCalendarRangeEndpoints() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2024,
                    month: 2,
                    day: 29,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(yearMonthDay(of: try #require(model.weekRows.first?.start), calendar: calendar) == [2014, 2, 24])
        #expect(yearMonthDay(of: try #require(model.weekRows.last?.start), calendar: calendar) == [2034, 2, 27])
        #expect(
            yearMonthDay(
                of: try #require(model.weekRows.last?.dateCells.last?.date),
                calendar: calendar
            ) == [2034, 3, 5]
        )
    }

    @Test("Date Cells remain consecutive across calendar and daylight-saving boundaries")
    func dateCellsRemainConsecutiveAcrossBoundaries() throws {
        let timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 3,
                    day: 8,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let dateCells = model.weekRows.flatMap(\.dateCells)
        let localDates = dateCells.map { yearMonthDay(of: $0.date, calendar: calendar) }
        let elapsedHours = zip(dateCells, dateCells.dropFirst()).map { earlier, later in
            Int(later.date.timeIntervalSince(earlier.date) / 3_600)
        }
        let calendarDaySteps = zip(dateCells, dateCells.dropFirst()).map { earlier, later in
            calendar.dateComponents([.day], from: earlier.date, to: later.date).day
        }

        #expect(model.weekRows.allSatisfy { $0.dateCells.count == 7 })
        #expect(model.weekRows.allSatisfy {
            calendar.component(.weekday, from: $0.start) == 2
        })
        #expect(Set(localDates.map { $0.map(String.init).joined(separator: "-") }).count == dateCells.count)
        #expect(calendarDaySteps.allSatisfy { $0 == 1 })
        #expect(elapsedHours.contains(23))
        #expect(elapsedHours.contains(25))
    }

    @Test("Visible Month follows the topmost Week Row")
    func visibleMonthFollowsTopmostWeekRow() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let augustWeek = try #require(model.weekRows.first {
            yearMonthDay(of: $0.start, calendar: calendar) == [2026, 8, 3]
        })

        #expect(model.visibleMonth == "July 2026")
        #expect(model.shortVisibleMonth == "JUL 2026")

        model.showWeek(starting: augustWeek.start)

        #expect(model.visibleMonth == "August 2026")
        #expect(model.shortVisibleMonth == "AUG 2026")
    }

    @Test("Visible Month uses the Monday of Today's Week Row at a year boundary")
    func visibleMonthUsesMondayAtYearBoundary() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2023,
                    month: 1,
                    day: 1,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(yearMonthDay(of: model.topWeekStart, calendar: calendar) == [2022, 12, 26])
        #expect(model.visibleMonth == "December 2022")
    }

    @Test("Today Jump targets Today's Week Row and is a no-op when already there")
    func todayJumpTargetsTodayAndAvoidsUnnecessaryMovement() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let augustWeek = try #require(model.weekRows.first {
            yearMonthDay(of: $0.start, calendar: calendar) == [2026, 8, 3]
        })

        #expect(model.todayJumpTarget() == nil)

        model.showWeek(starting: augustWeek.start)

        let target = try #require(model.todayJumpTarget())
        #expect(target == model.todayWeek.start)
        #expect(model.topWeekStart == augustWeek.start)

        model.showWeek(starting: target)

        #expect(model.todayJumpTarget() == nil)
    }

    @Test("Calendar text follows the supplied locale")
    func calendarTextFollowsSuppliedLocale() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "es_ES")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let firstOfJuly = try #require(model.weekRows.flatMap(\.dateCells).first {
            yearMonthDay(of: $0.date, calendar: calendar) == [2026, 7, 1]
        })

        #expect(model.visibleMonth == "julio de 2026")
        #expect(model.shortVisibleMonth == "JUL 2026")
        #expect(model.weekdayLabels.map(\.text) == ["LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB", "DOM"])
        #expect(model.todayWeek.dateCells[2].dayText == "15")
        #expect(firstOfJuly.monthMarker == "JUL")
    }

    @Test("Calendar semantics stay Gregorian when another calendar is preferred")
    func calendarSemanticsStayGregorian() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "es_ES")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.locale = locale
        gregorian.timeZone = timeZone
        let now = try #require(
            gregorian.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: Calendar(identifier: .buddhist),
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(yearMonthDay(of: model.today, calendar: gregorian) == [2026, 7, 15])
        #expect(model.visibleMonth == "julio de 2026")
        #expect(model.todayWeek.dateCells.map {
            gregorian.component(.weekday, from: $0.date)
        } == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("Right-to-left locale keeps Monday first at the leading edge and classifies its weekend")
    func rightToLeftLocaleKeepsMondayFirstAndClassifiesWeekend() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "ar_SA")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 7,
                    day: 15,
                    hour: 12
                )
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(model.layoutDirection == .rightToLeft)
        #expect(model.weekdayLabels.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(model.weekdayLabels.map(\.text) == [
            "اثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت", "أحد"
        ])
        #expect(model.weekdayLabels.map(\.isWeekend) == [false, false, false, false, true, true, false])
        #expect(model.todayWeek.dateCells.map(\.isWeekend) == [false, false, false, false, true, true, false])
        #expect(model.todayWeek.dateCells[2].dayText == "١٥")
    }

    @Test("Foreground and midnight refreshes preserve a browsed Week Row")
    func foregroundAndMidnightRefreshesPreserveBrowsedWeekRow() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let initialNow = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
            )
        )
        let refreshedNow = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 16, hour: 1)
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: initialNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let augustWeek = try #require(model.weekRows.first {
            yearMonthDay(of: $0.start, calendar: calendar) == [2026, 8, 3]
        })
        model.showWeek(starting: augustWeek.start)
        let initialEnvironment = CalendarEnvironment(
            now: initialNow,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        let foregroundScrollTarget = model.refresh(environment: initialEnvironment)

        #expect(yearMonthDay(of: foregroundScrollTarget, calendar: calendar) == [2026, 8, 3])
        #expect(yearMonthDay(of: model.today, calendar: calendar) == [2026, 7, 15])

        let scrollTarget = model.refresh(
            environment: CalendarEnvironment(
                now: refreshedNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(yearMonthDay(of: model.today, calendar: calendar) == [2026, 7, 16])
        #expect(yearMonthDay(of: model.topWeekStart, calendar: calendar) == [2026, 8, 3])
        #expect(yearMonthDay(of: scrollTarget, calendar: calendar) == [2026, 8, 3])
        #expect(model.visibleMonth == "August 2026")
        #expect(model.todayWeek.dateCells.map(\.isToday) == [false, false, false, true, false, false, false])
        #expect(model.todayJumpTarget() == model.todayWeek.start)
    }

    @Test("Midnight into a new week updates Today without moving the topmost Week Row")
    func midnightIntoNewWeekUpdatesTodayWithoutMovingTopmostWeekRow() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let sunday = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 19, hour: 23)
            )
        )
        let monday = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 20, hour: 1)
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: sunday,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let originalTopWeekStart = model.topWeekStart

        let scrollTarget = model.refresh(
            environment: CalendarEnvironment(
                now: monday,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )

        #expect(yearMonthDay(of: model.today, calendar: calendar) == [2026, 7, 20])
        #expect(model.topWeekStart == originalTopWeekStart)
        #expect(scrollTarget == originalTopWeekStart)
        #expect(yearMonthDay(of: model.todayWeek.start, calendar: calendar) == [2026, 7, 20])
        #expect(model.todayWeek.dateCells.map(\.isToday) == [true, false, false, false, false, false, false])
        #expect(model.todayJumpTarget() == model.todayWeek.start)
    }

    @Test("Timezone and locale refreshes preserve the browsed civil Week Row")
    func timezoneAndLocaleRefreshesPreserveBrowsedCivilWeekRow() throws {
        let initialTimeZone = try #require(TimeZone(secondsFromGMT: 0))
        let refreshedTimeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let initialLocale = Locale(identifier: "en_US_POSIX")
        let refreshedLocale = Locale(identifier: "ar_SA")
        var initialCalendar = Calendar(identifier: .gregorian)
        initialCalendar.locale = initialLocale
        initialCalendar.timeZone = initialTimeZone
        let now = try #require(
            initialCalendar.date(
                from: DateComponents(year: 2026, month: 7, day: 15, hour: 1)
            )
        )
        let model = CalendarGridModel(
            environment: CalendarEnvironment(
                now: now,
                calendar: initialCalendar,
                locale: initialLocale,
                timeZone: initialTimeZone
            )
        )
        let augustWeek = try #require(model.weekRows.first {
            yearMonthDay(of: $0.start, calendar: initialCalendar) == [2026, 8, 3]
        })
        model.showWeek(starting: augustWeek.start)

        let scrollTarget = model.refresh(
            environment: CalendarEnvironment(
                now: now,
                calendar: Calendar(identifier: .gregorian),
                locale: refreshedLocale,
                timeZone: refreshedTimeZone
            )
        )
        var refreshedCalendar = Calendar(identifier: .gregorian)
        refreshedCalendar.locale = refreshedLocale
        refreshedCalendar.timeZone = refreshedTimeZone

        #expect(yearMonthDay(of: model.today, calendar: refreshedCalendar) == [2026, 7, 14])
        #expect(yearMonthDay(of: model.topWeekStart, calendar: refreshedCalendar) == [2026, 8, 3])
        #expect(yearMonthDay(of: scrollTarget, calendar: refreshedCalendar) == [2026, 8, 3])
        #expect(model.visibleMonth == "أغسطس، ٢٠٢٦ م")
        #expect(model.layoutDirection == .rightToLeft)
        #expect(model.weekdayLabels.map(\.isWeekend) == [false, false, false, false, true, true, false])
        #expect(model.todayWeek.dateCells.map(\.isToday) == [false, true, false, false, false, false, false])
        #expect(model.todayWeek.dateCells[1].dayText == "١٤")
    }

    @Test("Extended Calendar Range refreshes preserve browsing at both valid edges")
    func extendedCalendarRangeRefreshesPreserveBrowsingAtValidEdges() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let initialNow = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
            )
        )
        let refreshedNow = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)
            )
        )
        let initialEnvironment = CalendarEnvironment(
            now: initialNow,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let refreshedEnvironment = CalendarEnvironment(
            now: refreshedNow,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )
        let lowerEdgeModel = CalendarGridModel(environment: initialEnvironment)
        let initialFirstWeek = try #require(lowerEdgeModel.weekRows.first)
        lowerEdgeModel.showWeek(starting: initialFirstWeek.start)

        let lowerScrollTarget = lowerEdgeModel.refresh(environment: refreshedEnvironment)

        #expect(lowerScrollTarget == initialFirstWeek.start)
        #expect(lowerEdgeModel.topWeekStart == initialFirstWeek.start)

        let upperEdgeModel = CalendarGridModel(environment: initialEnvironment)
        let initialLastWeek = try #require(upperEdgeModel.weekRows.last)
        upperEdgeModel.showWeek(starting: initialLastWeek.start)

        let upperScrollTarget = upperEdgeModel.refresh(environment: refreshedEnvironment)

        #expect(upperScrollTarget == initialLastWeek.start)
        #expect(upperEdgeModel.topWeekStart == initialLastWeek.start)
    }

    @Test("Extended Calendar Range shifts clamp browsing to the nearest edge")
    func extendedCalendarRangeShiftsClampBrowsingToNearestEdge() throws {
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US_POSIX")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let initialNow = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
            )
        )
        let laterNow = try #require(
            calendar.date(
                from: DateComponents(year: 2028, month: 7, day: 15, hour: 12)
            )
        )
        let earlierNow = try #require(
            calendar.date(
                from: DateComponents(year: 2024, month: 7, day: 15, hour: 12)
            )
        )
        let lowerEdgeModel = CalendarGridModel(
            environment: CalendarEnvironment(
                now: initialNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let initialFirstWeek = try #require(lowerEdgeModel.weekRows.first)
        lowerEdgeModel.showWeek(starting: initialFirstWeek.start)

        let lowerScrollTarget = lowerEdgeModel.refresh(
            environment: CalendarEnvironment(
                now: laterNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let refreshedFirstWeek = try #require(lowerEdgeModel.weekRows.first)

        #expect(lowerScrollTarget == refreshedFirstWeek.start)
        #expect(lowerEdgeModel.topWeekStart == refreshedFirstWeek.start)
        #expect(yearMonthDay(of: refreshedFirstWeek.start, calendar: calendar) == [2018, 7, 9])
        #expect(lowerEdgeModel.visibleMonth == "July 2018")
        #expect(lowerEdgeModel.todayJumpTarget() == lowerEdgeModel.todayWeek.start)

        let upperEdgeModel = CalendarGridModel(
            environment: CalendarEnvironment(
                now: initialNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let initialLastWeek = try #require(upperEdgeModel.weekRows.last)
        upperEdgeModel.showWeek(starting: initialLastWeek.start)

        let upperScrollTarget = upperEdgeModel.refresh(
            environment: CalendarEnvironment(
                now: earlierNow,
                calendar: calendar,
                locale: locale,
                timeZone: timeZone
            )
        )
        let refreshedLastWeek = try #require(upperEdgeModel.weekRows.last)

        #expect(upperScrollTarget == refreshedLastWeek.start)
        #expect(upperEdgeModel.topWeekStart == refreshedLastWeek.start)
        #expect(yearMonthDay(of: refreshedLastWeek.start, calendar: calendar) == [2034, 7, 10])
        #expect(upperEdgeModel.visibleMonth == "July 2034")
        #expect(upperEdgeModel.todayJumpTarget() == upperEdgeModel.todayWeek.start)
    }

    @Test("Month Marker and compact date numeral share one Date Cell row")
    func monthMarkerAndCompactDateNumeralShareOneRow() throws {
        let renderer = ImageRenderer(
            content: DateCellView(
                dateCell: DateCell(
                    date: Date(timeIntervalSince1970: 0),
                    dayText: "1",
                    monthMarker: "AUG",
                    isToday: false,
                    isWeekend: false
                )
            )
            .frame(width: 53, height: 96)
            .environment(\.layoutDirection, .leftToRight)
        )
        renderer.scale = 3
        let image = try #require(renderer.uiImage?.cgImage)
        let dayBounds = try #require(
            pixelBounds(in: image, matching: (29, 33, 18))
        )
        let monthBounds = try #require(
            pixelBounds(in: image, matching: (111, 114, 90))
        )

        #expect(abs(dayBounds.midY - monthBounds.midY) <= 12)
        #expect(dayBounds.height <= monthBounds.height + 3)
        #expect(monthBounds.width >= 40)

        let compactRTLRenderer = ImageRenderer(
            content: DateCellView(
                dateCell: DateCell(
                    date: Date(timeIntervalSince1970: 0),
                    dayText: "١",
                    monthMarker: "أغسطس",
                    isToday: false,
                    isWeekend: false
                )
            )
            .frame(width: 45, height: 96)
            .environment(\.layoutDirection, .rightToLeft)
        )
        compactRTLRenderer.scale = 3
        let compactRTLImage = try #require(compactRTLRenderer.uiImage?.cgImage)
        let compactRTLDayBounds = try #require(
            pixelBounds(in: compactRTLImage, matching: (29, 33, 18))
        )
        let compactRTLMonthBounds = try #require(
            pixelBounds(in: compactRTLImage, matching: (111, 114, 90))
        )

        #expect(abs(compactRTLDayBounds.midY - compactRTLMonthBounds.midY) <= 12)
        #expect(compactRTLDayBounds.height <= compactRTLMonthBounds.height + 3)
        #expect(compactRTLMonthBounds.width >= 40)
    }

    @Test("The same date environment produces the same Calendar Grid")
    func sameDateEnvironmentProducesSameCalendarGrid() throws {
        let timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let locale = Locale(identifier: "fr_FR")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let now = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 10, day: 25, hour: 12)
            )
        )
        let environment = CalendarEnvironment(
            now: now,
            calendar: calendar,
            locale: locale,
            timeZone: timeZone
        )

        let first = CalendarGridModel(environment: environment)
        let second = CalendarGridModel(environment: environment)

        #expect(first.today == second.today)
        #expect(first.weekRows == second.weekRows)
        #expect(first.todayWeekIndex == second.todayWeekIndex)
        #expect(first.todayWeek == second.todayWeek)
        #expect(first.weekdayLabels == second.weekdayLabels)
        #expect(first.layoutDirection == second.layoutDirection)
        #expect(first.topWeekStart == second.topWeekStart)
        #expect(first.visibleMonth == second.visibleMonth)
        #expect(first.todayJumpTarget() == second.todayJumpTarget())
    }
}

private func pixelBounds(
    in image: CGImage,
    matching target: (red: UInt8, green: UInt8, blue: UInt8)
) -> CGRect? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1
    let tolerance = 12

    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            let red = Int(pixels[offset])
            let green = Int(pixels[offset + 1])
            let blue = Int(pixels[offset + 2])
            guard abs(red - Int(target.red)) <= tolerance,
                  abs(green - Int(target.green)) <= tolerance,
                  abs(blue - Int(target.blue)) <= tolerance else {
                continue
            }
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return nil
    }
    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
}

private func yearMonthDay(of date: Date, calendar: Calendar) -> [Int] {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return [components.year ?? -1, components.month ?? -1, components.day ?? -1]
}
