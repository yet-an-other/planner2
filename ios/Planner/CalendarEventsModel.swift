import Foundation
import Observation

/// The Source Calendar presentation attributes Planner presents.
struct GoogleSourceCalendar: Equatable, Sendable {
    /// The calendar's Google background color as a `#RRGGBB` hex string.
    let backgroundColorHex: String
}

/// A decoded start or end of a Google Calendar event in Google-shaped form:
/// either a civil all-day date or an absolute timed instant. All-day ends
/// stay exclusive here, exactly as Google delivers them; product rules about
/// inclusive last days live in the model.
enum GoogleCalendarEventTime: Equatable, Sendable {
    case allDay(year: Int, month: Int, day: Int)
    case timed(Date)
}

/// One decoded Google Calendar event crossing the adapter seam. The shape is
/// Google's; classification, filtering, and presentation rules belong to the
/// model, and raw Google errors never cross this boundary.
struct GoogleCalendarEvent: Equatable, Sendable {
    let id: String
    let summary: String?
    /// Google's explicit event color id, when the event carries one.
    let colorId: String?
    let start: GoogleCalendarEventTime
    let end: GoogleCalendarEventTime
    let isCancelled: Bool
    let isDeclinedByViewer: Bool

    init(
        id: String,
        summary: String?,
        colorId: String? = nil,
        start: GoogleCalendarEventTime,
        end: GoogleCalendarEventTime,
        isCancelled: Bool,
        isDeclinedByViewer: Bool
    ) {
        self.id = id
        self.summary = summary
        self.colorId = colorId
        self.start = start
        self.end = end
        self.isCancelled = isCancelled
        self.isDeclinedByViewer = isDeclinedByViewer
    }
}

/// Planner-relevant event-fetch failure kinds.
enum GoogleCalendarEventsFailure: Equatable, Sendable {
    /// A transient connectivity failure.
    case offline

    /// Any other failure.
    case failed
}

/// The product-oriented outcome of one Google Calendar events fetch.
enum GoogleCalendarEventsOutcome: Equatable, Sendable {
    /// The primary Source Calendar's attributes, its decoded events for
    /// the requested range, and Google's event color metadata — the
    /// explicit-event-color backgrounds keyed by color id, possibly empty
    /// when their cosmetic fetch failed.
    case success(
        calendar: GoogleSourceCalendar,
        events: [GoogleCalendarEvent],
        eventColorBackgrounds: [String: String]
    )

    /// The fetch could not complete.
    case unavailable(GoogleCalendarEventsFailure)
}

/// The Google Calendar seam: one product-oriented interface satisfied by the
/// live Google Calendar API adapter in production and by a fake adapter in
/// deterministic tests. Fetches cover the primary Source Calendar only.
@MainActor
protocol GoogleCalendarEventsAdapting {
    /// Fetches the primary Source Calendar's events with local start dates
    /// in `[start, end)`, expanding recurring events into instances.
    func fetchEvents(
        from start: Date,
        to end: Date
    ) async -> GoogleCalendarEventsOutcome
}

/// The iOS Header Status content published by the Calendar Events model:
/// fetch progress, fetch failures, and offline conditions in Planner-owned
/// copy. A `nil` message leaves the row to the connection's own status.
struct CalendarEventsStatus: Equatable, Sendable {
    let message: String?
    let tone: Tone

    /// Severity mapped to palette tones by the view layer.
    enum Tone: Equatable, Sendable {
        case info
        case warning
        case error
    }
}

/// The Planner-owned iOS Header Status copy for Calendar Events,
/// English-only like the connection copy; raw Google errors never surface.
enum CalendarEventsCopy {}

extension CalendarEventsCopy {
    /// Shown while the initial window or a slab fetch is in flight.
    static let loading = "Loading events…"

    /// Shown when the initial fetch cannot complete offline; the Calendar
    /// Grid stays usable and the fetch retries when connectivity returns.
    static let offline =
        "You\u{2019}re offline. Events will load when online"

