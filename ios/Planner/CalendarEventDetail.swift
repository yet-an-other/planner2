import Foundation

/// The Event Detail Popover's presentation payload for one Calendar Event
/// (Planning glossary). The Calendar Events model projects it from the
/// canonical event selected by primary Source Calendar event identity, so
/// successful replacement updates an open popover and disappearance or
/// Disconnect on This Device dismisses it (iOS ADR 0005). Every field is
/// memory-only (iOS ADR 0003).
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
    /// The event's notes as plain text (HTML stripped at
    /// normalization), or `nil` when the event has none — the Notes
    /// section is omitted rather than shown empty.
    let notes: String?
    /// The first five attendees, display-name primary with the response
    /// status as text; empty when the event has none — the Attendees
    /// section is omitted rather than shown empty.
    let attendees: [CalendarEventAttendee]
    /// How many further attendees the five-attendee cap hides — the
    /// "+N more" count; zero when the list fits.
    let hiddenAttendeeCount: Int

    init(
        title: String,
        colorHex: String,
        timingText: String,
        location: String? = nil,
        googleLink: String? = nil,
        notes: String? = nil,
        attendees: [CalendarEventAttendee] = [],
        hiddenAttendeeCount: Int = 0
    ) {
        self.title = title
        self.colorHex = colorHex
        self.timingText = timingText
        self.location = location
        self.googleLink = googleLink
        self.notes = notes
        self.attendees = attendees
        self.hiddenAttendeeCount = hiddenAttendeeCount
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
    /// The environment values every timing formatter needs, travelling as
    /// one value so their date, locale, and timezone can never drift.
    struct Context: Sendable {
        let calendar: Calendar
        let locale: Locale
        let timeZone: TimeZone
    }

    static func timingLine(
        for timing: CalendarEventTiming,
        context: Context
    ) -> String {
        if timing.isAllDay, !timing.isMultiday {
            return "\(CalendarEventsCopy.allDay) · "
                + fullDate(timing.start, context: context)
        }
        if timing.isAllDay {
            return "\(CalendarEventsCopy.allDay) · "
                + dayMonthYear(timing.start, context: context)
                + " – "
                + dayMonthYear(timing.end, context: context)
        }
        if !timing.isMultiday {
            return fullDate(timing.start, context: context)
                + " · "
                + time(timing.start, context: context)
                + " – "
                + time(timing.end, context: context)
        }
        return dayMonthYear(timing.start, context: context)
            + ", "
            + time(timing.start, context: context)
            + " – "
            + dayMonthYear(timing.end, context: context)
            + ", "
            + time(timing.end, context: context)
    }

    /// The full date with weekday, as the Web Experience's popover shows
    /// it: "Wed, Jul 22, 2026" in en_US.
    private static func fullDate(
        _ date: Date,
        context: Context
    ) -> String {
        format("yMMMEd", date, context: context)
    }

    /// The month, day, and year without weekday: "Jul 22, 2026" in en_US.
    private static func dayMonthYear(
        _ date: Date,
        context: Context
    ) -> String {
        format("yMMMd", date, context: context)
    }

    /// The localized short time form, the same template the Calendar
    /// Event Row start time uses.
    private static func time(
        _ date: Date,
        context: Context
    ) -> String {
        format("jm", date, context: context)
    }

    private static func format(
        _ template: String,
        _ date: Date,
        context: Context
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = context.calendar
        formatter.locale = context.locale
        formatter.timeZone = context.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

/// Plain-text notes from Google's event description, isolated so the invariant
/// stays pinned at the seam: descriptions containing HTML are stripped at
/// normalization by a deterministic, dependency-free converter — tags removed,
/// entities and anchor text resolved, block and `<br>` breaks turned into
/// newlines, never markup — while already plain descriptions retain authored
/// line breaks. Google's auto-created-event boilerplate is removed, matching
/// the Web Experience's invariant. Plain text avoids rendering organizer
/// markup and any tracking beacons it may embed.
///
/// The converter is pure Swift text work with no WebKit or main-thread
/// requirement (unlike `NSAttributedString(documentType: .html)`, which is
/// WebKit-backed, main-thread-only, and blocks the caller synchronously), so
/// normalization stays cheap and off the critical path on every fetch.
enum CalendarEventPlainTextNotes {
    /// Renders Google's event description into plain text, or returns
    /// `nil` when nothing readable remains — absent, blank, or
    /// markup-only notes omit the Notes section rather than show it
    /// empty.
    static func plainText(fromHTML html: String?) -> String? {
        guard let html else {
            return nil
        }

        // Google also returns descriptions that are already plain text. The
        // markup converter would treat their line breaks as insignificant
        // whitespace and decode stray ampersands as entities, so only run it
        // when markup is actually present.
        let source = html as NSString
        let rendered =
            htmlMarkup.firstMatch(
                in: html,
                range: NSRange(location: 0, length: source.length)
            ) != nil
            ? strippingMarkup(html)
            : html

        let text = rendered as NSString
        let stripped = googleAutoEventBoilerplate.stringByReplacingMatches(
            in: rendered,
            range: NSRange(location: 0, length: text.length),
            withTemplate: ""
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Converts an HTML description to plain text: `<br>` and block-level
    /// tag boundaries become newlines, every other tag is dropped keeping
    /// its inner text, and HTML entities resolve. Deterministic and
    /// thread-safe — no WebKit, no main-thread hop.
    private static func strippingMarkup(_ html: String) -> String {
        let full = NSRange(location: 0, length: (html as NSString).length)
        var text = lineBreakTags.stringByReplacingMatches(
            in: html,
            range: full,
            withTemplate: "\n"
        )
        let afterBreaks = NSRange(location: 0, length: (text as NSString).length)
        text = otherTags.stringByReplacingMatches(
            in: text,
            range: afterBreaks,
            withTemplate: ""
        )
        // Adjacent block boundaries (e.g. `</div><div>`) yield back-to-back
        // breaks; collapse them so markup layout does not open blank lines.
        let afterTags = NSRange(location: 0, length: (text as NSString).length)
        text = blankLineRuns.stringByReplacingMatches(
            in: text,
            range: afterTags,
            withTemplate: "\n"
        )
        return decodingEntities(text)
    }

    /// Resolves HTML character references — the common named entities plus
    /// decimal (`&#NN;`) and hexadecimal (`&#xNN;`) forms — in a single
    /// pass so an encoded entity such as `&amp;lt;` resolves once to
    /// `&lt;`, never twice to `<`.
    private static func decodingEntities(_ text: String) -> String {
        let source = text as NSString
        let matches = entityReference.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else {
            return text
        }
        var result = text
        for match in matches.reversed() {
            let token = source.substring(with: match.range)
            guard let range = Range(match.range, in: result),
                  let replacement = entityValue(token)
            else {
                continue
            }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Maps one entity token (including its `&` and `;`) to its character,
    /// or `nil` to leave an unrecognized reference untouched.
    private static func entityValue(_ token: String) -> String? {
        if let named = namedEntities[token] {
            return named
        }
        guard token.hasPrefix("&#"), token.hasSuffix(";") else {
            return nil
        }
        let digits = token.dropFirst(2).dropLast()
        let scalarValue: UInt32?
        if digits.first == "x" || digits.first == "X" {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits, radix: 10)
        }
        guard let scalarValue, let scalar = Unicode.Scalar(scalarValue) else {
            return nil
        }
        return String(scalar)
    }

    private static let namedEntities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&quot;": "\"",
        "&apos;": "'",
        "&#39;": "'",
        "&nbsp;": "\u{00A0}",
    ]

    /// Detects tag-shaped markup while leaving ordinary already-plain
    /// descriptions on the newline-preserving path.
    private static let htmlMarkup: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "<[A-Za-z!/][^>]*>"
        ) else {
            preconditionFailure("The HTML-markup pattern must compile")
        }
        return regex
    }()

    /// `<br>` and block-level element boundaries that map to a line break.
    private static let lineBreakTags: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern:
                "</?(?:br|p|div|li|ul|ol|tr|h[1-6]|blockquote|section|article|pre|table|thead|tbody)\\b[^>]*>",
            options: [.caseInsensitive]
        ) else {
            preconditionFailure("The line-break-tag pattern must compile")
        }
        return regex
    }()

    /// Any remaining tag — dropped, keeping its inner text.
    private static let otherTags: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "<[^>]+>"
        ) else {
            preconditionFailure("The residual-tag pattern must compile")
        }
        return regex
    }()

    /// Runs of two or more newlines (with optional intervening spaces or
    /// tabs) left by adjacent block boundaries, collapsed to one break.
    private static let blankLineRuns: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "[ \\t]*\\n(?:[ \\t]*\\n)+"
        ) else {
            preconditionFailure("The blank-line pattern must compile")
        }
        return regex
    }()

    /// A named or numeric HTML character reference.
    private static let entityReference: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "&(?:#[xX]?[0-9A-Fa-f]+|[A-Za-z][A-Za-z0-9]*);"
        ) else {
            preconditionFailure("The entity pattern must compile")
        }
        return regex
    }()

    /// Google auto-appends this boilerplate to events it creates
    /// automatically (flights, hotel reservations, etc.). It carries no
    /// user value, so it is stripped at normalization. The g.co/calendar
    /// link may sit on the same line or wrap; `\s*` tolerates either.
    /// Mirrors the Web Experience's pattern.
    private static let googleAutoEventBoilerplate: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern:
                "To see detailed information for automatically created events like this one, use the official Google Calendar app\\.\\s*https://g\\.co/calendar"
        ) else {
            preconditionFailure("The boilerplate pattern must compile")
        }
        return regex
    }()
}

