import Foundation

/// A Calendar Event (Planning glossary) in Planner's classified,
/// local-date form: the output of Calendar Event Normalization. This is
/// the only shape the iOS Calendar Surface, the Event Detail Popover,
/// and Stored Calendar Events ever hold — the same struct is the
/// in-memory model and the Codable persistence record (iOS ADR 0007), so
/// a stored event persists its canonical identity and presents at
/// process start with no conversion.
struct CalendarEvent: Equatable, Sendable, Codable {
    /// The canonical cross-calendar occurrence identity: one entry per
    /// occurrence across every Selected Source Calendar.
    let id: String
    /// The winning Source Calendar's identity and presentation
    /// attributes, kept intact from the winning copy.
    let sourceCalendar: GoogleSourceCalendar
    let title: String
    /// The Event Color as a `#RRGGBB` hex string.
    let colorHex: String
    let textTone: CalendarEventTextTone
    /// The normalized bar-or-row classification in local dates, exactly
    /// as normalized at fetch time.
    let kind: Kind
    /// The Event Detail Popover payload, built at normalization and
    /// projected only when this canonical event identity is selected
    /// (iOS ADR 0005); persisted so a stored event's detail opens
    /// offline exactly as a freshly fetched one's does.
    let detail: CalendarEventDetail

    /// The normalized bar-or-row classification in local dates.
    enum Kind: Equatable, Sendable, Codable {
        /// An all-day or multiday bar over inclusive local dates, with
        /// the event's start instant for ordering.
        case bar(startDate: Date, endDate: Date, startsAt: Date)

        /// An intraday row on one local date.
        case row(date: Date, startsAt: Date, startTimeText: String)
    }
}

/// Canonical cross-calendar occurrence identity: the same occurrence
/// returned through multiple Selected Source Calendars presents once.
/// Google's `iCalUID` plus `originalStartTime` when supplied — otherwise
/// the occurrence's all-day date or timed start — identifies one
/// occurrence across sources, so distinct recurring instances, including
/// moved ones, never collapse. Without an `iCalUID`, identity falls back
/// to Source Calendar ID plus Google's event ID: Planner never guesses
/// that unrelated fallback events across calendars are duplicates.
enum CalendarEventCanonicalIdentity {
    /// The canonical occurrence identity of one fetched copy, used as the
    /// Calendar Event's identity for deduplication, layout, and the Event
    /// Detail selection. Opaque beyond its uniqueness and stability
    /// guarantees; it persists inside Stored Calendar Events exactly so a
    /// stored event keeps its canonical identity (iOS ADR 0007).
    static func id(of sourceEvent: GoogleSourceCalendarEvent) -> String {
        let event = sourceEvent.event
        if let iCalUID = event.iCalUID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !iCalUID.isEmpty {
            let occurrence = event.originalStartTime ?? event.start
            return "ical:\(iCalUID):occurrence:\(occurrenceStamp(occurrence))"
        }
        return "src:\(sourceEvent.sourceCalendar.id):event:\(event.id)"
    }

    private static func occurrenceStamp(
        _ time: GoogleCalendarEventTime
    ) -> String {
        switch time {
        case .allDay(let year, let month, let day):
            return "date-\(year)-\(month)-\(day)"
        case .timed(let instant):
            return "time-\(instant.timeIntervalSince1970)"
        }
    }
}

/// The readable text tone on top of an Event Color.
enum CalendarEventTextTone: Equatable, Sendable, Codable {
    case dark
    case light
}

/// An Event Color decomposed from its `#RRGGBB` hex form. A component
/// that fails to parse reads as zero.
struct EventColorRGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    /// Decomposes a `#RRGGBB` hex string, returning `nil` when it is not
    /// exactly six pairs after one optional leading `#`.
    init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else {
            return nil
        }
        red = Int(hex.prefix(2), radix: 16) ?? 0
        green = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
        blue = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
    }

    /// The WCAG 2.x relative luminance of the color.
    var relativeLuminance: Double {
        Self.relativeLuminance(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }

    /// The WCAG 2.x relative luminance of sRGB channels in 0...1.
    static func relativeLuminance(
        red: Double,
        green: Double,
        blue: Double
    ) -> Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
    }

    /// One sRGB channel's linear form per the WCAG threshold.
    private static func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

