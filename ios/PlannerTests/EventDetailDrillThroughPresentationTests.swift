import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Planner

/// The drill-through's hosted-presentation seam: the Day Events Popover
/// and the Event Detail Popover are real native presentations, and the
/// drill-through presents the detail as the day list dismisses. The model
/// seam cannot reach UIKit's presentation transitions, so this suite hosts
/// the real Calendar Screen in a window inside the app test host, drives
/// the exact state sequence a day-list tap triggers, and asserts the Event
/// Detail Popover actually presents — across the dismissal timings that
/// used to tear the detail's cross-anchor presentation down with the
/// dismissing day list. The drilled-through detail anchors to the summoned
/// Date Cell's Events Overflow marker — the same anchor that presented the
/// Day Events Popover — so native presentations serialize instead of
/// racing.
@Suite("Event Detail Drill-Through Presentation")
@MainActor
struct EventDetailDrillThroughPresentationTests {
    /// The deterministic environment: Wednesday 2026-07-15 at noon GMT —
    /// the same fixed instant the Day Events Selection suite pins.
    private static let now = Date(timeIntervalSince1970: 1_784_116_800)
    private static let denseDay = gmt(2026, 7, 15)
    /// 2026-07-13, the Monday of the dense day's Week Row.
    private static let weekStart = gmt(2026, 7, 13)

    private static func makeEnvironment() -> CalendarEnvironment {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("GMT must be available for deterministic tests")
        }
        return CalendarEnvironment(
            now: now,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }

    private static func gmt(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }

    /// Six timed events on the dense day: the visible cap shows three
    /// rows, so the Date Cell carries an Events Overflow marker and the
    /// remaining events are cap-hidden behind it.
    private func makeDenseAdapter() -> FakeGoogleCalendarEventsAdapter {
        let adapter = FakeGoogleCalendarEventsAdapter()
        adapter.fetchHandler = { _, _ in
            .success(
                calendar: FakeGoogleCalendarEventsAdapter.defaultCalendar,
                events: (1...6).map { index in
                    GoogleCalendarEvent(
                        id: "dense-\(index)",
                        summary: "Dense \(index)",
                        start: .timed(Self.gmt(2026, 7, 15, 7 + index, 0)),
                        end: .timed(Self.gmt(2026, 7, 15, 7 + index, 30)),
                        isCancelled: false,
                        isDeclinedByViewer: false
                    )
                }
            )
        }
        return adapter
    }

    private func eventually(
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The topmost presented view controller above the window's root, if
    /// any overlay is currently presented.
    private func topPresentedViewController(
        in window: UIWindow
    ) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top === window.rootViewController ? nil : top
    }

    /// Collects every accessibility label in a view hierarchy, including
    /// SwiftUI-provided accessibility container elements.
    private func collectAccessibilityLabels(
        of element: NSObject,
        into labels: inout [String],
        depth: Int = 0
    ) {
        guard depth < 25 else { return }
        if let label = element.accessibilityLabel, !label.isEmpty {
            labels.append(label)
        }
        var children: [NSObject] = element.accessibilityElements as? [NSObject]
            ?? []
        if let view = element as? UIView {
            children.append(contentsOf: view.subviews)
        }
        for child in children {
            collectAccessibilityLabels(of: child, into: &labels, depth: depth + 1)
        }
    }

    private func presentedLabels(in window: UIWindow) -> [String] {
        guard let presented = topPresentedViewController(in: window) else {
            return []
        }
        var labels: [String] = []
        collectAccessibilityLabels(of: presented.view, into: &labels)
        return labels
    }

