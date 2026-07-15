import SwiftUI

@main
struct PlannerApp: App {
    var body: some Scene {
        WindowGroup {
            CalendarScreen(environment: .current())
        }
    }
}
