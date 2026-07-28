import SwiftUI

@main
struct PlannerApp: App {
    /// The Google Account Connection module, created only when the
    /// build-time release gate is on. While the gate is off, no connection
    /// behavior is initialized and the Calendar Screen renders the accepted
    /// 80-point iOS Calendar Header with neither connection seam mounted.
    private let accountConnection: GoogleAccountConnection?

    /// The Calendar Events module, created only when the build-time release
    /// gate is on. It consumes disclosure-gated Selected Source Calendars
    /// and persists their events as Stored Calendar Events (ADR 0007):
    /// presented at process start, written through on every successful
    /// response, and wiped on Disconnect on This Device.
    private let calendarEvents: CalendarEventsModel?

    /// Disclosure-gated Source Calendar loading, reconciliation, and
    /// per-account selection persistence.
    private let sourceCalendars: SourceCalendarsModel?

    /// The fan-out publishing the disclosure-gated Calendar-data account
    /// to the Source Calendars and Calendar Events modules. Retained here
    /// because the connection holds its consumer weakly.
    private let calendarDataHub: CalendarDataAccountConsumerHub?

    init() {
        switch GoogleAccountConnectionConfiguration.load(from: .main) {
        case .gatedOff:
            accountConnection = nil
            calendarEvents = nil
            sourceCalendars = nil
            calendarDataHub = nil
        case let configuration:
            let calendarAPI = GoogleCalendarAPIAdapter()
            let events = CalendarEventsModel(
                environment: .current(),
                adapter: calendarAPI,
                connectivityMonitor: NWPathConnectivityMonitor(),
                eventStore: FileStoredCalendarEventsStore()
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
            let hub = CalendarDataAccountConsumerHub(
                consumers: [sources, events]
            )
            let disclosureStore = UserDefaultsGoogleConnectionDisclosureStore()
            let connection = GoogleAccountConnection(
                configuration: configuration,
                makeAdapter: { configured in
                    GoogleSignInSDKAdapter(configuration: configured)
                },
                disclosureStore: disclosureStore,
                connectivityMonitor: NWPathConnectivityMonitor(),
                installationBoundary: GoogleConnectionInstallationBoundary(
                    defaults: .standard,
                    deviceMarkerStore: KeychainGoogleConnectionDeviceMarkerStore(),
                    selectedSourceCalendarsStore:
                        UserDefaultsSelectedSourceCalendarsStore()
                ),
                calendarDataConsumer: hub
            )
            // Stored Calendar Events present at process start only for an
            // installation that has acknowledged the current disclosure;
            // an older acknowledgement keeps Calendar Events memory-only
            // until the revised explanation is acknowledged (ADR 0007).
            if (disclosureStore.acknowledgedDisclosureVersion() ?? 0)
                >= GoogleAccountConnection.currentDisclosureVersion
            {
                events.presentStoredCalendarEvents()
            }
            calendarEvents = events
            sourceCalendars = sources
            calendarDataHub = hub
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
