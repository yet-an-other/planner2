import SwiftUI

@main
struct PlannerApp: App {
    /// The build-time release gate and environment-specific inputs for the
    /// Google Account Connection, fixed for this build. While the gate is
    /// off, the Calendar Screen mounts no connection behavior at all.
    private let accountConnection = GoogleAccountConnectionConfiguration.load(
        from: .main
    )

    var body: some Scene {
        WindowGroup {
            CalendarScreen(
                environment: .current(),
                currentEnvironment: { .current() },
                accountConnection: accountConnection
            )
        }
    }
}