    /// Hosts the real Calendar Screen in a key window inside the app test
    /// host, summons the dense day's Day Events Popover, and drills through
    /// to one event with the production tap's exact state sequence: one
    /// model mutation that closes the day list and selects the event, so
    /// the two native presentations swap in a single view update on the
    /// same anchor. Returns the presented overlay's accessibility labels
    /// once the presentation settles.
    private func drillThrough(
        model: CalendarEventsModel,
        window: UIWindow,
        eventIndex: Int
    ) async -> [String] {
        // Summon the Day Events Popover exactly as the marker does.
        model.selectDayEvents(on: Self.denseDay)
        let dayListPresented = await eventually {
            topPresentedViewController(in: window) != nil
        }
        #expect(dayListPresented, "the Day Events Popover never presented")
        guard dayListPresented else { return [] }

        // The exact production drill-through sequence
        // (DayEventsPopoverPresentation.onSelectEvent): a single mutation.
        model.selectEvent(
            withID: canonicalID("dense-\(eventIndex)"),
            drilledFromDay: Self.denseDay
        )

        // The presentation must survive well past the day sheet's
        // dismissal transition, which occupies roughly a second.
        _ = await eventually(timeout: .seconds(2)) {
            presentedLabels(in: window).contains("WHEN")
        }
        return presentedLabels(in: window)
    }

    /// Hosts the real Calendar Screen with the dense day loaded and returns
    /// the model and window ready for drill-through scenarios.
    private func hostDenseDay() async -> (CalendarEventsModel, UIWindow) {
        let adapter = makeDenseAdapter()
        let model = CalendarEventsModel(
            environment: Self.makeEnvironment(),
            adapter: adapter,
            connectivityMonitor: FakeEventsConnectivityMonitor(),
            cadenceScheduler: FakeCalendarEventsCadenceScheduler(now: Self.now)
        )
        let environment = Self.makeEnvironment()
        let screen = CalendarScreen(
            environment: environment,
            currentEnvironment: { environment },
            events: model
        )
        let hosting = UIHostingController(rootView: screen)
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive })
            as? UIWindowScene ?? UIApplication.shared.connectedScenes.first
            as? UIWindowScene
        else {
            Issue.record("no window scene available for hosted presentation")
            return (model, UIWindow())
        }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = hosting
        window.makeKeyAndVisible()

        // Load the dense day through the model's own pipeline.
        model.setConnected(true)
        model.showVisibleRange(
            from: Self.weekStart,
            through: Self.gmt(2026, 7, 19)
        )
        let loaded = await eventually {
            model.weekLayouts[Self.weekStart]?.cells[2].overflowCount != nil
        }
        #expect(loaded, "the dense day never loaded")
        guard loaded else { return (model, window) }

        // Let SwiftUI settle layout so the marker's popover anchor exists.
        _ = await eventually(timeout: .milliseconds(500)) { false }
        return (model, window)
    }

    @Test("A visible row event drills through from the open day list")
    func visibleEventDrillsThrough() async {
        let (model, window) = await hostDenseDay()
        defer { window.isHidden = true }
        let labels = await drillThrough(
            model: model,
            window: window,
            eventIndex: 1
        )
        #expect(labels.contains("Dense 1"), "labels: \(labels)")
        #expect(
            labels.contains("WHEN"),
            "the Event Detail Popover did not present; labels: \(labels)"
        )
    }

    @Test("A cap-hidden event drills through to the marker anchor")
    func capHiddenEventDrillsThrough() async {
        let (model, window) = await hostDenseDay()
        defer { window.isHidden = true }
        let labels = await drillThrough(
            model: model,
            window: window,
            eventIndex: 5
        )
        #expect(labels.contains("Dense 5"), "labels: \(labels)")
        #expect(
            labels.contains("WHEN"),
            "the Event Detail Popover did not present; labels: \(labels)"
        )
    }

    @Test("Repeated drill-throughs keep presenting the Event Detail Popover")
    func repeatedDrillThroughs() async {
        let (model, window) = await hostDenseDay()
        defer { window.isHidden = true }
        for eventIndex in [1, 5, 2] {
            let labels = await drillThrough(
                model: model,
                window: window,
                eventIndex: eventIndex
            )
            let message = "round dense-\(eventIndex): the Event Detail "
                + "Popover did not present; labels: \(labels)"
            #expect(labels.contains("WHEN"), "\(message)")
            model.dismissEventDetail()
            _ = await eventually {
                topPresentedViewController(in: window) == nil
            }
        }
    }
}