/// Calendar Event Normalization (Planning glossary): applies Planner's
/// product rules to fetched Google Calendar events. Stateless — every
/// input crosses the interface per call, so a timezone change is simply
/// another call with a new environment.
enum CalendarEventNormalization {
    /// Applies Planner's product rules: cancelled and declined events drop
    /// out, duplicate copies of one canonical occurrence collapse to their
    /// deterministic winner — the Primary Source Calendar copy when
    /// present, otherwise the earliest in the deterministic Source
    /// Calendar order, kept intact with nothing combined across copies —
    /// blank titles become "Busy", all-day ends turn inclusive, and every
    /// event classifies as a bar or a row in the environment's local
    /// dates.
    static func normalize(
        _ events: [GoogleSourceCalendarEvent],
        eventColorBackgrounds: [String: String],
        environment: CalendarEnvironment
    ) -> [CalendarEvent] {
        let calendar = environment.calendar
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = environment.locale
        timeFormatter.timeZone = environment.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let timingContext = CalendarEventTimingLine.Context(
            calendar: calendar,
            locale: environment.locale,
            timeZone: environment.timeZone
        )

        // Collapse duplicate copies of one canonical occurrence, keeping
        // first-appearance order of identities so layout stays
        // deterministic regardless of copy order.
        var identityOrder: [String] = []
        var winners: [String: GoogleSourceCalendarEvent] = [:]
        for sourceEvent in events {
            guard !sourceEvent.event.isCancelled,
                  !sourceEvent.event.isDeclinedByViewer
            else {
                continue
            }
            let identity = CalendarEventCanonicalIdentity.id(of: sourceEvent)
            if let current = winners[identity] {
                if SourceCalendarReconciliation.precedes(
                    sourceEvent.sourceCalendar,
                    current.sourceCalendar
                ) {
                    winners[identity] = sourceEvent
                }
            } else {
                winners[identity] = sourceEvent
                identityOrder.append(identity)
            }
        }

        return identityOrder.compactMap { identity in
            guard let sourceEvent = winners[identity] else {
                return nil
            }
            let sourceCalendar = sourceEvent.sourceCalendar
            let event = sourceEvent.event

            let title = event.summary?.trimmedToNil ?? "Busy"
            // The Event Color (Planning glossary): the explicit Google
            // event color when one is set and known, otherwise the Source
            // Calendar's background color.
            let colorHex = event.colorId
                .flatMap { eventColorBackgrounds[$0] }
                ?? sourceCalendar.backgroundColorHex
            let textTone = textTone(forHexColor: colorHex)

            // The Event Detail Popover's optional fields, mapped once so
            // every classification branch publishes the same omission
            // rules: blank locations and Google links are absent; HTML
            // notes render plain and blank out to absence.
            let location = event.location?.trimmedToNil
            let googleLink = event.googleLink?.trimmedToNil
            let notes = CalendarEventPlainTextNotes.plainText(
                fromHTML: event.notes
            )
            let attendees = CalendarEventAttendeeNormalization.normalize(
                event.attendees
            )

            let makeDetail = { (timing: CalendarEventTiming) in
                CalendarEventDetail(
                    title: title,
                    colorHex: colorHex,
                    timingText: CalendarEventTimingLine.timingLine(
                        for: timing,
                        context: timingContext
                    ),
                    location: location,
                    googleLink: googleLink,
                    notes: notes,
                    attendees: attendees.visible,
                    hiddenAttendeeCount: attendees.hiddenCount
                )
            }

            switch (event.start, event.end) {
            case (
                .allDay(let startYear, let startMonth, let startDay),
                .allDay(let endYear, let endMonth, let endDay)
            ):
                guard
                    let startDate = civilDate(
                        year: startYear,
                        month: startMonth,
                        day: startDay,
                        environment: environment
                    ),
                    let exclusiveEnd = civilDate(
                        year: endYear,
                        month: endMonth,
                        day: endDay,
                        environment: environment
                    ),
                    let endDate = calendar.date(
                        byAdding: .day,
                        value: -1,
                        to: exclusiveEnd
                    ),
                    endDate >= startDate
                else {
                    return nil
                }
                return CalendarEvent(
                    id: identity,
                    sourceCalendar: sourceCalendar,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .bar(
                        startDate: startDate,
                        endDate: endDate,
                        startsAt: startDate
                    ),
                    detail: makeDetail(
                        CalendarEventTiming(
                            start: startDate,
                            end: endDate,
                            isAllDay: true,
                            isMultiday: endDate > startDate
                        )
                    )
                )
            case (.timed(let startsAt), .timed(let endsAt)):
                let startDate = calendar.startOfDay(for: startsAt)
                let endDate = calendar.startOfDay(for: endsAt)
                if endDate > startDate {
                    return CalendarEvent(
                        id: identity,
                        sourceCalendar: sourceCalendar,
                        title: title,
                        colorHex: colorHex,
                        textTone: textTone,
                        kind: .bar(
                            startDate: startDate,
                            endDate: endDate,
                            startsAt: startsAt
                        ),
                        detail: makeDetail(
                            CalendarEventTiming(
                                start: startsAt,
                                end: endsAt,
                                isAllDay: false,
                                isMultiday: true
                            )
                        )
                    )
                }
                return CalendarEvent(
                    id: identity,
                    sourceCalendar: sourceCalendar,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .row(
                        date: startDate,
                        startsAt: startsAt,
                        startTimeText: timeFormatter.string(from: startsAt)
                    ),
                    detail: makeDetail(
                        CalendarEventTiming(
                            start: startsAt,
                            end: endsAt,
                            isAllDay: false,
                            isMultiday: false
                        )
                    )
                )
            default:
                // A mixed or missing start/end pair is not presentable.
                return nil
            }
        }
    }

