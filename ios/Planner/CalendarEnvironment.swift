import Foundation

struct CalendarEnvironment: Sendable {
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let timeZone: TimeZone

    init(
        now: Date,
        calendar _: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) {
        var configuredCalendar = Calendar(identifier: .gregorian)
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
            locale: systemLocale,
            timeZone: .autoupdatingCurrent
        )
    }

    private static var systemLocale: Locale {
        let regionalLocale = Locale.autoupdatingCurrent
        let preferredLocale = Locale(
            identifier: Locale.preferredLanguages.first ?? regionalLocale.identifier
        )
        var components = Locale.Components(locale: regionalLocale)
        components.languageComponents.languageCode = preferredLocale.language.languageCode
        components.languageComponents.script = preferredLocale.language.script

        return Locale(components: components)
    }
}
