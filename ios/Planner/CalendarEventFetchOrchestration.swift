import Foundation

/// Calendar Event Fetch Orchestration (Planning glossary): the scheduling
/// of Calendar Event fetches behind one serialized request at a time.
/// This module owns every fetch-work decision — initial Fetched Window
/// fetch, Fetched Window growth slabs, bounded Calendar Event Refresh,
/// selection replacement, browsing freshness, cadence, picker gating, and
/// connectivity retry — as a pure reducer: events in, commands out. The
/// Calendar Events model executes the commands through the adapter and
/// reports their outcomes back as events, so policy is testable without
/// fakes, tasks, or clocks.
enum CalendarEventFetchOrchestration {
    /// A half-open local-date range, as start-of-day instants.
    struct FetchRange: Equatable, Sendable {
        var start: Date
        var end: Date
    }

    /// One successful request's half-open date coverage and completion
    /// time. Process-local bookkeeping only: never persisted, vanishing
    /// with Disconnect on This Device or model teardown.
    struct FreshnessCoverage: Equatable, Sendable {
        let start: Date
        let end: Date
        let completedAt: Date
    }

    /// Which serialized request a completion belongs to.
    enum FetchKind: Equatable, Sendable {
        case initial
        case refresh
        case slabForward
        case slabBackward
        case selectionReplacement
    }

    /// One slab direction of the Fetched Window.
    enum ExtensionDirection: Equatable, Sendable {
        case forward
        case backward
    }

    /// The outcome of one serialized request. `.applied` carries the
    /// fetched range for freshness coverage; `.discarded` is a stale
    /// completion whose results a newer connection decision threw away
    /// but whose physical request still releases the serialized seam.
    enum FetchResult: Equatable, Sendable {
        case applied(FetchRange)
        case failed(GoogleCalendarEventsFailure)
        case discarded
    }

    /// Every signal the scheduler acts on, reported by the Calendar
    /// Events model. The model owns all effects; outcomes it applies are
    /// reported here so the state below stays purely decision state.
    enum Event: Equatable, Sendable {
        /// A connection publication from either connection seam: the
        /// legacy Primary-only path (`usesResolvedSelection: false`) or
        /// the disclosure-gated, reconciled selection. Carries the
        /// resolved selection's emptiness so the zero-source exception
        /// starts no request.
        case connectionPublished(
            connected: Bool,
            usesResolvedSelection: Bool,
            selectionIsEmpty: Bool
        )
        case pickerPresented
        case pickerDismissed(selectionChanged: Bool)
        case visibleRange(start: Date, end: Date)
        case sceneActive(Bool)
        /// A foreground return requesting the immediate bounded refresh.
        case foregroundRefresh
        case connectivityReturned
        case cadenceFired
        case fetchCompleted(FetchKind, FetchResult)
        /// The model applied a Fetched Window change from a successful
        /// response.
        case fetchedWindowChanged(to: FetchRange?)
    }

    /// One fetch the model must execute through the serialized adapter
    /// seam. Policy guarantees at most one is outstanding: the state
    /// records the in-flight kind when the command is emitted.
    enum Command: Equatable, Sendable {
        case beginInitialFetch(start: Date, end: Date)
        case extendWindow(from: Date, to: Date, direction: ExtensionDirection)
        case refresh(start: Date, end: Date)
        case replaceSelection(start: Date, end: Date)
    }

