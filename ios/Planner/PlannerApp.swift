import SwiftUI

@main
struct PlannerApp: App {
    /// The Google Account Connection module, created only when the
    /// build-time release gate is on. While the gate is off, no connection
    /// behavior is initialized and the Calendar Screen renders the accepted
    /// 100-point iOS Calendar Header with neither connection seam mounted.
    private let accountConnection: GoogleAccountConnection?

    init() {
        switch GoogleAccountConnectionConfiguration.load(from: .main) {
        case .gatedOff:
            accountConnection = nil
        case let configuration:
            accountConnection = GoogleAccountConnection(
                configuration: configuration,
                makeAdapter: { configured in
                    GoogleSignInSDKAdapter(configuration: configured)
                },
                disclosureStore: UserDefaultsGoogleConnectionDisclosureStore()
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            CalendarScreen(
                environment: .current(),
                currentEnvironment: { .current() },
                connection: accountConnection
            )
            .onOpenURL { url in
                // The reversed-client-ID scheme routes Google's OAuth
                // callback here; the module decides whether it is ours.
                _ = accountConnection?.handleCallbackURL(url)
            }
        }
    }
}
