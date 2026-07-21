import SwiftUI

/// The single-line iOS Header Status row.
///
/// While the connection gate is on, the row always reserves its 20 points so
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
            // The row height is fixed, so the text size is bounded; the
            // complete message always reaches VoiceOver regardless.
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 16)
            .frame(height: 20)
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

/// Resolves the single iOS Header Status content from its two publishers.
/// The connection's warnings and errors — authorization and connectivity
/// problems — lead; event-fetch progress and issues override the
/// connection's resting information; the connection's own information
/// shows when neither has anything to say.
func resolveHeaderStatus(
    connection: GoogleAccountConnection.Status?,
    events: CalendarEventsStatus?
) -> (message: String?, tone: IOSHeaderStatus.Tone) {
    if let connection, connection.message != nil,
       connection.tone != .info
    {
        return (connection.message, IOSHeaderStatus.Tone(connection.tone))
    }

    if let events, events.message != nil {
        return (events.message, IOSHeaderStatus.Tone(events.tone))
    }

    if let connection {
        return (connection.message, IOSHeaderStatus.Tone(connection.tone))
    }

    return (nil, .info)
}