    /// Pure decision state. The Fetched Window is recorded from
    /// `.fetchedWindowChanged` events, never recomputed here; freshness
    /// coverage is updated only on `.applied` completions.
    struct State: Equatable, Sendable {
        /// Whether the module treats the Google Account Connection as
        /// connected; repeated reports of the same state are no-ops.
        var isConnected = false
        /// Whether the selection arrives reconciled from the Source
        /// Calendars module (vs. the legacy Primary-only path).
        var usesResolvedSourceCalendars = false
        /// The resolved selection's emptiness at publication: the
        /// zero-source exception starts no request.
        var selectionIsEmpty = false
        /// Whether the iOS scene is foreground-active. Calendar Event
        /// Refresh cadence exists only while this and the connection are
        /// both active.
        var isSceneActive = false
        /// Routine Calendar Event work pauses while the native Source
        /// Calendar Picker is open. Signals still coalesce in their
        /// pending flags.
        var isPickerPresented = false
        /// The last visible range reported by the Calendar Screen,
        /// re-checked when connectivity returns so owed slabs retry.
        var lastVisibleRange: FetchRange?
        /// The recorded Fetched Window: `[start, end)` as start-of-day
        /// instants, reported by the model as it applies responses.
        var fetchedWindow: FetchRange?
        /// Whether the initial Fetched Window fetch is in flight.
        var isFetchingInitialWindow = false
        /// Whether a bounded Calendar Event Refresh is in flight.
        var isRefreshing = false
        /// Foreground and recovery signals coalesce here while another
        /// Calendar Event request owns the serialized adapter seam.
        var isRefreshPending = false
        /// A final changed selection owes one whole-snapshot,
        /// visible-centered replacement. It takes priority over slabs and
        /// bounded refreshes.
        var isSelectionReplacementPending = false
        /// Whether that replacement currently owns the serialized seam.
        var isReplacingSelection = false
        /// A changed visible range leaves one freshness decision owed
        /// while another request owns the serialized adapter seam.
        var needsBrowsingFreshnessCheck = false
        /// In-flight slab directions, so repeated edge approaches can
        /// never duplicate a fetch.
        var isExtendingForward = false
        var isExtendingBackward = false
        /// A failed slab waits for another visible-range or connectivity
        /// signal instead of looping immediately through follow-up work.
        var isSlabRetryBlocked = false
        /// A failed Calendar Event Refresh remains owed so connectivity
        /// return can retry it and other progress can restore its
        /// warning.
        var refreshFailure: GoogleCalendarEventsFailure?
        /// Successful initial, slab, and refresh completion coverage.
        var freshnessCoverage: [FreshnessCoverage] = []
        /// The iOS Header Status for the Calendar Events area. Owned here
        /// because progress and failure copy transition with scheduling
        /// decisions; the model publishes it verbatim.
        var status = CalendarEventsStatus(message: nil, tone: .info)

        /// Whether one serialized adapter request is outstanding.
        var hasFetchInFlight: Bool {
            isFetchingInitialWindow || isRefreshing || isExtendingForward
                || isExtendingBackward || isReplacingSelection
        }

        /// Whether the five-minute foreground cadence should currently be
        /// scheduled: every bounded-refresh input is present and no
        /// serialized work is outstanding. The model reconciles its
        /// schedule handle against this after every event, keeping
        /// cadence completion-relative.
        var wantsCadence: Bool {
            !hasFetchInFlight && isConnected && !isPickerPresented
                && isSceneActive
                && (fetchedWindow != nil || isSelectionReplacementPending)
                && lastVisibleRange != nil
        }
    }

    /// Foreground Calendar Event Refresh waits five minutes after the
    /// prior serialized Calendar Event request attempt completes.
    static let cadenceIntervalSeconds: TimeInterval = 5 * 60
    static let cadenceInterval: Duration = .seconds(cadenceIntervalSeconds)

