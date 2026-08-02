import Foundation
import Testing
@testable import Planner

/// Direct coverage of Calendar Event Fetch Orchestration (Planning
/// glossary) at its own interface: events in, commands out. These tests
/// pin the scheduling policy — serialization, priority, coalescing,
/// freshness, cadence, picker gating, and retry — with no fakes, no
/// tasks, and no clocks beyond a fixed `now`.
@Suite("Calendar Event Fetch Orchestration")
struct CalendarEventFetchOrchestrationTests {
    private typealias Orchestration = CalendarEventFetchOrchestration
    private typealias State = Orchestration.State
    private typealias Event = Orchestration.Event
    private typealias Command = Orchestration.Command
    private typealias FetchRange = Orchestration.FetchRange

    private static let now = gmt(2026, 7, 15, 12)

    /// The initial Fetched Window: three months before Today through
    /// three months after, as a half-open range.
    private static let initialWindow = FetchRange(
        start: gmt(2026, 4, 15),
        end: gmt(2026, 10, 16)
    )

    private static func makeEnvironment() -> CalendarEnvironment {
        CalendarEnvironment(
            now: now,
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
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

    private func handle(
        _ state: inout State,
        _ event: Event,
        now: Date = Self.now
    ) -> [Command] {
        Orchestration.handle(
            &state,
            event,
            environment: Self.makeEnvironment(),
            now: now
        )
    }

    /// Drives a state to a connected, fetched, foreground-active surface
    /// with a visible range in the middle of the window.
    private func makeFetchedState() -> State {
        var state = State()
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        _ = handle(&state, .fetchedWindowChanged(to: Self.initialWindow))
        _ = handle(
            &state,
            .fetchCompleted(.initial, .applied(Self.initialWindow))
        )
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 7, 13),
                end: Self.gmt(2026, 7, 20)
            )
        )
        return state
    }

    @Test("Connecting fetches the initial Fetched Window with progress copy")
    func connectFetchesInitialWindow() {
        var state = State()
        let commands = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        #expect(
            commands
                == [
                    .beginInitialFetch(
                        start: Self.gmt(2026, 4, 15),
                        end: Self.gmt(2026, 10, 16)
                    )
                ]
        )
        #expect(state.isFetchingInitialWindow)
        #expect(state.status.message == CalendarEventsCopy.loading)
    }

    @Test("The zero-source exception starts no request")
    func emptySelectionStartsNoRequest() {
        var state = State()
        let commands = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: true
            )
        )
        #expect(commands.isEmpty)
        #expect(!state.isFetchingInitialWindow)
    }

    @Test("Approaching the window's end grows it forward by two months")
    func forwardSlabGrowth() {
        var state = makeFetchedState()
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(
            commands
                == [
                    .extendWindow(
                        from: Self.gmt(2026, 10, 16),
                        to: Self.gmt(2026, 12, 16),
                        direction: .forward
                    )
                ]
        )
        #expect(state.isExtendingForward)
    }

    @Test("Approaching the window's start grows it backward by two months")
    func backwardSlabGrowth() {
        var state = makeFetchedState()
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 5, 15),
                end: Self.gmt(2026, 5, 20)
            )
        )
        #expect(
            commands
                == [
                    .extendWindow(
                        from: Self.gmt(2026, 2, 15),
                        to: Self.gmt(2026, 4, 15),
                        direction: .backward
                    )
                ]
        )
        #expect(state.isExtendingBackward)
    }

    @Test("A visible range mid-window starts no slab")
    func midWindowStartsNoSlab() {
        var state = makeFetchedState()
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 7, 20),
                end: Self.gmt(2026, 7, 27)
            )
        )
        #expect(commands.isEmpty)
    }

    @Test("Foreground entry refreshes the visible dates plus one-month buffers")
    func foregroundRefreshRange() {
        var state = makeFetchedState()
        let commands = handle(&state, .sceneActive(true))
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                ]
        )
        #expect(state.isRefreshing)
    }

    @Test("A refresh never expands the Fetched Window")
    func refreshClampsToWindow() {
        var state = makeFetchedState()
        // Visible dates reach toward the window's end: the slab fetch
        // that would grow it fails, and the owed refresh clamps its
        // one-month buffer to the window that actually exists.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 20)
            )
        )
        #expect(state.isExtendingForward)
        _ = handle(&state, .foregroundRefresh)
        let commands = handle(
            &state,
            .fetchCompleted(.slabForward, .failed(.offline))
        )
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 8, 7),
                        end: Self.gmt(2026, 10, 16)
                    )
                ]
        )
    }

    @Test("A pending refresh runs when the slab ahead of it completes")
    func refreshWaitsForSlab() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        // The foreground refresh is in flight; a changed visible range
        // coalesces behind it rather than duplicating the request.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 8, 3),
                end: Self.gmt(2026, 8, 10)
            )
        )
        let commands = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        // Fresh coverage suppresses the owed browsing refresh.
        #expect(commands.isEmpty)
        #expect(state.wantsCadence)
    }

    @Test("Stale visible coverage refreshes once freshness expires")
    func staleCoverageRefreshes() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        // Six minutes later, a visible-range change finds the coverage
        // stale and refreshes.
        let later = Self.now.addingTimeInterval(6 * 60)
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 7, 20),
                end: Self.gmt(2026, 7, 27)
            ),
            now: later
        )
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 20),
                        end: Self.gmt(2026, 8, 27)
                    )
                ]
        )
    }

    @Test("A failed slab blocks immediate retry but not a pending refresh")
    func failedSlabBlocksRetry() {
        var state = makeFetchedState()
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(state.isExtendingForward)

        // A foreground signal coalesces behind the slab.
        _ = handle(&state, .foregroundRefresh)
        #expect(state.isRefreshPending)

        // The slab fails offline: blocked, partial-failure copy, and the
        // owed refresh runs inside the fetched range instead.
        let commands = handle(
            &state,
            .fetchCompleted(.slabForward, .failed(.offline))
        )
        #expect(state.isSlabRetryBlocked)
        #expect(state.status.message == CalendarEventsCopy.offlinePartial)
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 8, 7),
                        end: Self.gmt(2026, 10, 15)
                    )
                ]
        )
    }

    @Test("A failed refresh keeps its warning and retries on connectivity return")
    func failedRefreshRetriesOnConnectivity() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(&state, .fetchCompleted(.refresh, .failed(.offline)))
        #expect(state.status.message == CalendarEventsCopy.refreshOffline)
        #expect(state.status.tone == .warning)

        let commands = handle(&state, .connectivityReturned)
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                ]
        )
    }

    @Test("An open picker pauses work; a changed dismissal replaces the selection")
    func pickerGatesAndReplaces() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )

        _ = handle(&state, .pickerPresented)
        #expect(!state.wantsCadence)
        // Signals coalesce but nothing starts while the picker is open.
        let paused = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(paused.isEmpty)
        #expect(!state.isExtendingForward)

        let commands = handle(&state, .pickerDismissed(selectionChanged: true))
        // Three clamped months around the latest visible dates.
        #expect(commands.count == 1)
        guard case .replaceSelection(let start, let end) = commands.first
        else {
            Issue.record("a changed dismissal must replace the selection")
            return
        }
        #expect(start == Self.gmt(2026, 6, 7))
        #expect(end == Self.gmt(2026, 12, 16))
        #expect(state.isReplacingSelection)
        #expect(state.status.message == CalendarEventsCopy.updatingSelection)
    }

    @Test("An unchanged dismissal resumes without a replacement")
    func unchangedDismissalResumes() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        _ = handle(&state, .pickerPresented)
        let commands = handle(&state, .pickerDismissed(selectionChanged: false))
        #expect(commands.isEmpty)
        #expect(!state.isReplacingSelection)
        #expect(state.wantsCadence)
    }

    @Test("Selection replacement leads slabs and refreshes")
    func replacementHasPriority() {
        var state = makeFetchedState()
        // Approach the window's edge so a slab is owed, then replace.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(state.isExtendingForward)
        _ = handle(&state, .pickerPresented)
        _ = handle(
            &state,
            .fetchCompleted(
                .slabForward,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 10, 16),
                        end: Self.gmt(2026, 12, 16)
                    )
                )
            )
        )
        _ = handle(&state, .pickerDismissed(selectionChanged: true))
        // The replacement owns the seam; the re-approach slabs only
        // after it applies.
        #expect(state.isReplacingSelection)
        let newWindow = FetchRange(
            start: Self.gmt(2026, 6, 7),
            end: Self.gmt(2026, 12, 16)
        )
        _ = handle(&state, .fetchedWindowChanged(to: newWindow))
        let commands = handle(
            &state,
            .fetchCompleted(.selectionReplacement, .applied(newWindow))
        )
        #expect(!state.isReplacingSelection)
        // Visible dates are mid-window now: nothing further is owed.
        #expect(commands.isEmpty)
    }

    @Test("A failed selection replacement stays owed with its warning")
    func failedReplacementStaysOwed() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        _ = handle(&state, .pickerPresented)
        _ = handle(&state, .pickerDismissed(selectionChanged: true))
        let commands = handle(
            &state,
            .fetchCompleted(.selectionReplacement, .failed(.failed))
        )
        #expect(commands.isEmpty)
        #expect(state.isSelectionReplacementPending)
        #expect(state.status.message == CalendarEventsCopy.refreshFailed)

        // Connectivity return retries the owed replacement.
        let retry = handle(&state, .connectivityReturned)
        #expect(retry.count == 1)
        guard case .replaceSelection = retry.first else {
            Issue.record("connectivity return must retry the replacement")
            return
        }
    }

    @Test("Scene inactivity suppresses refresh and cadence")
    func inactiveSceneSuppressesWork() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        #expect(state.wantsCadence)

        let commands = handle(&state, .sceneActive(false))
        #expect(commands.isEmpty)
        #expect(!state.wantsCadence)

        // A visible-range change while backgrounded starts no refresh:
        // the browsing freshness decision is scene-gated.
        let backgrounded = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 7, 20),
                end: Self.gmt(2026, 7, 27)
            )
        )
        #expect(backgrounded.isEmpty)
        #expect(!state.isRefreshing)
    }

    @Test("A stale completion releases the seam and resumes current work")
    func staleCompletionResumes() {
        var state = State()
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        #expect(state.isFetchingInitialWindow)
        // A newer connection decision discards the in-flight request's
        // results; the physical completion still releases the seam and
        // the new connection's initial fetch starts.
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        let commands = handle(
            &state,
            .fetchCompleted(.initial, .discarded)
        )
        #expect(
            commands
                == [
                    .beginInitialFetch(
                        start: Self.gmt(2026, 4, 15),
                        end: Self.gmt(2026, 10, 16)
                    )
                ]
        )
    }

    @Test("Disconnect resets scheduling state")
    func disconnectResets() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(&state, .fetchCompleted(.refresh, .failed(.offline)))
        let commands = handle(
            &state,
            .connectionPublished(
                connected: false,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        #expect(commands.isEmpty)
        #expect(!state.isConnected)
        #expect(state.fetchedWindow == nil)
        #expect(state.refreshFailure == nil)
        #expect(!state.isRefreshPending)
        #expect(!state.isSlabRetryBlocked)
        #expect(state.status.message == nil)
        #expect(!state.wantsCadence)
    }

    @Test("Reconnecting behind physical work queues the initial fetch")
    func reconnectQueuesBehindInFlight() {
        var state = State()
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        // Disconnect and reconnect while the first request is still
        // physically in flight: the reconnect cannot duplicate it.
        _ = handle(
            &state,
            .connectionPublished(
                connected: false,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        let commands = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        #expect(commands.isEmpty)
        // The stale completion releases the seam; the new connection's
        // initial fetch starts then.
        let resumed = handle(&state, .fetchCompleted(.initial, .discarded))
        #expect(
            resumed
                == [
                    .beginInitialFetch(
                        start: Self.gmt(2026, 4, 15),
                        end: Self.gmt(2026, 10, 16)
                    )
                ]
        )
    }

    @Test("Selection replacement clips to the Extended Calendar Range")
    func replacementClipsToExtendedRange() {
        var state = State()
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            )
        )
        _ = handle(&state, .fetchedWindowChanged(to: Self.initialWindow))
        _ = handle(
            &state,
            .fetchCompleted(.initial, .applied(Self.initialWindow))
        )
        // The viewer has scrolled near the Extended Calendar Range's
        // start (the week containing 2016-07-15: Monday 2016-07-11).
        _ = handle(&state, .pickerPresented)
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2016, 8, 3),
                end: Self.gmt(2016, 8, 10)
            )
        )
        let commands = handle(&state, .pickerDismissed(selectionChanged: true))
        #expect(
            commands
                == [
                    .replaceSelection(
                        start: Self.gmt(2016, 7, 11),
                        end: Self.gmt(2016, 11, 11)
                    )
                ]
        )
    }

    @Test("A refresh waiting for a slab uses the latest visible range")
    func refreshUsesLatestVisibleRange() {
        var state = makeFetchedState()
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(state.isExtendingForward)
        _ = handle(&state, .sceneActive(true))
        #expect(state.isRefreshPending)
        // The visible range moves while the slab is in flight.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 14),
                end: Self.gmt(2026, 9, 21)
            )
        )
        let newWindow = FetchRange(
            start: Self.gmt(2026, 4, 15),
            end: Self.gmt(2026, 12, 16)
        )
        _ = handle(&state, .fetchedWindowChanged(to: newWindow))
        let commands = handle(
            &state,
            .fetchCompleted(
                .slabForward,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 10, 16),
                        end: Self.gmt(2026, 12, 16)
                    )
                )
            )
        )
        // The refresh clamps the newest visible dates against the newest
        // window — not the range that was visible when it coalesced.
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 8, 14),
                        end: Self.gmt(2026, 10, 21)
                    )
                ]
        )
    }

    @Test("A slab waits for an in-flight refresh")
    func slabWaitsForRefresh() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        #expect(state.isRefreshing)
        let blocked = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        #expect(blocked.isEmpty)
        #expect(!state.isExtendingForward)
        let commands = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        // The serialized seam released: the owed slab starts, ahead of
        // any browsing freshness decision.
        #expect(
            commands
                == [
                    .extendWindow(
                        from: Self.gmt(2026, 10, 16),
                        to: Self.gmt(2026, 12, 16),
                        direction: .forward
                    )
                ]
        )
    }

    @Test("Connectivity return during an offline refresh queues one retry")
    func connectivityDuringRefreshQueuesOneRetry() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        #expect(state.isRefreshing)
        // The recovery signal arrives while the request that observed the
        // offline state is still in flight: it coalesces, never loops.
        _ = handle(&state, .connectivityReturned)
        #expect(state.isRefreshPending)
        let commands = handle(
            &state,
            .fetchCompleted(.refresh, .failed(.offline))
        )
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                ]
        )
        #expect(!state.isRefreshPending)
    }

    @Test("A completion later than the clock cannot count as fresh")
    func futureCompletionIsNotFresh() {
        var state = State()
        let future = Self.now.addingTimeInterval(60)
        _ = handle(
            &state,
            .connectionPublished(
                connected: true,
                usesResolvedSelection: true,
                selectionIsEmpty: false
            ),
            now: future
        )
        _ = handle(
            &state,
            .fetchedWindowChanged(to: Self.initialWindow),
            now: future
        )
        _ = handle(
            &state,
            .fetchCompleted(.initial, .applied(Self.initialWindow)),
            now: future
        )
        _ = handle(&state, .sceneActive(true), now: future)
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            ),
            now: future
        )
        // At an earlier clock reading every coverage record is "from the
        // future" and counts for nothing: the range is stale.
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 7, 20),
                end: Self.gmt(2026, 7, 27)
            )
        )
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 20),
                        end: Self.gmt(2026, 8, 27)
                    )
                ]
        )
    }

    @Test("Fresh initial and slab coverage jointly suppress a browsing refresh")
    func jointCoverageSuppresses() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        let newWindow = FetchRange(
            start: Self.gmt(2026, 4, 15),
            end: Self.gmt(2026, 12, 16)
        )
        _ = handle(&state, .fetchedWindowChanged(to: newWindow))
        _ = handle(
            &state,
            .fetchCompleted(
                .slabForward,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 10, 16),
                        end: Self.gmt(2026, 12, 16)
                    )
                )
            )
        )
        // The bounded range straddles the old window's end: the initial
        // and slab coverage meet there, leaving no gap.
        let commands = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 14),
                end: Self.gmt(2026, 9, 21)
            )
        )
        #expect(commands.isEmpty)
        #expect(!state.isRefreshPending)
    }

    @Test("A fresh slab cannot hide stale partial range coverage")
    func freshSlabCannotHideGap() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        _ = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 15)
            )
        )
        let newWindow = FetchRange(
            start: Self.gmt(2026, 4, 15),
            end: Self.gmt(2026, 12, 16)
        )
        _ = handle(&state, .fetchedWindowChanged(to: newWindow))
        // The viewer browses to a range straddling the fresh slab's edge
        // while the slab is still in flight.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 14),
                end: Self.gmt(2026, 10, 21)
            )
        )
        // The slab completes six minutes after the initial window and
        // refresh: only its coverage is still fresh.
        let later = Self.now.addingTimeInterval(6 * 60)
        let commands = handle(
            &state,
            .fetchCompleted(
                .slabForward,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 10, 16),
                        end: Self.gmt(2026, 12, 16)
                    )
                )
            ),
            now: later
        )
        // The fresh slab covers the bounded range's tail, but the
        // expired coverage leaves the rest uncovered: a gap is a gap.
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 8, 14),
                        end: Self.gmt(2026, 11, 21)
                    )
                ]
        )
    }

    @Test("Browsing during a refresh follows up with the latest stale range")
    func browsingFollowsUpWithLatestStaleRange() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        #expect(state.isRefreshing)
        // The viewer browses while the refresh is in flight; the owed
        // freshness decision waits for it.
        _ = handle(
            &state,
            .visibleRange(
                start: Self.gmt(2026, 9, 7),
                end: Self.gmt(2026, 9, 14)
            )
        )
        let later = Self.now.addingTimeInterval(6 * 60)
        let commands = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            ),
            now: later
        )
        // The completed refresh covers only part of the latest bounded
        // range; the follow-up uses that range, not the coalesced one.
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 8, 7),
                        end: Self.gmt(2026, 10, 14)
                    )
                ]
        )
    }

    @Test("Timer and lifecycle signals coalesce behind one in-flight refresh")
    func signalsCoalesceBehindRefresh() {
        var state = makeFetchedState()
        _ = handle(&state, .sceneActive(true))
        #expect(state.isRefreshing)
        _ = handle(&state, .cadenceFired)
        _ = handle(&state, .foregroundRefresh)
        _ = handle(&state, .connectivityReturned)
        #expect(state.isRefreshPending)
        let commands = handle(
            &state,
            .fetchCompleted(
                .refresh,
                .applied(
                    FetchRange(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                )
            )
        )
        // However many signals arrived, exactly one refresh follows.
        #expect(
            commands
                == [
                    .refresh(
                        start: Self.gmt(2026, 6, 13),
                        end: Self.gmt(2026, 8, 20)
                    )
                ]
        )
    }
}
