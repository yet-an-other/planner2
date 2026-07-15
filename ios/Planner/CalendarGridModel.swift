import Foundation
import Observation

struct DateCell: Identifiable, Equatable, Sendable {
    let date: Date
    let dayNumber: Int
    let isToday: Bool

    var id: Date { date }
}

struct WeekRow: Identifiable, Equatable, Sendable {
    let start: Date
    let dateCells: [DateCell]

    var id: Date { start }
}

@MainActor
@Observable
final class CalendarGridModel {
    let today: Date
    let weekRows: [WeekRow]
    let todayWeekIndex: Int
    let todayWeek: WeekRow

    init(environment: CalendarEnvironment) {
        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        let todayWeekStart = startOfMondayWeek(containing: today, calendar: calendar)
        let rangeStart = startOfMondayWeek(
            containing: addYearsClamped(-10, to: today, calendar: calendar),
            calendar: calendar
        )
        let finalWeekStart = startOfMondayWeek(
            containing: addYearsClamped(10, to: today, calendar: calendar),
            calendar: calendar
        )

        var weekRows: [WeekRow] = []
        var cursor = rangeStart
        var todayWeekIndex: Int?

        while cursor <= finalWeekStart {
            if calendar.isDate(cursor, inSameDayAs: todayWeekStart) {
                todayWeekIndex = weekRows.count
            }

            weekRows.append(makeWeekRow(starting: cursor, today: today, calendar: calendar))
            cursor = addDays(7, to: cursor, calendar: calendar)
        }

        guard let todayWeekIndex else {
            preconditionFailure("The Extended Calendar Range must contain Today's Week Row")
        }

        self.today = today
        self.weekRows = weekRows
        self.todayWeekIndex = todayWeekIndex
        self.todayWeek = weekRows[todayWeekIndex]
    }
}

private func startOfMondayWeek(containing date: Date, calendar: Calendar) -> Date {
    let localDate = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: localDate)
    let daysSinceMonday = (weekday - calendar.firstWeekday + 7) % 7
    return addDays(-daysSinceMonday, to: localDate, calendar: calendar)
}

private func addYearsClamped(_ amount: Int, to date: Date, calendar: Calendar) -> Date {
    let source = calendar.dateComponents([.era, .year, .month, .day], from: date)

    guard
        let year = source.year,
        let month = source.month,
        let day = source.day
    else {
        preconditionFailure("The Gregorian Calendar must describe a local date")
    }

    var firstOfTargetMonth = DateComponents()
    firstOfTargetMonth.calendar = calendar
    firstOfTargetMonth.timeZone = calendar.timeZone
    firstOfTargetMonth.era = source.era
    firstOfTargetMonth.year = year + amount
    firstOfTargetMonth.month = month
    firstOfTargetMonth.day = 1

    guard
        let targetMonth = calendar.date(from: firstOfTargetMonth),
        let validDays = calendar.range(of: .day, in: .month, for: targetMonth)
    else {
        preconditionFailure("The Gregorian Calendar must produce the target month")
    }

    var target = firstOfTargetMonth
    target.day = min(day, validDays.count)

    guard let result = calendar.date(from: target) else {
        preconditionFailure("The Gregorian Calendar must produce a clamped year offset")
    }

    return result
}

private func makeWeekRow(starting weekStart: Date, today: Date, calendar: Calendar) -> WeekRow {
    let dateCells = (0..<7).map { offset in
        let date = addDays(offset, to: weekStart, calendar: calendar)
        return DateCell(
            date: date,
            dayNumber: calendar.component(.day, from: date),
            isToday: calendar.isDate(date, inSameDayAs: today)
        )
    }

    return WeekRow(start: weekStart, dateCells: dateCells)
}

private func addDays(_ amount: Int, to date: Date, calendar: Calendar) -> Date {
    guard let result = calendar.date(byAdding: .day, value: amount, to: date) else {
        preconditionFailure("The Gregorian Calendar must add local calendar days")
    }

    return result
}
