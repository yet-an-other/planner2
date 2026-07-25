import SwiftUI

@main
struct PlannerApp: App {
    /// The Google Account Connection module, created only when the
    /// build-time release gate is on. While the gate is off, no connection
    /// behavior is initialized and the Calendar Screen renders the accepted
    /// 100-point iOS Calendar Header with neither connection seam mounted.
    private let accountConnection: GoogleAccountConnection?

    /// The Calendar Events module, created only when the build-time release
    /// gate is on. It consumes disclosure-gated Selected Source Calendars,
    /// keeps their events memory-only, and clears them on Disconnect on This
    /// Device.
    private let calendarEvents: CalendarEventsModel?

    /// Disclosure-gated Source Calendar loading, reconciliation, and
    /// per-account selection persistence.
    private let sourceCalendars: SourceCalendarsModel?

    init() {
        switch GoogleAccountConnectionConfiguration.load(from: .main) {
        case .gatedOff:
            accountConnection = nil
            calendarEvents = nil
            sourceCalendars = nil
        case let configuration:
            let calendarAPI = GoogleCalendarAPIAdapter()
            let events = CalendarEventsModel(
                environment: .current(),
                adapter: calendarAPI,
                connectivityMonitor: NWPathConnectivityMonitor()
            )
            let sources = SourceCalendarsModel(
                adapter: calendarAPI,
                store: UserDefaultsSelectedSourceCalendarsStore(),
                selectionConsumer: events,
                connectivityMonitor: NWPathConnectivityMonitor()
            )
            // Forbidden/not-found event failures recover through the Source
            // Calendars module's one live reload and reconciliation.
            events.sourceCalendarRecovery = sources
            let connection = GoogleAccountConnection(
                configuration: configuration,
                makeAdapter: { configured in
                    GoogleSignInSDKAdapter(configuration: configured)
                },
                disclosureStore: UserDefaultsGoogleConnectionDisclosureStore(),
                connectivityMonitor: NWPathConnectivityMonitor(),
                installationBoundary: GoogleConnectionInstallationBoundary(
                    defaults: .standard,
                    deviceMarkerStore: KeychainGoogleConnectionDeviceMarkerStore(),
                    selectedSourceCalendarsStore:
                        UserDefaultsSelectedSourceCalendarsStore()
                ),
                calendarDataConsumer: sources
            )
            calendarEvents = events
            sourceCalendars = sources
            accountConnection = connection
        }
    }

    var body: some Scene {
        WindowGroup {
            CalendarScreen(
                environment: .current(),
                currentEnvironment: { .current() },
                connection: accountConnection,
                sourceCalendars: sourceCalendars,
                events: calendarEvents
            )
            .onOpenURL { url in
                // The reversed-client-ID scheme routes Google's OAuth
                // callback here; the module decides whether it is ours.
                _ = accountConnection?.handleCallbackURL(url)
            }
        }
    }
}
