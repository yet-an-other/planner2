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
            #if DEBUG
            // The Maps-pin UI test's launch-argument harness replaces the
            // surface while its launch argument is present.
            if ProcessInfo.processInfo.arguments.contains(
                EventDetailMapsPinHarnessView.launchArgument
            ) {
                EventDetailMapsPinHarnessView()
            } else {
                calendarScreen
            }
            #else
            calendarScreen
            #endif
        }
    }

    private var calendarScreen: some View {
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
