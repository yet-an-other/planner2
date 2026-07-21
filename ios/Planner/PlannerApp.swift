import SwiftUI

@main
struct PlannerApp: App {
    /// The Google Account Connection module, created only when the
    /// build-time release gate is on. While the gate is off, no connection
    /// behavior is initialized and the Calendar Screen renders the accepted
    /// 100-point iOS Calendar Header with neither connection seam mounted.
    private let accountConnection: GoogleAccountConnection?

    /// The Calendar Events module, created only when the build-time release
    /// gate is on. It fetches the primary Source Calendar's events directly
    /// from Google while the connection is connected, keeps them
    /// memory-only, and clears them on Disconnect on This Device.
    private let calendarEvents: CalendarEventsModel?

    init() {
        switch GoogleAccountConnectionConfiguration.load(from: .main) {
        case .gatedOff:
            accountConnection = nil
            calendarEvents = nil
        case let configuration:
            accountConnection = GoogleAccountConnection(
                configuration: configuration,
                makeAdapter: { configured in
                    GoogleSignInSDKAdapter(configuration: configured)
                },
                disclosureStore: UserDefaultsGoogleConnectionDisclosureStore(),
                connectivityMonitor: NWPathConnectivityMonitor(),
                installationBoundary: GoogleConnectionInstallationBoundary(
                    defaults: .standard,
                    deviceMarkerStore: KeychainGoogleConnectionDeviceMarkerStore()
                )
            )
            calendarEvents = CalendarEventsModel(
                environment: .current(),
                adapter: GoogleCalendarAPIAdapter(),
                connectivityMonitor: NWPathConnectivityMonitor()
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            CalendarScreen(
                environment: .current(),
                currentEnvironment: { .current() },
                connection: accountConnection,
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
