import SwiftUI

/// The single-line iOS Header Status row.
///
/// While the connection gate is on, the row always reserves its 16 points so
/// messages never move the Calendar Grid. It spans the full width between the
/// 16-point header margins, aligns to the trailing edge (mirroring naturally
/// for right-to-left), stays on one visual line with tail truncation, and
/// exposes the complete message to VoiceOver. Changes are announced politely
/// as a live region.
///
/// Tones come from the palette: the existing olive/neutral family for
/// information, amber for recoverable warnings, and red for errors. The
/// message copy itself carries the meaning, so severity never depends on
/// color alone. The latest message remains until superseded; a `nil` message
/// leaves the reserved row blank.
struct IOSHeaderStatus: View {
    /// The severity of the current message.
    enum Tone: Sendable {
        case info
        case warning
        case error
    }

    let message: String?
    let tone: Tone

    var body: some View {
        Text(message ?? "")
            .font(.footnote)
            // The compact 16-point row bounds the text size; the complete
            // message always reaches VoiceOver regardless.
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)
            .frame(height: 16)
            .frame(maxWidth: .infinity)
            .background(PlannerPalette.canvas)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var foregroundColor: Color {
        switch tone {
        case .info:
            return PlannerPalette.monthText
        case .warning:
            return PlannerPalette.statusWarning
        case .error:
            return PlannerPalette.statusError
        }
    }
}

extension IOSHeaderStatus.Tone {
    /// Maps the connection module's status tone onto the status row's
    /// presentation tone; the view layer owns the palette mapping.
    init(_ tone: GoogleAccountConnection.Status.Tone) {
        switch tone {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .error:
            self = .error
        }
    }

    /// Maps the Source Calendars module's status tone onto the status row's
    /// presentation tone; the view layer owns the palette mapping.
    init(_ tone: SourceCalendarsStatus.Tone) {
        switch tone {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .error:
            self = .error
        }
    }

    /// Maps the events module's status tone onto the status row's
    /// presentation tone; the view layer owns the palette mapping.
    init(_ tone: CalendarEventsStatus.Tone) {
        switch tone {
        case .info:
            self = .info
        case .warning:
            self = .warning
        case .error:
            self = .error
        }
    }
}

/// Resolves the single iOS Header Status content from its three publishers.
/// The connection's warnings and errors — authorization and connectivity
/// problems — lead; Source Calendar loading follows; event-fetch progress
/// and issues override the connection's transient information; the
/// connection's own information shows when neither has anything to say.
/// Resting connection states publish nothing, so a settled connection
/// leaves the row to the calendar pipelines or blank.
func resolveHeaderStatus(
    connection: GoogleAccountConnection.Status?,
    sourceCalendars: SourceCalendarsStatus? = nil,
    events: CalendarEventsStatus?
) -> (message: String?, tone: IOSHeaderStatus.Tone) {
    if let connection, connection.message != nil,
       connection.tone != .info
    {
        return (connection.message, IOSHeaderStatus.Tone(connection.tone))
    }

    if let sourceCalendars, sourceCalendars.message != nil {
        return (
            sourceCalendars.message,
            IOSHeaderStatus.Tone(sourceCalendars.tone)
        )
    }

    if let events, events.message != nil {
        return (events.message, IOSHeaderStatus.Tone(events.tone))
    }

    if let connection {
        return (connection.message, IOSHeaderStatus.Tone(connection.tone))
    }

    return (nil, .info)
}