/// One attendee in the Event Detail Popover: the display name when
/// Google provides one, the email otherwise, and the response status as
/// a closed union rendered as text — never color alone.
struct CalendarEventAttendee: Equatable, Sendable {
    /// The attendee's display name when Google provides one, their
    /// email otherwise — the single line the popover shows.
    let label: String
    /// The attendee's response status in Planner's closed union.
    let status: CalendarEventResponseStatus
}
/// An attendee's response status in Planner's closed union; Google's
/// `needsAction` reads as invited and any unrecognized value collapses
/// to unknown, matching the Web Experience.
enum CalendarEventResponseStatus: Equatable, Sendable {
    case accepted
    case declined
    case tentative
    case invited
    case unknown

    /// The English-only status copy the popover renders, separate from
    /// the enum's identity so future copy can change without changing
    /// the domain value.
    var displayText: String {
        switch self {
        case .accepted: "accepted"
        case .declined: "declined"
        case .tentative: "tentative"
        case .invited: "invited"
        case .unknown: "unknown"
        }
    }

    /// Maps Google's raw response status string into the closed union.
    init(googleResponseStatus: String?) {
        self = switch googleResponseStatus {
        case "accepted": .accepted
        case "declined": .declined
        case "tentative": .tentative
        case "needsAction": .invited
        default: .unknown
        }
    }
}