    /// Applies one event to the decision state and returns the fetch
    /// commands the model must execute. Environment and clock arrive per
    /// call; the reducer holds no dependencies.
    static func handle(
        _ state: inout State,
        _ event: Event,
        environment: CalendarEnvironment,
        now: Date
    ) -> [Command] {
        switch event {
        case .connectionPublished(
            let connected,
            let usesResolved,
            let selectionIsEmpty
        ):
            state.usesResolvedSourceCalendars = usesResolved
            state.selectionIsEmpty = selectionIsEmpty
            state.isConnected = connected
            state.isPickerPresented = false
            state.isSelectionReplacementPending = false
            state.fetchedWindow = nil
            state.freshnessCoverage = []
            state.needsBrowsingFreshnessCheck = false
            state.isRefreshPending = false
            state.refreshFailure = nil
            state.isSlabRetryBlocked = false
            state.status = CalendarEventsStatus(message: nil, tone: .info)
            guard connected else {
                return []
            }
            return initialFetchDecision(&state, environment: environment)

        case .pickerPresented:
            guard state.isConnected, !state.isPickerPresented else {
                return []
            }
            state.isPickerPresented = true
            return []

        case .pickerDismissed(let selectionChanged):
            guard state.isConnected, state.isPickerPresented else {
                return []
            }
            state.isPickerPresented = false
            if selectionChanged {
                state.isSelectionReplacementPending = true
                state.refreshFailure = nil
                state.status = CalendarEventsStatus(
                    message: CalendarEventsCopy.updatingSelection,
                    tone: .info
                )
            }
            return drain(&state, environment: environment, now: now)

        case .visibleRange(let start, let end):
            if state.lastVisibleRange?.start != start
                || state.lastVisibleRange?.end != end
            {
                state.needsBrowsingFreshnessCheck = true
            }
            state.lastVisibleRange = FetchRange(start: start, end: end)
            state.isSlabRetryBlocked = false
            return drain(&state, environment: environment, now: now)

        case .sceneActive(let active):
            guard active != state.isSceneActive else {
                return []
            }
            state.isSceneActive = active
            guard active else {
                state.isRefreshPending = false
                return []
            }
            guard state.isConnected else {
                return []
            }
            if state.isSelectionReplacementPending {
                return drain(&state, environment: environment, now: now)
            }
            if state.fetchedWindow == nil {
                return initialFetchDecision(&state, environment: environment)
            }
            return requestRefreshDecision(
                &state,
                environment: environment,
                now: now
            )

        case .foregroundRefresh:
            if state.isSceneActive {
                return requestRefreshDecision(
                    &state,
                    environment: environment,
                    now: now
                )
            }
            return handle(
                &state,
                .sceneActive(true),
                environment: environment,
                now: now
            )

        case .connectivityReturned:
            guard state.isConnected else {
                return []
            }
            state.isSlabRetryBlocked = false
            if state.isSelectionReplacementPending {
                return drain(&state, environment: environment, now: now)
            }
            if state.fetchedWindow == nil {
                return initialFetchDecision(&state, environment: environment)
            }
            if state.isRefreshing || state.refreshFailure != nil {
                return requestRefreshDecision(
                    &state,
                    environment: environment,
                    now: now
                )
            }
            guard state.lastVisibleRange != nil else {
                return []
            }
            return drain(&state, environment: environment, now: now)

        case .cadenceFired:
            if state.isSelectionReplacementPending {
                return drain(&state, environment: environment, now: now)
            }
            return requestRefreshDecision(
                &state,
                environment: environment,
                now: now
            )

        case .fetchedWindowChanged(let range):
            state.fetchedWindow = range
            return []

        case .fetchCompleted(let kind, let result):
            switch kind {
            case .initial:
                state.isFetchingInitialWindow = false
            case .refresh:
                state.isRefreshing = false
            case .slabForward:
                state.isExtendingForward = false
            case .slabBackward:
                state.isExtendingBackward = false
            case .selectionReplacement:
                state.isReplacingSelection = false
            }

            switch result {
            case .discarded:
                // A stale completion releases the serialized seam;
                // continue the current connection's work.
                guard state.isConnected else {
                    return []
                }
                if state.isSelectionReplacementPending {
                    return drain(&state, environment: environment, now: now)
                }
                if state.fetchedWindow == nil {
                    return initialFetchDecision(
                        &state,
                        environment: environment
                    )
                }
                return drain(&state, environment: environment, now: now)

            case .applied(let range):
                switch kind {
                case .selectionReplacement:
                    state.freshnessCoverage = []
                    recordFreshness(
                        &state,
                        for: range,
                        completedAt: now
                    )
                    state.refreshFailure = nil
                    state.isSelectionReplacementPending = false
                    setIdleStatusIfIdle(&state)
                    return drain(&state, environment: environment, now: now)
                case .refresh:
                    recordFreshness(&state, for: range, completedAt: now)
                    state.refreshFailure = nil
                    setIdleStatusIfIdle(&state)
                    return drain(&state, environment: environment, now: now)
                case .slabForward, .slabBackward:
                    recordFreshness(&state, for: range, completedAt: now)
                    state.isSlabRetryBlocked = false
                    setIdleStatusIfIdle(&state)
                    return drain(&state, environment: environment, now: now)
                case .initial:
                    recordFreshness(&state, for: range, completedAt: now)
                    setIdleStatusIfIdle(&state)
                    return drain(&state, environment: environment, now: now)
                }

            case .failed(let failure):
                switch kind {
                case .initial:
                    state.status = initialFailureStatus(failure)
                    return []
                case .refresh:
                    state.refreshFailure = failure
                    setIdleStatusIfIdle(&state)
                    return drain(&state, environment: environment, now: now)
                case .slabForward, .slabBackward:
                    state.status = slabFailureStatus(failure)
                    // Do not immediately retry the failed slab. A pending
                    // foreground refresh may still run inside the fetched
                    // range.
                    state.isSlabRetryBlocked = true
                    return drain(&state, environment: environment, now: now)
                case .selectionReplacement:
                    // Keep the prior snapshot, Fetched Window, selected
                    // detail, and freshness. The new durable selection
                    // remains desired.
                    state.refreshFailure = failure
                    state.isSelectionReplacementPending = true
                    setIdleStatusIfIdle(&state)
                    return []
                }
            }
        }
    }