    /// The readable text tone on an Event Color: whichever of Planner's
    /// ink or white has the stronger APCA lightness contrast against it.
    /// APCA — the W3C's perceptually calibrated WCAG 3 candidate — ranks
    /// pairings the way the eye reads them; the WCAG 2.x ratio it
    /// replaces overvalued dark text on mid-dark saturated colors,
    /// rendering barely readable ink on Google's blues (iOS ADR 0004).
    static func textTone(forHexColor hexColor: String) -> CalendarEventTextTone {
        guard let color = EventColorRGB(hex: hexColor) else {
            return .light
        }
        let luminance = color.relativeLuminance
        let darkLc = apcaContrast(
            textLuminance: darkTextRelativeLuminance,
            backgroundLuminance: luminance
        )
        let lightLc = apcaContrast(
            textLuminance: 1.0,
            backgroundLuminance: luminance
        )
        return abs(darkLc) >= abs(lightLc) ? .dark : .light
    }

    /// The APCA lightness contrast (Lc) of a text color on a background,
    /// from their WCAG relative luminances: positive for dark text on a
    /// light ground, negative for light text on a dark ground, with
    /// polarity-dependent exponents modeling how the eye reads each
    /// pairing; a pairing too weak to read clips to zero. Constants are
    /// the published apca-w3 ones.
    private static func apcaContrast(
        textLuminance: Double,
        backgroundLuminance: Double
    ) -> Double {
        let blackThreshold = 0.022
        let text = textLuminance > blackThreshold
            ? textLuminance
            : textLuminance + pow(blackThreshold - textLuminance, 1.414)
        let background = backgroundLuminance > blackThreshold
            ? backgroundLuminance
            : backgroundLuminance + pow(blackThreshold - backgroundLuminance, 1.414)
        guard abs(background - text) >= 0.0005 else {
            return 0
        }
        if background > text {
            let contrast = pow(background, 0.56) - pow(text, 0.57)
            return contrast < 0.1 ? 0 : contrast * 1.14 * 100
        }
        let contrast = pow(background, 0.62) - pow(text, 0.65)
        return contrast > -0.1 ? 0 : contrast * 1.14 * 100
    }

    /// The WCAG relative luminance of the dark text candidate, Planner's
    /// ink (PlannerPalette.ink: sRGB 0.114, 0.129, 0.071).
    private static let darkTextRelativeLuminance =
        EventColorRGB.relativeLuminance(
            red: 0.114,
            green: 0.129,
            blue: 0.071
        )

    private static func civilDate(
        year: Int,
        month: Int,
        day: Int,
        environment: CalendarEnvironment
    ) -> Date? {
        var components = DateComponents()
        components.calendar = environment.calendar
        components.timeZone = environment.timeZone
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }
}

private extension String {
    /// Trims an optional Google string at the model seam, returning
    /// `nil` when nothing but whitespace remains — the shared
    /// blank-means-absent rule for titles and optional detail fields.
    var trimmedToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
