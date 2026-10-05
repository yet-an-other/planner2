#if DEBUG
import SwiftUI

/// The Event Detail Popover's Maps-pin UI-test harness: a launch-argument
/// debug surface that presents the popover through the same native popover
/// presentation the Calendar Surface uses (adapting to a compact sheet),
/// with the openURL environment overridden so a Where-pin tap records the
/// dispatched URL into visible text instead of leaving the app. The
/// Maps-pin UI test drives it with `-eventDetailMapsPinHarness`;
/// `-eventDetailMapsPinAutoPresent` presents the popover immediately for
/// screenshot workflows. Debug builds only.
struct EventDetailMapsPinHarnessView: View {
    static let launchArgument = "-eventDetailMapsPinHarness"
    static let autoPresentArgument = "-eventDetailMapsPinAutoPresent"
    static let openButtonTitle = "Show Event Detail"
    static let openedPrefix = "OPENED:"
    static let notOpenedTitle = "NOT-OPENED"

    @State private var presented = false
    @State private var openedURL: URL?

    private static let detail = CalendarEventDetail(
        title: "Rehearsal",
        colorHex: "#039BE5",
        timingText: "Tue 10:00 – 11:00",
        location: "Studio 4, King Street, Copenhagen"
    )

    var body: some View {
        VStack(spacing: 24) {
            Button(Self.openButtonTitle) {
                presented = true
            }
            .buttonStyle(.borderedProminent)

            Text(
                openedURL.map {
                    "\(Self.openedPrefix)\($0.absoluteString)"
                } ?? Self.notOpenedTitle
            )
            .font(.body.monospaced())
            .accessibilityIdentifier("openURL-record")
            .textSelection(.enabled)
        }
        .padding()
        .popover(isPresented: $presented) {
            IOSEventDetailPopover(detail: Self.detail) {}
                .environment(\.openURL, OpenURLAction { url in
                    openedURL = url
                    return .handled
                })
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains(
                Self.autoPresentArgument
            ) {
                Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    presented = true
                }
            }
        }
    }
}
#endif
