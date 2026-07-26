import Foundation
import Testing
@testable import Planner

@Suite("Header Status Resolution")
struct HeaderStatusResolutionTests {
    private static func connection(
        _ message: String?,
        _ tone: GoogleAccountConnection.Status.Tone
    ) -> GoogleAccountConnection.Status {
        GoogleAccountConnection.Status(message: message, tone: tone)
    }

    private static func sourceCalendars(
        _ message: String?,
        _ tone: SourceCalendarsStatus.Tone
    ) -> SourceCalendarsStatus {
        SourceCalendarsStatus(message: message, tone: tone)
    }

    private static func events(
        _ message: String?,
        _ tone: CalendarEventsStatus.Tone
    ) -> CalendarEventsStatus {
        CalendarEventsStatus(message: message, tone: tone)
    }

    @Test("A connection warning or error leads over any events message")
    func connectionAlertLeads() {
        let content = resolveHeaderStatus(
            connection: Self.connection(
                GoogleAccountConnectionCopy.offline,
                .warning
            ),
            events: Self.events(CalendarEventsCopy.loading, .info)
        )

        #expect(content.message == GoogleAccountConnectionCopy.offline)
        #expect(content.tone == .warning)
    }

    @Test("Source Calendar loading leads over event and connection status")
    func sourceCalendarsLeadCalendarPipeline() {
        let content = resolveHeaderStatus(
            connection: Self.connection(
                GoogleAccountConnectionCopy.restoring,
                .info
            ),
            sourceCalendars: Self.sourceCalendars(
                SourceCalendarsCopy.loading,
                .info
            ),
            events: Self.events(CalendarEventsCopy.loading, .info)
        )

        #expect(content.message == SourceCalendarsCopy.loading)
        #expect(content.tone == .info)
    }

    @Test("Events progress overrides the connection's transient information")
    func eventsProgressOverridesTransientInfo() {
        let content = resolveHeaderStatus(
            connection: Self.connection(
                GoogleAccountConnectionCopy.restoring,
                .info
            ),
            events: Self.events(CalendarEventsCopy.loading, .info)
        )

        #expect(content.message == CalendarEventsCopy.loading)
        #expect(content.tone == .info)
    }

    @Test("An events fetch issue shows while the connection rests silent")
    func eventsIssueShowsOverSilentConnection() {
        // The resting connection publishes nothing, so an events fetch
        // issue is the only candidate.
        let content = resolveHeaderStatus(
            connection: Self.connection(nil, .info),
            events: Self.events(CalendarEventsCopy.failedPartial, .warning)
        )

        #expect(content.message == CalendarEventsCopy.failedPartial)
        #expect(content.tone == .warning)
    }

    @Test("The connection's information shows when events have nothing to say")
    func connectionInfoShowsWhenEventsSilent() {
        let content = resolveHeaderStatus(
            connection: Self.connection(
                GoogleAccountConnectionCopy.restoring,
                .info
            ),
            events: Self.events(nil, .info)
        )

        #expect(content.message == GoogleAccountConnectionCopy.restoring)
        #expect(content.tone == .info)
    }

    @Test("A silent connection with an events message shows the events message")
    func silentConnectionShowsEvents() {
        let content = resolveHeaderStatus(
            connection: Self.connection(nil, .info),
            events: Self.events(CalendarEventsCopy.offline, .warning)
        )

        #expect(content.message == CalendarEventsCopy.offline)
        #expect(content.tone == .warning)
    }

    @Test("Nothing to say leaves the reserved row blank")
    func nothingToSayStaysBlank() {
        let content = resolveHeaderStatus(
            connection: Self.connection(nil, .info),
            events: Self.events(nil, .info)
        )

        #expect(content.message == nil)
        #expect(content.tone == .info)
    }
}
