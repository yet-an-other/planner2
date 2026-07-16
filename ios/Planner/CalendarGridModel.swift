import Foundation
import Observation

enum CalendarLayoutDirection: Equatable, Sendable {
    case leftToRight
    case rightToLeft
}

struct DateCell: Identifiable, Equatable, Sendable {
    let date: Date
    let dayText: String
    let monthMarker: String?
    let isToday: Bool
    let isWeekend: Bool

    var id: Date { date }
}

struct WeekdayLabel: Identifiable, Equatable, Sendable {
    let weekday: Int
    let text: String
    let isWeekend: Bool

    var id: Int { weekday }
}

struct WeekRow: Identifiable, Equatable, Sendable {
    let start: Date
    let dateCells: [DateCell]

    var id: Date { start }
}

@MainActor
@Observable
final class CalendarGridModel {
    private(set) var today: Date
    private(set) var weekRows: [WeekRow]
    private(set) var todayWeekIndex: Int
    private(set) var todayWeek: WeekRow
    private(set) var weekdayLabels: [WeekdayLabel]
    private(set) var layoutDirection: CalendarLayoutDirection
    private(set) var topWeekStart: WeekRow.ID

    @ObservationIgnored
    private var calendar: Calendar

    @ObservationIgnored
    private var visibleMonthFormatter: DateFormatter

    var visibleMonth: String {
        visibleMonthFormatter.string(from: topWeekStart)
    }

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

        let dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = environment.locale
        dayFormatter.timeZone = environment.timeZone
        dayFormatter.setLocalizedDateFormatFromTemplate("d")

        let monthMarkerFormatter = DateFormatter()
        monthMarkerFormatter.calendar = calendar
        monthMarkerFormatter.locale = environment.locale
        monthMarkerFormatter.timeZone = environment.timeZone
        monthMarkerFormatter.setLocalizedDateFormatFromTemplate("MMM")

        var weekRows: [WeekRow] = []
        var cursor = rangeStart
        var todayWeekIndex: Int?

        while cursor <= finalWeekStart {
            if calendar.isDate(cursor, inSameDayAs: todayWeekStart) {
                todayWeekIndex = weekRows.count
            }

            weekRows.append(
                makeWeekRow(
                    starting: cursor,
                    today: today,
                    calendar: calendar,
                    locale: environment.locale,
                    dayFormatter: dayFormatter,
                    monthMarkerFormatter: monthMarkerFormatter
                )
            )
            cursor = addDays(7, to: cursor, calendar: calendar)
        }

        guard let todayWeekIndex else {
            preconditionFailure("The Extended Calendar Range must contain Today's Week Row")
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.calendar = calendar
        weekdayFormatter.locale = environment.locale
        weekdayFormatter.timeZone = environment.timeZone
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
        let weekdayLabels = weekRows[todayWeekIndex].dateCells.map { dateCell in
            WeekdayLabel(
                weekday: calendar.component(.weekday, from: dateCell.date),
                text: weekdayFormatter
                    .string(from: dateCell.date)
                    .uppercased(with: environment.locale),
                isWeekend: calendar.isDateInWeekend(dateCell.date)
            )
        }

        let visibleMonthFormatter = DateFormatter()
        visibleMonthFormatter.calendar = calendar
        visibleMonthFormatter.locale = environment.locale
        visibleMonthFormatter.timeZone = environment.timeZone
        visibleMonthFormatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")

        self.today = today
        self.weekRows = weekRows
        self.todayWeekIndex = todayWeekIndex
        self.todayWeek = weekRows[todayWeekIndex]
        self.weekdayLabels = weekdayLabels
        self.layoutDirection = environment.locale.language.characterDirection == .rightToLeft
            ? .rightToLeft
            : .leftToRight
        self.topWeekStart = todayWeekStart
        self.calendar = calendar
        self.visibleMonthFormatter = visibleMonthFormatter
    }

    @discardableResult
    func refresh(environment: CalendarEnvironment) -> WeekRow.ID {
        let browsedDateComponents = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: topWeekStart
        )
        let refreshed = CalendarGridModel(environment: environment)
        let preservedDate = refreshed.calendar.date(from: browsedDateComponents)
            .map {
                startOfMondayWeek(containing: $0, calendar: refreshed.calendar)
            }
            ?? refreshed.todayWeek.start
        guard
            let firstWeekStart = refreshed.weekRows.first?.start,
            let lastWeekStart = refreshed.weekRows.last?.start
        else {
            preconditionFailure("The Extended Calendar Range must contain Week Rows")
        }
        let preservedTopWeekStart = min(
            max(preservedDate, firstWeekStart),
            lastWeekStart
        )

        today = refreshed.today
        weekRows = refreshed.weekRows
        todayWeekIndex = refreshed.todayWeekIndex
        todayWeek = refreshed.todayWeek
        weekdayLabels = refreshed.weekdayLabels
        layoutDirection = refreshed.layoutDirection
        calendar = refreshed.calendar
        visibleMonthFormatter = refreshed.visibleMonthFormatter
        topWeekStart = preservedTopWeekStart

        return preservedTopWeekStart
    }

    func showWeek(starting weekStart: WeekRow.ID) {
        topWeekStart = weekStart
    }

    func todayJumpTarget() -> WeekRow.ID? {
        topWeekStart == todayWeek.start ? nil : todayWeek.start
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

private func makeWeekRow(
    starting weekStart: Date,
    today: Date,
    calendar: Calendar,
    locale: Locale,
    dayFormatter: DateFormatter,
    monthMarkerFormatter: DateFormatter
) -> WeekRow {
    let dateCells = (0..<7).map { offset in
        let date = addDays(offset, to: weekStart, calendar: calendar)
        let dayNumber = calendar.component(.day, from: date)
        return DateCell(
            date: date,
            dayText: dayFormatter.string(from: date),
            monthMarker: dayNumber == 1
                ? monthMarkerFormatter.string(from: date).uppercased(with: locale)
                : nil,
            isToday: calendar.isDate(date, inSameDayAs: today),
            isWeekend: calendar.isDateInWeekend(date)
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
