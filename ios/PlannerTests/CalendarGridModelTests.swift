import Foundation
import Testing
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

        model.showWeek(starting: augustWeek.start)

        #expect(model.visibleMonth == "August 2026")
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
}

private func yearMonthDay(of date: Date, calendar: Calendar) -> [Int] {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return [components.year ?? -1, components.month ?? -1, components.day ?? -1]
}
