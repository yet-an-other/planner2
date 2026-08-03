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
///
/// The suite observes the presentation itself — a presented controller
/// that survives the dismissal transition alongside the surviving model
/// selection — and never the presented content's accessibility labels:
/// since iOS 26 SwiftUI renders popover content out of process, so the
/// in-process view hierarchy of the presented controller carries no
/// accessibility elements even while the popover is fully visible.
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

    /// Whether a native overlay is currently presented above the window's
    /// root view controller.
    private func overlayPresented(in window: UIWindow) -> Bool {
        topPresentedViewController(in: window) != nil
    }

    /// Hosts the real Calendar Screen in a key window inside the app test
    /// host, summons the dense day's Day Events Popover, and drills through
    /// to one event with the production tap's exact state sequence: one
    /// model mutation that closes the day list and selects the event, so
    /// the two native presentations swap in a single view update on the
    /// same anchor. Returns whether the Event Detail Popover presented and
    /// survived well past the day sheet's dismissal transition, which
    /// occupies roughly a second: an overlay remains presented, the drilled
    /// selection survives (a teardown writes `false` through the popover's
    /// source binding and clears it), and the day list stays closed.
    private func drillThrough(
        model: CalendarEventsModel,
        window: UIWindow,
        eventIndex: Int
    ) async -> Bool {
        // Summon the Day Events Popover exactly as the marker does.
        model.selectDayEvents(on: Self.denseDay)
        let dayListPresented = await eventually {
            overlayPresented(in: window)
        }
        #expect(dayListPresented, "the Day Events Popover never presented")
        guard dayListPresented else { return false }

        // The exact production drill-through sequence
        // (DayEventsPopoverPresentation.onSelectEvent): a single mutation.
        model.selectEvent(
            withID: canonicalID("dense-\(eventIndex)"),
            drilledFromDay: Self.denseDay
        )

        // Let the dismissal and presentation transitions settle, then
        // verify the surviving state: any overlay presented after this
        // window can only be the Event Detail Popover, since the day
        // list's binding has been false since the mutation.
        _ = await eventually(timeout: .seconds(2)) { false }
        return overlayPresented(in: window)
            && model.selectedEvent?.id == canonicalID("dense-\(eventIndex)")
            && model.selectedDayEvents == nil
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
        let presented = await drillThrough(
            model: model,
            window: window,
            eventIndex: 1
        )
        #expect(
            presented,
            "the drilled-through Event Detail Popover did not survive"
        )
    }

    @Test("A cap-hidden event drills through to the marker anchor")
    func capHiddenEventDrillsThrough() async {
        let (model, window) = await hostDenseDay()
        defer { window.isHidden = true }
        let presented = await drillThrough(
            model: model,
            window: window,
            eventIndex: 5
        )
        #expect(
            presented,
            "the cap-hidden drill-through Event Detail Popover did not survive"
        )
    }

    @Test("Repeated drill-throughs keep presenting the Event Detail Popover")
    func repeatedDrillThroughs() async {
        let (model, window) = await hostDenseDay()
        defer { window.isHidden = true }
        for eventIndex in [1, 5, 2] {
            let presented = await drillThrough(
                model: model,
                window: window,
                eventIndex: eventIndex
            )
            #expect(
                presented,
                "round dense-\(eventIndex): the Event Detail Popover did not survive"
            )
            model.dismissEventDetail()
            _ = await eventually {
                !overlayPresented(in: window)
            }
        }
    }
}