    /// Shown when a slab fetch cannot complete offline; already-fetched
    /// events stay visible and the slab retries when connectivity returns.
    static let offlinePartial =
        "You\u{2019}re offline. More events will load when online"

    /// Shown when the initial fetch fails for any other reason.
    static let failed = "Couldn\u{2019}t load events"

    /// Shown when a slab fetch fails for any other reason; the range
    /// retries on the next edge approach.
    static let failedPartial = "Couldn\u{2019}t load more events. Will retry"
}

/// The readable text tone on top of an Event Color.
enum CalendarEventTextTone: Equatable, Sendable {
    case dark
    case light
}

/// An Event Color decomposed from its `#RRGGBB` hex form. A component
/// that fails to parse reads as zero.
struct EventColorRGB: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    /// Decomposes a `#RRGGBB` hex string, returning `nil` when it is not
    /// exactly six pairs after one optional leading `#`.
    init?(hex: String) {
        var hex = hex
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 else {
            return nil
        }
        red = Int(hex.prefix(2), radix: 16) ?? 0
        green = Int(hex.dropFirst(2).prefix(2), radix: 16) ?? 0
        blue = Int(hex.dropFirst(4).prefix(2), radix: 16) ?? 0
    }

    /// The WCAG 2.x relative luminance of the color.
    var relativeLuminance: Double {
        Self.relativeLuminance(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }

    /// The WCAG 2.x relative luminance of sRGB channels in 0...1.
    static func relativeLuminance(
        red: Double,
        green: Double,
        blue: Double
    ) -> Double {
        0.2126 * linearized(red) + 0.7152 * linearized(green)
            + 0.0722 * linearized(blue)
    }

    /// One sRGB channel's linear form per the WCAG threshold.
    private static func linearized(_ channel: Double) -> Double {
        channel <= 0.04045
            ? channel / 12.92
            : pow((channel + 0.055) / 1.055, 2.4)
    }
}

/// One week's segment of a Calendar Event Bar: a multiday or all-day event
/// clipped to the Week Row it crosses, in its assigned lane.
struct CalendarEventBarSegment: Equatable, Sendable, Identifiable {
    /// Unique within the Week Row: the event's id (one segment per event per
    /// week).
    let id: String
    let title: String
    let colorHex: String
    let textTone: CalendarEventTextTone
    /// The vertical lane, zero-based from the top of the events area.
    let lane: Int
    /// Monday-first columns the segment covers, 0...6.
    let startColumn: Int
    let endColumn: Int
    /// The event continues into the previous Week Row.
    let isStartTruncated: Bool
    /// The event continues into the next Week Row.
    let isEndTruncated: Bool
}

/// A Calendar Event Row: an intraday event presented in its Date Cell with a
/// dot, a localized start time, and a title.
struct CalendarEventRowItem: Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let startTimeText: String
    let colorHex: String
}

/// One Date Cell's event content: the deepest visible bar lane crossing
/// the cell, the cell's visible intraday rows in start-time order, and the
/// inert Events Overflow count when the visible cap hides items.
struct CalendarEventCellLayout: Equatable, Sendable {
    /// The highest visible lane index crossing this cell, or -1 when no
    /// visible bar does; rows and the overflow marker render below it.
    let maxBarLane: Int
    let rows: [CalendarEventRowItem]
    /// The hidden item count for the "+N more" marker, or `nil` when every
    /// item fits. The marker is inert: it summons nothing.
    let overflowCount: Int?
}

/// One Week Row's laid-out Calendar Events: bar segments in an overlay and
/// per-cell content, ready for presentation.
struct CalendarEventWeekLayout: Equatable, Sendable {
    let bars: [CalendarEventBarSegment]
    /// Exactly seven cells, Monday-first.
    let cells: [CalendarEventCellLayout]
}

