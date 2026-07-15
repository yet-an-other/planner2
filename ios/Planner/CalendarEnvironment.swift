import Foundation

struct CalendarEnvironment: Sendable {
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    init(
        now: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        var configuredCalendar = calendar
        configuredCalendar.locale = locale
        configuredCalendar.timeZone = timeZone
        configuredCalendar.firstWeekday = 2

        self.now = now
        self.calendar = configuredCalendar
        self.locale = locale
        self.timeZone = timeZone
    }

    static func current(now: Date = .now) -> CalendarEnvironment {
        CalendarEnvironment(
            now: now,
            calendar: Calendar(identifier: .gregorian),
            locale: .autoupdatingCurrent,
            timeZone: .autoupdatingCurrent
        )
    }
}