/// Maps Google's attendees into the popover's presentation list:
/// display-name primary with email fallback, trimmed; attendees with no
/// displayable identity drop out; the list caps at five with the rest
/// counted into the "+N more" line.
enum CalendarEventAttendeeNormalization {
    /// The normalized attendees and how many further attendees the cap
    /// hides (zero when the list fits).
    static func normalize(
        _ attendees: [GoogleCalendarEventAttendee]
    ) -> (visible: [CalendarEventAttendee], hiddenCount: Int) {
        let mapped = attendees.compactMap { attendee -> CalendarEventAttendee? in
            let displayName = attendee.displayName?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let email = attendee.email?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let label = displayName.isEmpty ? email : displayName
            guard !label.isEmpty else {
                return nil
            }
            return CalendarEventAttendee(
                label: label,
                status: CalendarEventResponseStatus(
                    googleResponseStatus: attendee.responseStatus
                )
            )
        }
        return (
            Array(mapped.prefix(Self.maxVisibleAttendees)),
            max(0, mapped.count - Self.maxVisibleAttendees)
        )
    }

    /// The popover shows at most this many attendees before the
    /// "+N more" line, matching the Web Experience's cap.
    private static let maxVisibleAttendees = 5
}

extension CalendarEventsCopy {
    /// The timing line's all-day word, English-only like the rest of the
    /// events copy.
    static let allDay = "All day"
}