/// The deep native module behind Calendar Events on the iOS Calendar
/// Surface: it owns the Fetched Window, normalizes Google-shaped events
/// into Planner's classification, and publishes per-Week-Row layouts. All
/// events are memory-only: they arrive while the Google Account Connection
/// is connected, vanish when it disconnects, and are never persisted
/// (iOS ADR 0003).
@MainActor
@Observable
final class CalendarEventsModel {
    /// The laid-out Week Rows keyed by their Monday-first local start dates.
    private(set) var weekLayouts: [Date: CalendarEventWeekLayout] = [:]

    /// The iOS Header Status content: the latest events message and its
    /// tone, or a `nil` message while nothing needs saying.
    private(set) var status = CalendarEventsStatus(message: nil, tone: .info)

    @ObservationIgnored
    private let adapter: (any GoogleCalendarEventsAdapting)?

    /// The connectivity observer behind offline recovery, when configured;
    /// the same seam the connection module uses.
    @ObservationIgnored
    private let connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)?

    @ObservationIgnored
    private var environment: CalendarEnvironment

    /// The last visible range reported by the Calendar Screen, re-checked
    /// when connectivity returns so owed slabs retry.
    @ObservationIgnored
    private var lastVisibleRange: (start: Date, end: Date)?

    /// Whether the initial Fetched Window fetch is in flight.
    @ObservationIgnored
    private var isFetchingInitialWindow = false

    /// The local-date bounds of the Fetched Window, when it has been
    /// fetched: `[windowStart, windowEnd)` as start-of-day instants.
    @ObservationIgnored
    private var fetchedWindow: (start: Date, end: Date)?

    /// Every fetched event in normalized form, retained so a slab can
    /// recompute its boundary Week Row from old and new events together.
    /// At most one entry per event id: slabs redeliver events spanning a
    /// fetched range's boundary, and the fresh copy replaces the retained
    /// one. Memory-only: cleared on Disconnect on This Device (ADR 0003).
    @ObservationIgnored
    private var normalizedEvents: [NormalizedEvent] = []

    /// In-flight slab directions, so repeated edge approaches can never
    /// duplicate a fetch.
    @ObservationIgnored
    private var isExtendingForward = false

    @ObservationIgnored
    private var isExtendingBackward = false

    /// Whether the module currently treats the Google Account Connection
    /// as connected; repeated reports of the same state are no-ops, so a
    /// republished connection can never wedge or duplicate a fetch.
    @ObservationIgnored
    private var isConnected = false

    /// Monotonic marker of the latest connection decision, so a stale
    /// asynchronous fetch completion can never overwrite newer user intent
    /// — the same discipline the connection module keeps.
    @ObservationIgnored
    private var connectionGeneration = 0

    /// Builds the module. A `nil` adapter leaves the module permanently
    /// inert: nothing fetches and nothing renders. The connectivity
    /// monitor, when provided, drives offline recovery event-driven.
    init(
        environment: CalendarEnvironment,
        adapter: (any GoogleCalendarEventsAdapting)?,
        connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)? = nil
    ) {
        self.environment = environment
        self.adapter = adapter
        self.connectivityMonitor = connectivityMonitor
        connectivityMonitor?.start { [weak self] in
            self?.handleConnectivityReturn()
        }
    }

    /// The module's lifetime end stops connectivity observation; in-flight
    /// asynchronous work captures the module weakly and is ignored once the
    /// module is gone.
    isolated deinit {
        connectivityMonitor?.stop()
    }

    /// The laid-out events for the Week Row starting on the given local
    /// date, or `nil` when the week holds no fetched events.
    func layout(forWeekStarting weekStart: Date) -> CalendarEventWeekLayout? {
        weekLayouts[weekStart]
    }

    /// Publishes the Google Account Connection state. Becoming connected
    /// fetches the initial Fetched Window — three months before Today
    /// through three months after — once; becoming disconnected clears
    /// every event and forgets the window, so a later connection fetches
    /// fresh data.
    func setConnected(_ connected: Bool) {
        guard let adapter, connected != isConnected else {
            return
        }

        isConnected = connected
        connectionGeneration += 1

        guard connected else {
            fetchedWindow = nil
            normalizedEvents = []
            isFetchingInitialWindow = false
            isExtendingForward = false
            isExtendingBackward = false
            lastVisibleRange = nil
            weekLayouts = [:]
            status = CalendarEventsStatus(message: nil, tone: .info)
            return
        }

        beginInitialFetch(adapter: adapter)
    }

    /// Fetches the initial Fetched Window — three months before Today
    /// through three months after — announcing progress in the iOS Header
    /// Status. A failure reports Planner-owned copy and leaves the window
    /// unfetched: an offline failure retries when connectivity returns.
    private func beginInitialFetch(
        adapter: any GoogleCalendarEventsAdapting
    ) {
        guard fetchedWindow == nil, !isFetchingInitialWindow else {
            return
        }

        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        guard
            let windowStart = addMonthsClamped(-3, to: today),
            let lastDay = addMonthsClamped(3, to: today),
            let windowEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: lastDay
            )
        else {
            return
        }

        isFetchingInitialWindow = true
        status = CalendarEventsStatus(
            message: CalendarEventsCopy.loading,
            tone: .info
        )

        let attempt = connectionGeneration
        Task { [weak self] in
            let outcome = await adapter.fetchEvents(
                from: windowStart,
                to: windowEnd
            )

            // A stale completion must not overwrite a newer decision: after
            // Disconnect on This Device or a newer connection, its events
            // are discarded.
            guard let self, attempt == self.connectionGeneration else {
                return
            }

            isFetchingInitialWindow = false

            switch outcome {
            case .success(
                let sourceCalendar,
                let events,
                let eventColorBackgrounds
            ):
                fetchedWindow = (windowStart, windowEnd)
                normalizedEvents = normalize(
                    events,
                    calendar: sourceCalendar,
                    eventColorBackgrounds: eventColorBackgrounds
                )
                weekLayouts = [:]
                publishWeeks(covering: (start: windowStart, end: windowEnd))
                clearStatusIfIdle()
            case .unavailable(let failure):
                status = switch failure {
                case .offline:
                    CalendarEventsStatus(
                        message: CalendarEventsCopy.offline,
                        tone: .warning
                    )
                case .failed:
                    CalendarEventsStatus(
                        message: CalendarEventsCopy.failed,
                        tone: .error
                    )
                }
            }
        }
    }

    /// Handles connectivity returning after an offline period, event-driven
    /// with no polling: an unfetched initial window retries, and otherwise
    /// the last reported visible range is re-checked so failed slabs retry.
    private func handleConnectivityReturn() {
        guard isConnected, let adapter else {
            return
        }

        if fetchedWindow == nil {
            beginInitialFetch(adapter: adapter)
        } else if let lastVisibleRange {
            showVisibleRange(
                from: lastVisibleRange.start,
                through: lastVisibleRange.end
            )
        }
    }

    /// Clears the status once no fetch work remains in flight; failure
    /// copy stays until fresh progress or a success supersedes it.
    private func clearStatusIfIdle() {
        guard !isFetchingInitialWindow,
              !isExtendingForward,
              !isExtendingBackward
        else {
            return
        }
        status = CalendarEventsStatus(message: nil, tone: .info)
    }

    /// Reports the currently visible local-date range (as Week Row start
    /// instants) and grows the Fetched Window when either edge comes within
    /// one month of it: a two-month slab fetch in that direction, once per
    /// range per process run. A failed slab leaves the window unchanged, so
    /// the next approach retries it. Approaches before the initial window
    /// lands do nothing — the initial fetch owns that range.
    func showVisibleRange(from visibleStart: Date, through visibleEnd: Date) {
        guard let adapter, let window = fetchedWindow else {
            return
        }

        lastVisibleRange = (visibleStart, visibleEnd)

        let calendar = environment.calendar

        if !isExtendingForward,
           let lastFetchedDay = calendar.date(
               byAdding: .day,
               value: -1,
               to: window.end
           ),
           let forwardTrigger = addMonthsClamped(-1, to: lastFetchedDay),
           visibleEnd >= forwardTrigger,
           let newLastDay = addMonthsClamped(2, to: lastFetchedDay),
           let newEnd = calendar.date(
               byAdding: .day,
               value: 1,
               to: newLastDay
           )
        {
            isExtendingForward = true
            extend(
                adapter: adapter,
                from: window.end,
                to: newEnd,
                direction: .forward
            )
        }

        if !isExtendingBackward,
           let backwardTrigger = addMonthsClamped(1, to: window.start),
           visibleStart <= backwardTrigger,
           let newStart = addMonthsClamped(-2, to: window.start)
        {
            isExtendingBackward = true
            extend(
                adapter: adapter,
                from: newStart,
                to: window.start,
                direction: .backward
            )
        }
    }

    /// One slab direction of the Fetched Window.
    private enum ExtensionDirection {
        case forward
        case backward
    }

    /// Fetches one slab and, on success, grows the window over it and
    /// republishes the affected Week Rows — including the boundary row,
    /// which is recomputed from every fetched event so old and new events
    /// merge. Failures leave the window unchanged for the next approach to
    /// retry; stale completions (a newer connection decision) discard.
    private func extend(
        adapter: any GoogleCalendarEventsAdapting,
        from fetchStart: Date,
        to fetchEnd: Date,
        direction: ExtensionDirection
    ) {
        let attempt = connectionGeneration
        status = CalendarEventsStatus(
            message: CalendarEventsCopy.loading,
            tone: .info
        )
        Task { [weak self] in
            let outcome = await adapter.fetchEvents(
                from: fetchStart,
                to: fetchEnd
            )

            switch direction {
            case .forward:
                self?.isExtendingForward = false
            case .backward:
                self?.isExtendingBackward = false
            }

            guard let self, attempt == self.connectionGeneration else {
                return
            }

            switch outcome {
            case .success(
                let sourceCalendar,
                let events,
                let eventColorBackgrounds
            ):
                // Google delivers every event overlapping the requested
                // range, so an event spanning a previously fetched range's
                // boundary arrives again here. The fresh copy replaces the
                // retained one: one entry per event id keeps every Week
                // Row to one segment per event.
                let slabEvents = normalize(
                    events,
                    calendar: sourceCalendar,
                    eventColorBackgrounds: eventColorBackgrounds
                )
                let redeliveredIds = Set(slabEvents.map(\.id))
                normalizedEvents.removeAll { redeliveredIds.contains($0.id) }
                normalizedEvents.append(contentsOf: slabEvents)
                switch direction {
                case .forward:
                    fetchedWindow?.end = fetchEnd
                case .backward:
                    fetchedWindow?.start = fetchStart
                }
                publishWeeks(covering: (start: fetchStart, end: fetchEnd))
                clearStatusIfIdle()
            case .unavailable(let failure):
                status = switch failure {
                case .offline:
                    CalendarEventsStatus(
                        message: CalendarEventsCopy.offlinePartial,
                        tone: .warning
                    )
                case .failed:
                    CalendarEventsStatus(
                        message: CalendarEventsCopy.failedPartial,
                        tone: .warning
                    )
                }
            }
        }
    }

    // MARK: Normalization

    /// One event in Planner's classified, local-date form.
    private struct NormalizedEvent {
        enum Kind: Equatable {
            /// An all-day or multiday bar over inclusive local dates, with
            /// the event's start instant for ordering.
            case bar(startDate: Date, endDate: Date, startsAt: Date)

            /// An intraday row on one local date.
            case row(date: Date, startsAt: Date, startTimeText: String)
        }

        let id: String
        let title: String
        let colorHex: String
        let textTone: CalendarEventTextTone
        let kind: Kind
    }

    /// Applies Planner's product rules: cancelled and declined events drop
    /// out, blank titles become "Busy", all-day ends turn inclusive, and
    /// every event classifies as a bar or a row in the environment's local
    /// dates.
    private func normalize(
        _ events: [GoogleCalendarEvent],
        calendar sourceCalendar: GoogleSourceCalendar,
        eventColorBackgrounds: [String: String]
    ) -> [NormalizedEvent] {
        let calendar = environment.calendar
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = environment.locale
        timeFormatter.timeZone = environment.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")

        return events.compactMap { event in
            guard !event.isCancelled, !event.isDeclinedByViewer else {
                return nil
            }

            let trimmed = event.summary?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let title = trimmed.isEmpty ? "Busy" : trimmed
            // The Event Color (Planning glossary): the explicit Google
            // event color when one is set and known, otherwise the Source
            // Calendar's background color.
            let colorHex = event.colorId
                .flatMap { eventColorBackgrounds[$0] }
                ?? sourceCalendar.backgroundColorHex
            let textTone = CalendarEventsModel.textTone(forHexColor: colorHex)

            switch (event.start, event.end) {
            case (
                .allDay(let startYear, let startMonth, let startDay),
                .allDay(let endYear, let endMonth, let endDay)
            ):
                guard
                    let startDate = civilDate(
                        year: startYear,
                        month: startMonth,
                        day: startDay
                    ),
                    let exclusiveEnd = civilDate(
                        year: endYear,
                        month: endMonth,
                        day: endDay
                    ),
                    let endDate = calendar.date(
                        byAdding: .day,
                        value: -1,
                        to: exclusiveEnd
                    ),
                    endDate >= startDate
                else {
                    return nil
                }
                return NormalizedEvent(
                    id: event.id,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .bar(
                        startDate: startDate,
                        endDate: endDate,
                        startsAt: startDate
                    )
                )
            case (.timed(let startsAt), .timed(let endsAt)):
                let startDate = calendar.startOfDay(for: startsAt)
                let endDate = calendar.startOfDay(for: endsAt)
                if endDate > startDate {
                    return NormalizedEvent(
                        id: event.id,
                        title: title,
                        colorHex: colorHex,
                        textTone: textTone,
                        kind: .bar(
                            startDate: startDate,
                            endDate: endDate,
                            startsAt: startsAt
                        )
                    )
                }
                return NormalizedEvent(
                    id: event.id,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .row(
                        date: startDate,
                        startsAt: startsAt,
                        startTimeText: timeFormatter.string(from: startsAt)
                    )
                )
            default:
                // A mixed or missing start/end pair is not presentable.
                return nil
            }
        }
    }

    // MARK: Layout

    /// Computes and publishes the layout of every non-empty Week Row
    /// intersecting the given local-date range, recomputed from every
    /// fetched event so slabs merge into already-published boundary rows.
    private func publishWeeks(covering range: (start: Date, end: Date)) {
        let calendar = environment.calendar

        var weekStart = startOfMondayWeek(containing: range.start)
        while weekStart < range.end {
            let layout = layoutWeek(normalizedEvents, weekStart: weekStart)
            // Weeks without events publish no layout at all, so the view
            // renders them exactly as an event-free surface.
            if !layout.bars.isEmpty
                || layout.cells.contains(where: { !$0.rows.isEmpty })
            {
                weekLayouts[weekStart] = layout
            }
            guard
                let next = calendar.date(byAdding: .day, value: 7, to: weekStart)
            else {
                break
            }
            weekStart = next
        }
    }

    /// Lays out one Week Row: bars clipped to the row in globally ordered
    /// lanes, then each Date Cell's rows in start-time order.
    private func layoutWeek(
        _ events: [NormalizedEvent],
        weekStart: Date
    ) -> CalendarEventWeekLayout {
        let calendar = environment.calendar
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        struct PlacedBar {
            let event: NormalizedEvent
            let startDate: Date
            let endDate: Date
            let startsAt: Date
            let startColumn: Int
            let endColumn: Int
        }

        let bars = events.compactMap { event -> PlacedBar? in
            guard
                case .bar(let startDate, let endDate, let startsAt) = event.kind,
                startDate <= weekEnd,
                endDate >= weekStart
            else {
                return nil
            }

            let clippedStart = max(startDate, weekStart)
            let clippedEnd = min(endDate, weekEnd)
            return PlacedBar(
                event: event,
                startDate: startDate,
                endDate: endDate,
                startsAt: startsAt,
                startColumn: calendar.dateComponents(
                    [.day],
                    from: weekStart,
                    to: clippedStart
                ).day!,
                endColumn: calendar.dateComponents(
                    [.day],
                    from: weekStart,
                    to: clippedEnd
                ).day!
            )
        }
        .sorted { left, right in
            if left.startDate != right.startDate {
                return left.startDate < right.startDate
            }
            if left.startsAt != right.startsAt {
                return left.startsAt < right.startsAt
            }
            return left.endDate > right.endDate
        }

        var laneEnds: [Int: Int] = [:]
        var segments: [CalendarEventBarSegment] = []
        for bar in bars {
            var lane = 0
            while let occupiedThrough = laneEnds[lane],
                  occupiedThrough >= bar.startColumn
            {
                lane += 1
            }
            laneEnds[lane] = bar.endColumn

            segments.append(
                CalendarEventBarSegment(
                    id: bar.event.id,
                    title: bar.event.title,
                    colorHex: bar.event.colorHex,
                    textTone: bar.event.textTone,
                    lane: lane,
                    startColumn: bar.startColumn,
                    endColumn: bar.endColumn,
                    isStartTruncated: bar.startDate < weekStart,
                    isEndTruncated: bar.endDate > weekEnd
                )
            )
        }

        var rowsByColumn: [[(startsAt: Date, item: CalendarEventRowItem)]] =
            (0..<7).map { _ in [] }
        for event in events {
            guard case .row(let date, let startsAt, let startTimeText) =
                event.kind
            else {
                continue
            }
            let column = calendar.dateComponents(
                [.day],
                from: weekStart,
                to: date
            ).day!
            guard (0..<7).contains(column) else {
                continue
            }
            rowsByColumn[column].append(
                (
                    startsAt,
                    CalendarEventRowItem(
                        id: event.id,
                        title: event.title,
                        startTimeText: startTimeText,
                        colorHex: event.colorHex
                    )
                )
            )
        }

        var maxCrossingLaneByColumn = [Int](repeating: -1, count: 7)
        var crossingLaneCountByColumn = [Int](repeating: 0, count: 7)
        for segment in segments {
            for column in segment.startColumn...segment.endColumn {
                crossingLaneCountByColumn[column] += 1
                maxCrossingLaneByColumn[column] = max(
                    maxCrossingLaneByColumn[column],
                    segment.lane
                )
            }
        }

        let rowCountByColumn = rowsByColumn.map(\.count)

        // Lane visibility: the first three lanes always render. A deeper
        // segment renders only when every Date Cell it crosses still fits
        // the four 14-point slots at true lane positions — no rows below
        // the deepest lane and no overflow — so a strip never collides
        // with a row or the Events Overflow marker; otherwise the segment
        // counts into the overflow of every cell it crosses.
        let visibleSegments = segments.filter { segment in
            if segment.lane < Self.maxVisibleBarLanes {
                return true
            }
            return (segment.startColumn...segment.endColumn).allSatisfy {
                column in
                maxCrossingLaneByColumn[column] + rowCountByColumn[column] <= 3
                    && crossingLaneCountByColumn[column]
                        + rowCountByColumn[column] <= 4
            }
        }

        var maxBarLaneByColumn = [Int](repeating: -1, count: 7)
        var visibleLaneCountByColumn = [Int](repeating: 0, count: 7)
        for segment in visibleSegments {
            for column in segment.startColumn...segment.endColumn {
                visibleLaneCountByColumn[column] += 1
                maxBarLaneByColumn[column] = max(
                    maxBarLaneByColumn[column],
                    segment.lane
                )
            }
        }

        let cells = (0..<7).map { column in
            let visibleLaneCount = visibleLaneCountByColumn[column]
            let hiddenBarCount =
                crossingLaneCountByColumn[column] - visibleLaneCount
            let orderedRows = rowsByColumn[column]
                .sorted { $0.startsAt < $1.startsAt }
                .map(\.item)

            // The visible cap: four slots per Date Cell — visible lanes,
            // then rows — beyond which the cell shows three items and the
            // inert Events Overflow marker counts the rest. Rows and the
            // marker only appear while they fit below the deepest visible
            // lane inside the fixed 96-point Week Row.
            let rowSlots = 4 - visibleLaneCount
            let rowsFit = maxBarLaneByColumn[column] + orderedRows.count <= 3
            if hiddenBarCount == 0 && orderedRows.count <= rowSlots && rowsFit {
                return CalendarEventCellLayout(
                    maxBarLane: maxBarLaneByColumn[column],
                    rows: orderedRows,
                    overflowCount: nil
                )
            }
            let visibleRowCount = max(
                0,
                min(
                    3 - visibleLaneCount,
                    2 - maxBarLaneByColumn[column]
                )
            )
            return CalendarEventCellLayout(
                maxBarLane: maxBarLaneByColumn[column],
                rows: Array(orderedRows.prefix(visibleRowCount)),
                overflowCount: hiddenBarCount
                    + (orderedRows.count - visibleRowCount)
            )
        }

        return CalendarEventWeekLayout(bars: visibleSegments, cells: cells)
    }

    // MARK: Local dates

    private func civilDate(year: Int, month: Int, day: Int) -> Date? {
        var components = DateComponents()
        components.calendar = environment.calendar
        components.timeZone = environment.timeZone
        components.year = year
        components.month = month
        components.day = day
        return components.date
    }

    private func startOfMondayWeek(containing date: Date) -> Date {
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

    private func addMonthsClamped(_ amount: Int, to date: Date) -> Date? {
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
        firstOfTargetMonth.year = year
        firstOfTargetMonth.month = month + amount
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

    /// A Week Row renders at most this many bar lanes at the fixed
    /// 96-point height; further lanes count into Events Overflow instead
    /// of rendering.
    private static let maxVisibleBarLanes = 3

    /// The readable text tone on an Event Color: whichever of Planner's
    /// ink or white yields the higher WCAG contrast ratio against it —
    /// the most readable pair the palette can offer, always above WCAG AA
    /// (4.5:1) for Google's fixed event and calendar palettes. This
    /// deliberately replaces the YIQ luminance rule the Web Experience
    /// still uses, which renders low-contrast white text on several
    /// Google palette colors.
    static func textTone(forHexColor hexColor: String) -> CalendarEventTextTone {
        guard let color = EventColorRGB(hex: hexColor) else {
            return .light
        }
        let luminance = color.relativeLuminance
        let darkContrast = (luminance + 0.05)
            / (Self.darkTextRelativeLuminance + 0.05)
        let lightContrast = (1.0 + 0.05) / (luminance + 0.05)
        return darkContrast >= lightContrast ? .dark : .light
    }

    /// The WCAG relative luminance of the dark text candidate, Planner's
    /// ink (PlannerPalette.ink: sRGB 0.114, 0.129, 0.071).
    private static let darkTextRelativeLuminance =
        EventColorRGB.relativeLuminance(
            red: 0.114,
            green: 0.129,
            blue: 0.071
        )
}
