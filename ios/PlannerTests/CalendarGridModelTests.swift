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
}
