import Foundation

/// The Event Detail Popover's presentation payload for one Calendar Event
/// (Planning glossary). The published layout items — Calendar Event Bar
/// segments and Calendar Event Row items — carry it, so the popover
/// renders entirely from model-published state and Disconnect on This
/// Device dismisses an open popover as a consequence of clearing events
/// (iOS ADR 0005). Every field is memory-only (iOS ADR 0003).
struct CalendarEventDetail: Equatable, Sendable {
    let title: String
    /// The Event Color as a `#RRGGBB` hex string.
    let colorHex: String
    /// The localized timing line, computed at normalization with the
    /// environment's locale and timezone: "All day · date" for a single
    /// all-day event, "All day · start – end" for a multiday one, and
    /// "date · start – end" for a timed one.
    let timingText: String
    /// The event's location, trimmed, or `nil` when Google provides none
    /// or a blank one — the Where section is omitted rather than shown
    /// empty.
    let location: String?
    /// Google's link to the event in Google Calendar, or `nil` when
    /// Google provides none — the footer is omitted rather than shown
    /// empty.
    let googleLink: String?

    init(
        title: String,
        colorHex: String,
        timingText: String,
        location: String? = nil,
        googleLink: String? = nil
    ) {
        self.title = title
        self.colorHex = colorHex
        self.timingText = timingText
        self.location = location
        self.googleLink = googleLink
    }
}

/// One event's display timing in Planner's uniform shape, so the timing
/// line never branches on the bar/row classification.
struct CalendarEventTiming: Equatable, Sendable {
    /// The start instant for a timed event, the start-of-day for an
    /// all-day one.
    let start: Date
    /// The end instant for a timed event, the inclusive last day's
    /// start-of-day for an all-day one.
    let end: Date
    /// The event carries no time component.
    let isAllDay: Bool
    /// The event spans more than one local date.
    let isMultiday: Bool
}

/// The Event Detail Popover's timing line, computed with the
/// environment's locale and timezone — the same discipline as the
/// Calendar Event Row start time. All-day shapes read "All day · …" with
/// Planner's English-only copy; a timed multiday event carries its date
/// and time on both ends, matching the Web Experience's popover.
enum CalendarEventTimingLine {
    static func timingLine(
        for timing: CalendarEventTiming,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        if timing.isAllDay, !timing.isMultiday {
            return "\(CalendarEventsCopy.allDay) · "
                + fullDate(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
        }
        if timing.isAllDay {
            return "\(CalendarEventsCopy.allDay) · "
                + dayMonthYear(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
                + " – "
                + dayMonthYear(timing.end, calendar: calendar, locale: locale, timeZone: timeZone)
        }
        if !timing.isMultiday {
            return fullDate(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
                + " · "
                + time(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
                + " – "
                + time(timing.end, calendar: calendar, locale: locale, timeZone: timeZone)
        }
        return dayMonthYear(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
            + ", "
            + time(timing.start, calendar: calendar, locale: locale, timeZone: timeZone)
            + " – "
            + dayMonthYear(timing.end, calendar: calendar, locale: locale, timeZone: timeZone)
            + ", "
            + time(timing.end, calendar: calendar, locale: locale, timeZone: timeZone)
    }

    /// The full date with weekday, as the Web Experience's popover shows
    /// it: "Wed, Jul 22, 2026" in en_US.
    private static func fullDate(
        _ date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        format("yMMMEd", date, calendar: calendar, locale: locale, timeZone: timeZone)
    }

    /// The month, day, and year without weekday: "Jul 22, 2026" in en_US.
    private static func dayMonthYear(
        _ date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        format("yMMMd", date, calendar: calendar, locale: locale, timeZone: timeZone)
    }

    /// The localized short time form, the same template the Calendar
    /// Event Row start time uses.
    private static func time(
        _ date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        format("jm", date, calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private static func format(
        _ template: String,
        _ date: Date,
        calendar: Calendar,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

extension CalendarEventsCopy {
    /// The timing line's all-day word, English-only like the rest of the
    /// events copy.
    static let allDay = "All day"
}
