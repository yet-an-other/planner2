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
    let todayWeek: WeekRow

    init(environment: CalendarEnvironment) {
        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday - calendar.firstWeekday + 7) % 7

        guard let weekStart = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: today
        ) else {
            preconditionFailure("The Gregorian Calendar must produce a Monday week boundary")
        }

        let dateCells = (0..<7).map { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                preconditionFailure("The Gregorian Calendar must produce seven consecutive dates")
            }

            return DateCell(
                date: date,
                dayNumber: calendar.component(.day, from: date),
                isToday: calendar.isDate(date, inSameDayAs: today)
            )
        }

        self.today = today
        self.todayWeek = WeekRow(start: weekStart, dateCells: dateCells)
    }
}