    // MARK: Decisions

    /// Fetches the initial Fetched Window — three months before Today
    /// through three months after — when nothing is fetched, nothing is
    /// in flight, the picker is closed, and the selection permits a
    /// request.
    private static func initialFetchDecision(
        _ state: inout State,
        environment: CalendarEnvironment
    ) -> [Command] {
        guard state.fetchedWindow == nil, !state.hasFetchInFlight,
              !state.isPickerPresented,
              !state.usesResolvedSourceCalendars || !state.selectionIsEmpty
        else {
            return []
        }

        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        guard
            let windowStart = addMonthsClamped(
                -3,
                to: today,
                environment: environment
            ),
            let lastDay = addMonthsClamped(
                3,
                to: today,
                environment: environment
            ),
            let windowEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDay
            )
        else {
            return []
        }

        state.isFetchingInitialWindow = true
        state.status = CalendarEventsStatus(
            message: CalendarEventsCopy.loading,
            tone: .info
        )
        return [.beginInitialFetch(start: windowStart, end: windowEnd)]
    }

    /// Coalesces one refresh signal against current scene and range
    /// state, then drains.
    private static func requestRefreshDecision(
        _ state: inout State,
        environment: CalendarEnvironment,
        now: Date
    ) -> [Command] {
        guard state.isConnected, state.isSceneActive,
              (state.fetchedWindow != nil
                  || state.isSelectionReplacementPending),
              state.lastVisibleRange != nil
        else {
            return []
        }
        state.isRefreshPending = true
        return drain(&state, environment: environment, now: now)
    }

    /// The one scheduling decision point. Calendar API requests share one
    /// serialized seam: selection replacement leads, then slab expansion
    /// — ahead of a pending refresh so the latter clamps against the
    /// latest Fetched Window — then the owed browsing freshness check,
    /// then the coalesced refresh. All decisions use the newest visible
    /// range.
    private static func drain(
        _ state: inout State,
        environment: CalendarEnvironment,
        now: Date
    ) -> [Command] {
        guard !state.hasFetchInFlight, state.isConnected,
              !state.isPickerPresented
        else {
            return []
        }

        if state.isSelectionReplacementPending {
            guard let visible = state.lastVisibleRange,
                  let range = selectionReplacementRange(
                      visible: visible,
                      environment: environment
                  )
            else {
                return []
            }
            state.isSelectionReplacementPending = false
            state.isReplacingSelection = true
            state.status = CalendarEventsStatus(
                message: CalendarEventsCopy.updatingSelection,
                tone: .info
            )
            return [.replaceSelection(start: range.start, end: range.end)]
        }

        guard let window = state.fetchedWindow,
              let visible = state.lastVisibleRange
        else {
            return []
        }

        let calendar = environment.calendar
        if !state.isSlabRetryBlocked,
           let lastFetchedDay = calendar.date(
               byAdding: .day,
               value: -1,
               to: window.end
           ),
           let forwardTrigger = addMonthsClamped(
               -1,
               to: lastFetchedDay,
               environment: environment
           ),
           visible.end >= forwardTrigger,
           let newLastDay = addMonthsClamped(
               2,
               to: lastFetchedDay,
               environment: environment
           ),
           let proposedEnd = calendar.date(
               byAdding: .day,
               value: 1,
               to: newLastDay
           ),
           let extendedRange = extendedCalendarRange(
               environment: environment
           ),
           case let newEnd = min(proposedEnd, extendedRange.end),
           newEnd > window.end
        {
            state.isExtendingForward = true
            state.status = CalendarEventsStatus(
                message: CalendarEventsCopy.loading,
                tone: .info
            )
            return [
                .extendWindow(
                    from: window.end,
                    to: newEnd,
                    direction: .forward
                )
            ]
        }

        if !state.isSlabRetryBlocked,
           let backwardTrigger = addMonthsClamped(
               1,
               to: window.start,
               environment: environment
           ),
           visible.start <= backwardTrigger,
           let proposedStart = addMonthsClamped(
               -2,
               to: window.start,
               environment: environment
           ),
           let extendedRange = extendedCalendarRange(
               environment: environment
           ),
           case let newStart = max(proposedStart, extendedRange.start),
           newStart < window.start
        {
            state.isExtendingBackward = true
            state.status = CalendarEventsStatus(
                message: CalendarEventsCopy.loading,
                tone: .info
            )
            return [
                .extendWindow(
                    from: newStart,
                    to: window.start,
                    direction: .backward
                )
            ]
        }

        if state.needsBrowsingFreshnessCheck, state.isSceneActive,
           let range = boundedRefreshRange(
               window: window,
               visible: visible,
               environment: environment
           )
        {
            state.needsBrowsingFreshnessCheck = false
            if !isFresh(state.freshnessCoverage, range: range, at: now) {
                state.isRefreshPending = true
            }
        }

        guard state.isRefreshPending, state.isSceneActive else {
            return []
        }
        guard let range = boundedRefreshRange(
            window: window,
            visible: visible,
            environment: environment
        ) else {
            // A visible range can sit beyond a failed expansion slab.
            // Keep the coalesced refresh owed; cadence re-arms instead of
            // losing it or spinning while no bounded overlap exists.
            return []
        }
        state.isRefreshPending = false
        state.isRefreshing = true
        return [.refresh(start: range.start, end: range.end)]
    }

    // MARK: Status

    /// Clears the status once no fetch work remains in flight; failure
    /// copy stays until fresh progress or a success supersedes it.
    private static func setIdleStatusIfIdle(_ state: inout State) {
        guard !state.hasFetchInFlight else {
            return
        }
        state.status = switch state.refreshFailure {
        case .offline:
            CalendarEventsStatus(
                message: CalendarEventsCopy.refreshOffline,
                tone: .warning
            )
        case .sourceUnavailable, .failed:
            CalendarEventsStatus(
                message: CalendarEventsCopy.refreshFailed,
                tone: .warning
            )
        case nil:
            CalendarEventsStatus(message: nil, tone: .info)
        }
    }

    /// Planner-owned initial-fetch failure copy for either Primary Source
    /// Calendar discovery or its aggregate Calendar Event request.
    private static func initialFailureStatus(
        _ failure: GoogleCalendarEventsFailure
    ) -> CalendarEventsStatus {
        switch failure {
        case .offline:
            CalendarEventsStatus(
                message: CalendarEventsCopy.offline,
                tone: .warning
            )
        case .sourceUnavailable, .failed:
            CalendarEventsStatus(
                message: CalendarEventsCopy.failed,
                tone: .error
            )
        }
    }

    private static func slabFailureStatus(
        _ failure: GoogleCalendarEventsFailure
    ) -> CalendarEventsStatus {
        switch failure {
        case .offline:
            CalendarEventsStatus(
                message: CalendarEventsCopy.offlinePartial,
                tone: .warning
            )
        case .sourceUnavailable, .failed:
            CalendarEventsStatus(
                message: CalendarEventsCopy.failedPartial,
                tone: .warning
            )
        }
    }

    // MARK: Freshness

    /// Records only successful request completion. Coverage older than
    /// the freshness horizon can no longer satisfy a future query, so it
    /// is discarded as newer successes arrive to keep this memory-only
    /// list bounded during long foreground sessions.
    private static func recordFreshness(
        _ state: inout State,
        for range: FetchRange,
        completedAt: Date
    ) {
        let cutoff = completedAt.addingTimeInterval(-cadenceIntervalSeconds)
        state.freshnessCoverage.removeAll { coverage in
            coverage.completedAt < cutoff
                || (range.start <= coverage.start
                    && range.end >= coverage.end
                    && completedAt >= coverage.completedAt)
        }
        state.freshnessCoverage.append(
            FreshnessCoverage(
                start: range.start,
                end: range.end,
                completedAt: completedAt
            )
        )
    }

    /// Whether recent successful requests jointly cover every instant in
    /// a bounded refresh range. Overlapping initial, slab, and refresh
    /// ranges can form the coverage together; any gap makes the range
    /// stale.
    private static func isFresh(
        _ coverage: [FreshnessCoverage],
        range: FetchRange,
        at now: Date
    ) -> Bool {
        let cutoff = now.addingTimeInterval(-cadenceIntervalSeconds)
        let eligible = coverage
            .filter {
                $0.completedAt >= cutoff
                    && $0.completedAt <= now
                    && $0.end > range.start
                    && $0.start < range.end
            }
            .sorted {
                if $0.start != $1.start {
                    return $0.start < $1.start
                }
                return $0.end > $1.end
            }

        var coveredThrough = range.start
        for entry in eligible {
            if entry.start > coveredThrough {
                return false
            }
            coveredThrough = max(coveredThrough, entry.end)
            if coveredThrough >= range.end {
                return true
            }
        }
        return false
    }

    // MARK: Range math

    /// Three clamped calendar months around the latest visible Date
    /// Cells, clipped to the complete Week Rows of the Extended Calendar
    /// Range.
    private static func selectionReplacementRange(
        visible: FetchRange,
        environment: CalendarEnvironment
    ) -> FetchRange? {
        let calendar = environment.calendar
        guard
            let bufferedStart = addMonthsClamped(
                -3,
                to: visible.start,
                environment: environment
            ),
            let bufferedLastDay = addMonthsClamped(
                3,
                to: visible.end,
                environment: environment
            ),
            let bufferedEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: bufferedLastDay
            ),
            let extended = extendedCalendarRange(environment: environment)
        else {
            return nil
        }

        let start = max(
            calendar.startOfDay(for: bufferedStart),
            extended.start
        )
        let end = min(
            calendar.startOfDay(for: bufferedEnd),
            extended.end
        )
        return start < end ? FetchRange(start: start, end: end) : nil
    }

    /// The half-open complete Week Rows from the week containing ten
    /// years before Today through the week containing ten years after
    /// Today.
    private static func extendedCalendarRange(
        environment: CalendarEnvironment
    ) -> FetchRange? {
        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        guard
            let firstDate = addYearsClamped(
                -10,
                to: today,
                environment: environment
            ),
            let finalDate = addYearsClamped(
                10,
                to: today,
                environment: environment
            ),
            let end = calendar.date(
                byAdding: .day,
                value: 7,
                to: startOfMondayWeek(
                    containing: finalDate,
                    environment: environment
                )
            )
        else {
            return nil
        }
        return FetchRange(
            start: startOfMondayWeek(
                containing: firstDate,
                environment: environment
            ),
            end: end
        )
    }

    /// The visible dates plus one month on each side, clipped to the
    /// Fetched Window. Both foreground and browsing refresh decisions use
    /// this one calculation so freshness can never authorize a different
    /// range from the request it suppresses or starts.
    private static func boundedRefreshRange(
        window: FetchRange,
        visible: FetchRange,
        environment: CalendarEnvironment
    ) -> FetchRange? {
        guard
            let bufferedStart = addMonthsClamped(
                -1,
                to: visible.start,
                environment: environment
            ),
            let bufferedEnd = addMonthsClamped(
                1,
                to: visible.end,
                environment: environment
            )
        else {
            return nil
        }

        let start = max(bufferedStart, window.start)
        let end = min(bufferedEnd, window.end)
        return start < end ? FetchRange(start: start, end: end) : nil
    }

    private static func startOfMondayWeek(
        containing date: Date,
        environment: CalendarEnvironment
    ) -> Date {
        let calendar = environment.calendar
        let localDate = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: localDate)
        let daysSinceMonday = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: localDate
        )!
    }

    private static func addMonthsClamped(
        _ amount: Int,
        to date: Date,
        environment: CalendarEnvironment
    ) -> Date? {
        addClamped(.month, amount: amount, to: date, environment: environment)
    }

    private static func addYearsClamped(
        _ amount: Int,
        to date: Date,
        environment: CalendarEnvironment
    ) -> Date? {
        addClamped(.year, amount: amount, to: date, environment: environment)
    }

    /// Adds calendar months or years the way a person flips pages: the
    /// same day-of-month in the target month, clamped to its last day
    /// when the target month is shorter, in the environment's calendar
    /// and time zone.
    private static func addClamped(
        _ component: Calendar.Component,
        amount: Int,
        to date: Date,
        environment: CalendarEnvironment
    ) -> Date? {
        let calendar = environment.calendar
        let source = calendar.dateComponents(
            [.era, .year, .month, .day],
            from: date
        )
        guard let year = source.year, let month = source.month,
              let day = source.day
        else {
            return nil
        }

        var firstOfTargetMonth = DateComponents()
        firstOfTargetMonth.calendar = calendar
        firstOfTargetMonth.timeZone = calendar.timeZone
        firstOfTargetMonth.era = source.era
        switch component {
        case .month:
            firstOfTargetMonth.year = year
            firstOfTargetMonth.month = month + amount
        case .year:
            firstOfTargetMonth.year = year + amount
            firstOfTargetMonth.month = month
        default:
            return nil
        }
        firstOfTargetMonth.day = 1

        guard
            let targetMonth = calendar.date(from: firstOfTargetMonth),
            let validDays = calendar.range(
                of: .day,
                in: .month,
                for: targetMonth
            )
        else {
            return nil
        }

        var target = firstOfTargetMonth
        target.day = min(day, validDays.count)
        return calendar.date(from: target)
    }
}
