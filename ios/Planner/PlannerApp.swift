import SwiftUI

@main
struct PlannerApp: App {
    /// The Calendar Data coordinator: the one composition root for the
    /// Google Account Connection and the Calendar Data modules. While
    /// the build-time release gate is off, its publications are `nil` and
    /// the Calendar Screen renders the accepted 80-point iOS Calendar
    /// Header with neither connection seam mounted.
    private let calendarData: CalendarDataCoordinator

    init() {
        calendarData = CalendarDataCoordinator()
    }

    var body: some Scene {
        WindowGroup {
            CalendarScreen(
                environment: .current(),
                currentEnvironment: { .current() },
                connection: calendarData.connection,
                sourceCalendars: calendarData.sourceCalendars,
                events: calendarData.events
            )
            .onOpenURL { url in
                // The reversed-client-ID scheme routes Google's OAuth
                // callback here; the module decides whether it is ours.
                _ = calendarData.connection?.handleCallbackURL(url)
            }
        }
    }
}
