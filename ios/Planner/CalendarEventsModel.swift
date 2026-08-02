import Foundation
import Observation

/// One Source Calendar crossing the Google adapter seam. Its stable Google
/// identity and presentation attributes travel with Calendar Events —
/// including into Stored Calendar Events when a store is wired (iOS ADR
/// 0007).
struct GoogleSourceCalendar: Equatable, Sendable, Codable {
    /// Google's stable opaque calendar identifier.
    let id: String
    /// Google's display summary. Presentation fallback for a blank summary
    /// belongs to the Source Calendars module introduced by a later slice.
    let summary: String
    /// The calendar's Google background color as a `#RRGGBB` hex string.
    let backgroundColorHex: String
    /// Whether Google marks this as the Primary Source Calendar.
    let isPrimary: Bool

}

/// A decoded start or end of a Google Calendar event in Google-shaped form:
/// either a civil all-day date or an absolute timed instant. All-day ends
/// stay exclusive here, exactly as Google delivers them; product rules about
/// inclusive last days live in the model.
enum GoogleCalendarEventTime: Equatable, Sendable {
    case allDay(year: Int, month: Int, day: Int)
    case timed(Date)
}

/// One decoded Google Calendar event attendee in Google-shaped form:
/// raw display name, email, and response status strings exactly as
/// Google delivers them; the display-name-primary label and the
/// closed-union status live in the model's normalization.
struct GoogleCalendarEventAttendee: Equatable, Sendable {
    let displayName: String?
    let email: String?
    let responseStatus: String?
}

/// One decoded Google Calendar event crossing the adapter seam. The shape is
/// Google's; classification, filtering, and presentation rules belong to the
/// model, and raw Google errors never cross this boundary.
struct GoogleCalendarEvent: Equatable, Sendable {
    let id: String
    /// Google's `iCalUID`, when supplied: the stable half of canonical
    /// cross-calendar occurrence identity.
    let iCalUID: String?
    /// Google's `originalStartTime`, when supplied: a moved recurring
    /// instance's original slot, the occurrence half of canonical identity.
    let originalStartTime: GoogleCalendarEventTime?
    let summary: String?
    /// Google's explicit event color id, when the event carries one.
    let colorId: String?
    let start: GoogleCalendarEventTime
    let end: GoogleCalendarEventTime
    let isCancelled: Bool
    let isDeclinedByViewer: Bool
    /// Google's link to the event in Google Calendar, when provided.
    let googleLink: String?
    /// Google's free-form location string, when provided.
    let location: String?
    /// Google's HTML description, when provided; normalization renders
    /// it plain.
    let notes: String?
    /// Google's attendee list, possibly empty.
    let attendees: [GoogleCalendarEventAttendee]

    init(
        id: String,
        iCalUID: String? = nil,
        originalStartTime: GoogleCalendarEventTime? = nil,
        summary: String?,
        colorId: String? = nil,
        start: GoogleCalendarEventTime,
        end: GoogleCalendarEventTime,
        isCancelled: Bool,
        isDeclinedByViewer: Bool,
        googleLink: String? = nil,
        location: String? = nil,
        notes: String? = nil,
        attendees: [GoogleCalendarEventAttendee] = []
    ) {
        self.id = id
        self.iCalUID = iCalUID
        self.originalStartTime = originalStartTime
        self.summary = summary
        self.colorId = colorId
        self.start = start
        self.end = end
        self.isCancelled = isCancelled
        self.isDeclinedByViewer = isDeclinedByViewer
        self.googleLink = googleLink
        self.location = location
        self.notes = notes
        self.attendees = attendees
    }
}

/// Planner-relevant event-fetch failure kinds.
enum GoogleCalendarEventsFailure: Equatable, Sendable {
    /// A transient connectivity failure.
    case offline

    /// A selected Source Calendar returned forbidden or not-found, so it may
    /// no longer be available. One live Source Calendar reload,
    /// reconciliation, and one aggregate retry follow before this is
    /// reported as a fetch failure.
    case sourceUnavailable

    /// Any other failure.
    case failed
}

/// One Google-shaped Calendar Event tagged with the Source Calendar from
/// which it was fetched. Keeping the complete Source Calendar on the event
/// side of the seam preserves identity, summary, Primary marker, and color
/// without introducing another store.
struct GoogleSourceCalendarEvent: Equatable, Sendable {
    let sourceCalendar: GoogleSourceCalendar
    let event: GoogleCalendarEvent
}

/// The legacy product-oriented outcome of obtaining the current Primary
/// Source Calendar before the earlier Primary-only event path begins.
enum GoogleSourceCalendarOutcome: Equatable, Sendable {
    case success(GoogleSourceCalendar)
    case unavailable(GoogleCalendarEventsFailure)
}

/// The product-oriented outcome of one aggregate Google Calendar events
/// fetch.
enum GoogleCalendarEventsOutcome: Equatable, Sendable {
    /// Complete source-tagged events for the requested Source Calendars and
    /// Google's account-wide event color metadata. The metadata may be empty
    /// when its cosmetic fetch failed.
    case success(
        events: [GoogleSourceCalendarEvent],
        eventColorBackgrounds: [String: String]
    )

    /// The aggregate fetch could not complete. No partial source result
    /// crosses this seam.
    case unavailable(GoogleCalendarEventsFailure)
}

/// The Google Calendar seam: one product-oriented interface satisfied by the
/// live Google Calendar API adapter in production and by fakes in tests and
/// previews. Calendar Event requests always name their Source Calendars
/// explicitly; production supplies the complete Selected Source Calendars.
@MainActor
protocol GoogleCalendarEventsAdapting {
    /// Obtains the Source Calendar Google currently designates as primary.
    func fetchPrimarySourceCalendar() async -> GoogleSourceCalendarOutcome

    /// Fetches one atomic aggregate for all supplied Source Calendars with
    /// local start dates in `[start, end)`, expanding recurring events into
    /// instances.
    func fetchEvents(
        from sourceCalendars: [GoogleSourceCalendar],
        start: Date,
        end: Date
    ) async -> GoogleCalendarEventsOutcome
}

/// One cancellable wait owned by the Calendar Events cadence.
@MainActor
protocol CalendarEventsCadenceSchedule: AnyObject {
    func cancel()
}

/// The deterministic scheduling and clock boundary for Calendar Event
/// Refresh. Production reads wall time and sleeps with a Task; tests control
/// both completion instants and scheduled actions directly.
@MainActor
protocol CalendarEventsCadenceScheduling: AnyObject {
    var now: Date { get }

    func schedule(
        after delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> any CalendarEventsCadenceSchedule
}

/// The live completion-relative cadence scheduler.
@MainActor
final class TaskCalendarEventsCadenceScheduler: CalendarEventsCadenceScheduling {
    var now: Date { .now }

    func schedule(
        after delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) -> any CalendarEventsCadenceSchedule {
        TaskCalendarEventsCadenceSchedule(delay: delay, action: action)
    }
}

/// A Task-backed wait whose cancellation never invokes its action.
@MainActor
private final class TaskCalendarEventsCadenceSchedule:
    CalendarEventsCadenceSchedule
{
    private var task: Task<Void, Never>?

    init(
        delay: Duration,
        action: @escaping @MainActor @Sendable () -> Void
    ) {
        task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
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

    /// Shown when Calendar Event Refresh cannot complete offline; existing
    /// events remain visible and connectivity return retries.
    static let refreshOffline =
        "You\u{2019}re offline. Events may be out of date"

    /// Shown when Calendar Event Refresh fails for any other reason; existing
    /// events remain visible until a later refresh succeeds.
    static let refreshFailed = "Couldn\u{2019}t refresh events. Will retry"

    /// Shown while an intentional Selected Source Calendars change replaces
    /// the prior atomic snapshot around the dates the user is viewing.
    static let updatingSelection = "Updating events…"
}

/// One week's segment of a Calendar Event Bar: a multiday or all-day event
/// clipped to the Week Row it crosses, in its assigned lane.
struct CalendarEventBarSegment: Equatable, Sendable, Identifiable {
    /// Unique within the Week Row: the event's canonical occurrence
    /// identity (one segment per event per week).
    let id: String
    /// The winning Source Calendar for this canonical occurrence,
    /// retained in memory for the Event Detail source row.
    let sourceCalendar: GoogleSourceCalendar
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
    /// The event's canonical occurrence identity.
    let id: String
    /// The winning Source Calendar for this canonical occurrence,
    /// retained in memory for the Event Detail source row.
    let sourceCalendar: GoogleSourceCalendar
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

/// The one Calendar Event currently presented in the Event Detail Popover.
/// Its canonical occurrence identity is the selection identity; the detail
/// is a projection of the model's canonical normalized event and is
/// reconciled whenever that collection changes.
struct CalendarEventDetailSelection: Equatable, Sendable, Identifiable {
    let id: String
    /// The winning Source Calendar's identity and presentation data,
    /// retained with the selected Calendar Event — and inside Stored
    /// Calendar Events — and presented as the Event Detail source row.
    let sourceCalendar: GoogleSourceCalendar
    let detail: CalendarEventDetail
}

/// One item in the Day Events Popover's complete ordered day list,
/// rendering with the Date Cell's own visual language: Calendar Event
/// Bars as colored bars, Calendar Event Rows with dot, start time, and
/// title.
enum CalendarEventDayItem: Equatable, Sendable, Identifiable {
    /// A Calendar Event Bar crossing the Date Cell, ordered by its lane
    /// in the cell's Week Row.
    case bar(Bar)

    /// A Calendar Event Row of the Date Cell, ordered by start time
    /// ascending.
    case row(Row)

    /// The bar presentation: color and title with contrast-safe text.
    struct Bar: Equatable, Sendable, Identifiable {
        /// The event's canonical occurrence identity.
        let id: String
        let title: String
        /// The Event Color as a `#RRGGBB` hex string.
        let colorHex: String
        let textTone: CalendarEventTextTone
    }

    /// The row presentation: color dot, localized start time, and title.
    struct Row: Equatable, Sendable, Identifiable {
        /// The event's canonical occurrence identity.
        let id: String
        let title: String
        let startTimeText: String
        /// The Event Color as a `#RRGGBB` hex string.
        let colorHex: String
    }

    var id: String {
        switch self {
        case .bar(let bar):
            bar.id
        case .row(let row):
            row.id
        }
    }

    /// The item's title, whichever shape it takes.
    var title: String {
        switch self {
        case .bar(let bar):
            bar.title
        case .row(let row):
            row.title
        }
    }
}

/// The Date Cell whose complete ordered day the open Day Events Popover
/// lists (Planning glossary). The selection projects from the model's
/// Calendar Events — including Stored Calendar Events presented at process
/// start — when the Events Overflow marker summons it,
/// opens with no network call, and reconciles with every successful
/// Calendar Event replacement — edits and moves update items in place,
/// deletions and declines remove them, and the popover dismisses itself
/// when the day's last Calendar Event disappears. Disconnect on This
/// Device clears it with the events themselves.
struct CalendarEventDaySelection: Equatable, Sendable, Identifiable {
    /// The Date Cell's local start-of-day, the selection identity.
    let date: Date
    var id: Date { date }
    /// The localized heading naming the Date Cell ("Monday, June 9").
    let heading: String
    /// The complete ordered day: Calendar Event Bars in lane order, then
    /// Calendar Event Rows by start time ascending — visible and hidden
    /// alike, including multiday and all-day bars crossing the day.
    let items: [CalendarEventDayItem]
}

/// The deep native module behind Calendar Events on the iOS Calendar
/// Surface: it owns the Fetched Window, normalizes Google-shaped events
/// into Planner's classification, and publishes per-Week-Row layouts. When
/// a store is wired, the Fetched Window's events persist as Stored
/// Calendar Events (iOS ADR 0007): the store is read at process start,
/// every successful response writes through, and Disconnect on This
/// Device wipes it. Without a store, events remain memory-only and clear
/// on Disconnect on This Device.
@MainActor
@Observable
final class CalendarEventsModel: SelectedSourceCalendarsConsuming,
    CalendarDataAccountConsuming
{
    /// The laid-out Week Rows keyed by their Monday-first local start dates.
    private(set) var weekLayouts: [Date: CalendarEventWeekLayout] = [:]

    /// The iOS Header Status content: the latest events message and its
    /// tone, or a `nil` message while nothing needs saying.
    private(set) var status = CalendarEventsStatus(message: nil, tone: .info)

    /// The selected canonical Calendar Event projected for the open Event
    /// Detail Popover. The selection remains present through edits and moves,
    /// updates after successful canonical replacement, and becomes `nil` when
    /// the selected event disappears or Calendar Events clear.
    private(set) var selectedEvent: CalendarEventDetailSelection?

    /// The Date Cell's day whose Day Events Popover the selected Calendar
    /// Event was drilled through from, while that selection stands. A
    /// cap-hidden drilled event has no visible Calendar Event Bar or Row,
    /// so this day's Events Overflow marker anchors its Event Detail
    /// Popover — the drilled-through cell summoned the list, so it stays
    /// on screen unlike any earlier attributed cell.
    private(set) var selectedEventDrilledFromDay: Date?

    /// The Date Cell whose complete ordered day the open Day Events Popover
    /// lists. The selection reconciles with every successful Calendar Event
    /// replacement like the Event Detail selection: edits and moves update
    /// items in place, deletions and declines remove them, and a failed
    /// refresh leaves the list unchanged. The popover dismisses itself when
    /// the day's last Calendar Event disappears, and Disconnect on This
    /// Device clears the selection with the events themselves.
    private(set) var selectedDayEvents: CalendarEventDaySelection?

    @ObservationIgnored
    private let adapter: (any GoogleCalendarEventsAdapting)?

    /// The disclosure-gated, reconciled Selected Source Calendars supplied
    /// to every Calendar Event request.
    @ObservationIgnored
    private var sourceCalendars: [GoogleSourceCalendar] = []

    /// The live Source Calendar reload behind forbidden/not-found recovery,
    /// wired when the Source Calendars module exists. Without it a
    /// `.sourceUnavailable` failure is reported like any other failure.
    @ObservationIgnored
    weak var sourceCalendarRecovery: (any SourceCalendarRecoveryHandling)?

    /// The connectivity observer behind offline recovery, when configured;
    /// the same seam the connection module uses.
    @ObservationIgnored
    private let connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)?

    /// The one scheduling boundary for completion-relative foreground
    /// cadence. It owns no model state and never persists freshness.
    @ObservationIgnored
    private let cadenceScheduler: any CalendarEventsCadenceScheduling

    /// The Stored Calendar Events boundary (iOS ADR 0007): read at
    /// process start, written through on every successful response, and
    /// wiped when the Calendar-data account clears. A `nil` store keeps
    /// Calendar Events memory-only.
    @ObservationIgnored
    private let eventStore: (any StoredCalendarEventsStoring)?

    /// The Google account whose Stored Calendar Events this process
    /// mirrors, published by the Calendar-data boundary only after the
    /// current disclosure is acknowledged. Writes happen only while an
    /// account is published, so an installation that acknowledged only an
    /// older disclosure never writes.
    @ObservationIgnored
    private var storedAccountID: String?

    /// Whether the presented events came from the store at process start
    /// and no successful response has replaced them yet. They stay on the
    /// surface while the first fetch runs — the grid never blanks behind
    /// an in-flight refresh.
    @ObservationIgnored
    private var isPresentingStoredEvents = false

    @ObservationIgnored
    private var environment: CalendarEnvironment

    /// Calendar Event Fetch Orchestration (Planning glossary): every
    /// fetch-work decision — the initial Fetched Window fetch, Fetched
    /// Window growth, bounded Calendar Event Refresh, selection
    /// replacement, browsing freshness, cadence, picker gating, and
    /// connectivity retry — lives behind this pure reducer. The model
    /// translates signals into events, executes the emitted fetch
    /// commands, and reports applied outcomes back.
    @ObservationIgnored
    private var orchestration = CalendarEventFetchOrchestration.State()

    /// The local-date bounds of the Fetched Window, when it has been
    /// fetched: `[windowStart, windowEnd)` as start-of-day instants. The
    /// model owns the window as effect-side truth; every change is
    /// reported to the orchestration.
    @ObservationIgnored
    private var fetchedWindow: CalendarEventFetchOrchestration.FetchRange?

    /// Every fetched event in normalized form, retained so a slab can
    /// recompute its boundary Week Row from old and new events together.
    /// At most one entry per event id: slabs redeliver events spanning a
    /// fetched range's boundary, and the fresh copy replaces the retained
    /// one. Persisted only through the Stored Calendar Events boundary
    /// (ADR 0007) and cleared on Disconnect on This Device.
    @ObservationIgnored
    private var normalizedEvents: [CalendarEvent] = []

    /// The single cancellable five-minute wait, reconciled against the
    /// orchestration's cadence decision after every event.
    @ObservationIgnored
    private var cadenceSchedule: (any CalendarEventsCadenceSchedule)?

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
        connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)? = nil,
        cadenceScheduler: any CalendarEventsCadenceScheduling =
            TaskCalendarEventsCadenceScheduler(),
        eventStore: (any StoredCalendarEventsStoring)? = nil
    ) {
        self.environment = environment
        self.adapter = adapter
        self.connectivityMonitor = connectivityMonitor
        self.cadenceScheduler = cadenceScheduler
        self.eventStore = eventStore
        connectivityMonitor?.start { [weak self] in
            self?.handleConnectivityReturn()
        }
    }

    /// The module's lifetime end cancels foreground cadence and stops
    /// connectivity observation. Scheduled actions and asynchronous fetches
    /// capture the module weakly, so neither can retain it.
    isolated deinit {
        cadenceSchedule?.cancel()
        connectivityMonitor?.stop()
    }

    /// The laid-out events for the Week Row starting on the given local
    /// date, or `nil` when the week holds no fetched events.
    func layout(forWeekStarting weekStart: Date) -> CalendarEventWeekLayout? {
        weekLayouts[weekStart]
    }

    /// Selects one canonical Calendar Event by its canonical occurrence
    /// identity. Layout items carry that identity, but the popover detail
    /// is resolved here so it never retains the tapped item's stale payload.
    /// The surface's overlays are mutually exclusive: summoning the Event
    /// Detail Popover closes any open Day Events Popover. `drilledFromDay`
    /// records the Date Cell's day whose Day Events Popover the event was
    /// drilled through from — an open day selection implies it — so that
    /// day's Events Overflow marker, the same anchor that presented the
    /// Day Events Popover, anchors the drilled event's detail.
    func selectEvent(withID id: String, drilledFromDay day: Date? = nil) {
        guard let selection = detailSelection(forEventID: id) else {
            return
        }
        let drilledFromDay = day ?? selectedDayEvents?.date
        selectedDayEvents = nil
        selectedEvent = selection
        selectedEventDrilledFromDay = drilledFromDay
    }

    /// Whether the selected Calendar Event is attributed to the given Date
    /// Cell's day. An event drilled from the Day Events Popover anchors its
    /// Event Detail Popover to that day's Events Overflow marker while it
    /// stays attributed — the same anchor that presented the Day Events
    /// Popover — so the surface needs attribution to keep the marker's
    /// presentation owned by a day the event still belongs to.
    func selectedEventIsAttributed(toDay date: Date) -> Bool {
        guard let selectedEvent else {
            return false
        }
        return dayEventsSelection(
            for: environment.calendar.startOfDay(for: date)
        ).items.contains { $0.id == selectedEvent.id }
    }

    /// Dismisses the Event Detail Popover without changing Calendar Events.
    func dismissEventDetail() {
        selectedEvent = nil
        selectedEventDrilledFromDay = nil
    }

    /// Summons the Day Events Popover for one Date Cell: the complete
    /// ordered day — Calendar Event Bars crossing the cell in lane order,
    /// then its Calendar Event Rows by start time ascending, visible and
    /// hidden alike — projected from the presented Calendar Events with no
    /// network call. The surface's overlays are mutually exclusive:
    /// summoning the Day Events Popover closes any open Event Detail
    /// Popover.
    func selectDayEvents(on date: Date) {
        selectedEvent = nil
        selectedEventDrilledFromDay = nil
        selectedDayEvents = dayEventsSelection(
            for: environment.calendar.startOfDay(for: date)
        )
    }

    /// Dismisses the Day Events Popover without changing Calendar Events.
    func dismissDayEvents() {
        selectedDayEvents = nil
    }

    /// Projects one Date Cell's complete ordered day from the canonical
    /// collection. Bars take their lanes from the cell's Week Row so the
    /// list mirrors the cell's own bars-then-rows ordering, including
    /// items the visible cap hides and multiday bars crossing the day.
    private func dayEventsSelection(for date: Date) -> CalendarEventDaySelection {
        let calendar = environment.calendar
        let weekStart = startOfMondayWeek(containing: date)
        let column = calendar.dateComponents(
            [.day],
            from: weekStart,
            to: date
        ).day ?? 0

        let bars = placedBarSegments(normalizedEvents, weekStart: weekStart)
            .filter { $0.startColumn <= column && column <= $0.endColumn }
            .sorted { $0.lane < $1.lane }
            .map {
                CalendarEventDayItem.bar(
                    CalendarEventDayItem.Bar(
                        id: $0.id,
                        title: $0.title,
                        colorHex: $0.colorHex,
                        textTone: $0.textTone
                    )
                )
            }

        let rows: [CalendarEventDayItem] = normalizedEvents
            .compactMap { event -> (startsAt: Date, row: CalendarEventDayItem.Row)? in
                guard
                    case .row(let rowDate, let startsAt, let startTimeText) =
                        event.kind,
                    rowDate == date
                else {
                    return nil
                }
                return (
                    startsAt,
                    CalendarEventDayItem.Row(
                        id: event.id,
                        title: event.title,
                        startTimeText: startTimeText,
                        colorHex: event.colorHex
                    )
                )
            }
            .sorted { $0.startsAt < $1.startsAt }
            .map { .row($0.row) }

        let headingFormatter = DateFormatter()
        headingFormatter.calendar = calendar
        headingFormatter.locale = environment.locale
        headingFormatter.timeZone = environment.timeZone
        headingFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")

        return CalendarEventDaySelection(
            date: date,
            heading: headingFormatter.string(from: date),
            items: bars + rows
        )
    }

    /// Reprojects the selected identity from the canonical collection after
    /// replacement. Absence means deletion, decline, or movement outside the
    /// refreshed canonical range and dismisses the popover.
    private func reconcileSelectedEvent() {
        guard let selectedEvent else {
            return
        }
        self.selectedEvent = detailSelection(forEventID: selectedEvent.id)
        if self.selectedEvent == nil {
            selectedEventDrilledFromDay = nil
        }
    }

    /// Reprojects the summoned day from the canonical collection after
    /// replacement, so the open Day Events Popover follows refreshed
    /// Calendar Events like the Event Detail Popover: edits and moves
    /// update items in place, deletions and declines remove them. When the
    /// day's last Calendar Event disappears, the popover dismisses itself —
    /// an empty read-only list is a dead end.
    private func reconcileSelectedDayEvents() {
        guard let selectedDayEvents else {
            return
        }
        let projection = dayEventsSelection(for: selectedDayEvents.date)
        self.selectedDayEvents = projection.items.isEmpty ? nil : projection
    }

    /// Projects one canonical normalized event into the popover's observable
    /// selection value. Keeping construction here makes initial selection and
    /// every later reconciliation share the same identity/detail invariant.
    private func detailSelection(
        forEventID id: String
    ) -> CalendarEventDetailSelection? {
        guard let event = normalizedEvents.first(where: { $0.id == id }) else {
            return nil
        }
        return CalendarEventDetailSelection(
            id: event.id,
            sourceCalendar: event.sourceCalendar,
            detail: event.detail
        )
    }

    /// Publishes the disclosure-gated, reconciled Selected Source Calendars.
    /// `nil` suspends Calendar data and clears the presented events; an
    /// empty selection is the successful no-source exception and starts no
    /// request.
    func setSelectedSourceCalendars(
        _ selectedSourceCalendars: [GoogleSourceCalendar]?
    ) {
        guard adapter != nil else {
            return
        }
        let selected = selectedSourceCalendars ?? []
        let connected = selectedSourceCalendars != nil
        guard !orchestration.usesResolvedSourceCalendars
                || connected != orchestration.isConnected
                || selected != sourceCalendars
        else {
            return
        }

        connectionGeneration += 1
        // Stored Calendar Events presented at process start stay on the
        // surface across selection publications until the first successful
        // response replaces them atomically: the grid never blanks behind
        // an in-flight refresh, and a transitional nil publication (the
        // Source Calendars module resetting on account arrival) never
        // clears them. The zero-source exception is Calendar-data truth
        // and clears them with the store.
        let retainStoredPresentation = isPresentingStoredEvents
            && fetchedWindow == nil && !(connected && selected.isEmpty)
        fetchedWindow = nil
        sourceCalendars = selected
        if !retainStoredPresentation {
            isPresentingStoredEvents = false
            normalizedEvents = []
            weekLayouts = [:]
        }
        selectedEvent = nil
        selectedEventDrilledFromDay = nil
        selectedDayEvents = nil
        if connected && selected.isEmpty {
            // The zero-source exception mirrors an empty Fetched Window:
            // the account's Stored Calendar Events empty with it.
            writeStore()
        }
        feed(
            .connectionPublished(
                connected: connected,
                usesResolvedSelection: true,
                selectionIsEmpty: selected.isEmpty
            )
        )
    }

    /// The Calendar-data boundary's account publication. An account
    /// arrives only after the current disclosure is acknowledged, so its
    /// Stored Calendar Events may then present; moving away from a
    /// published account — Disconnect on This Device, confirmed
    /// expiration, or scope loss — wipes the store, and no transition
    /// ever lets one account's events reach another.
    func setCalendarDataAccountID(_ accountID: String?) {
        guard accountID != storedAccountID else {
            return
        }
        if storedAccountID != nil {
            eventStore?.wipeSnapshots()
            isPresentingStoredEvents = false
            normalizedEvents = []
            weekLayouts = [:]
            setSelectedSourceCalendars(nil)
        }
        storedAccountID = accountID
        guard let accountID else {
            return
        }
        guard let snapshot = eventStore?.loadSnapshot() else {
            return
        }
        // The store holds at most one account's snapshot; a snapshot that
        // does not belong to the published account is wiped rather than
        // presented.
        guard snapshot.accountID == accountID else {
            eventStore?.wipeSnapshots()
            return
        }
        presentStoredSnapshot(snapshot)
    }

    /// Presents Stored Calendar Events at process start, online or
    /// offline, before any account publication: at most one account's
    /// snapshot exists, and the composition root calls this only when the
    /// installation has acknowledged the current disclosure. The stored
    /// view is always stale — freshness coverage starts empty and the
    /// ordinary fetching rules schedule requests exactly as if no events
    /// existed — and the first successful response replaces it
    /// atomically.
    func presentStoredCalendarEvents() {
        guard !orchestration.isConnected, normalizedEvents.isEmpty,
              let snapshot = eventStore?.loadSnapshot()
        else {
            return
        }
        storedAccountID = snapshot.accountID
        presentStoredSnapshot(snapshot)
    }

    /// Projects one stored snapshot onto the surface: the normalized
    /// events and their Week Row layouts, with no freshness, no Fetched
    /// Window, and no fetch side effects. An empty snapshot presents the
    /// bare, usable Calendar Grid.
    private func presentStoredSnapshot(
        _ snapshot: StoredCalendarEventsSnapshot
    ) {
        let stored = snapshot.events
        guard !stored.isEmpty else {
            return
        }
        normalizedEvents = stored
        isPresentingStoredEvents = true

        let calendar = environment.calendar
        var first: Date?
        var last: Date?
        for event in stored {
            let dates: (start: Date, end: Date)
            switch event.kind {
            case .bar(let startDate, let endDate, _):
                dates = (startDate, endDate)
            case .row(let date, _, _):
                dates = (date, date)
            }
            first = min(first ?? dates.start, dates.start)
            last = max(last ?? dates.end, dates.end)
        }
        guard let first, let last,
              let end = calendar.date(byAdding: .day, value: 1, to: last)
        else {
            return
        }
        publishWeeks(covering: (start: first, end: end))
    }

    /// Write-through (iOS ADR 0007): every successful initial, slab, or
    /// Calendar Event Refresh response updates the store with the
    /// in-memory model, so process death never resurrects Calendar Events
    /// older than the last successful response. Entries that fell out of
    /// the Fetched Window and events from deselected Source Calendars
    /// disappear with the write; no separate eviction policy exists.
    /// Writes happen only while a disclosure-acknowledged account is
    /// published.
    private func writeStore() {
        guard let storedAccountID else {
            return
        }
        eventStore?.saveSnapshot(
            StoredCalendarEventsSnapshot(
                accountID: storedAccountID,
                events: normalizedEvents
            )
        )
    }

    /// Pauses new routine work while the native picker is open. Physical work
    /// already in flight may finish; all new triggers continue to coalesce.
    func sourceCalendarPickerDidOpen() {
        feed(.pickerPresented)
    }

    /// Resumes routine work after an unchanged dismissal, or invalidates older
    /// publication and starts one visible-centered atomic replacement after a
    /// changed dismissal.
    func sourceCalendarPickerDidClose(
        selectedSourceCalendars: [GoogleSourceCalendar],
        selectionChanged: Bool
    ) {
        guard orchestration.isConnected, orchestration.isPickerPresented else {
            return
        }
        if selectionChanged {
            sourceCalendars = selectedSourceCalendars
            connectionGeneration += 1
        }
        feed(.pickerDismissed(selectionChanged: selectionChanged))
    }

    /// Legacy Primary-only connection seam retained for deterministic tests
    /// and previews. Production uses `setSelectedSourceCalendars(_:)`.
    func setConnected(_ connected: Bool) {
        guard adapter != nil, connected != orchestration.isConnected else {
            return
        }
        connectionGeneration += 1

        guard connected else {
            fetchedWindow = nil
            sourceCalendars = []
            normalizedEvents = []
            selectedEvent = nil
            selectedDayEvents = nil
            weekLayouts = [:]
            feed(
                .connectionPublished(
                    connected: false,
                    usesResolvedSelection: false,
                    selectionIsEmpty: false
                )
            )
            return
        }

        feed(
            .connectionPublished(
                connected: true,
                usesResolvedSelection: false,
                selectionIsEmpty: false
            )
        )
    }

    /// Feeds one signal through Calendar Event Fetch Orchestration:
    /// applies the event, publishes the decided status, executes every
    /// emitted fetch command, and reconciles cadence against the new
    /// decision state. A `nil` adapter leaves the module permanently
    /// inert: no event is ever fed, nothing fetches, nothing renders.
    private func feed(_ event: CalendarEventFetchOrchestration.Event) {
        guard let adapter else {
            return
        }
        let commands = CalendarEventFetchOrchestration.handle(
            &orchestration,
            event,
            environment: environment,
            now: cadenceScheduler.now
        )
        status = orchestration.status
        for command in commands {
            execute(command, adapter: adapter)
        }
        reconcileCadence()
    }

    /// Starts one serialized Calendar Event request the orchestration
    /// decided on. The completion — applied, failed, or discarded as
    /// stale — is reported back as an event.
    private func execute(
        _ command: CalendarEventFetchOrchestration.Command,
        adapter: any GoogleCalendarEventsAdapting
    ) {
        switch command {
        case .beginInitialFetch(let windowStart, let windowEnd):
            beginInitialFetch(
                adapter: adapter,
                windowStart: windowStart,
                windowEnd: windowEnd
            )
        case .extendWindow(let from, let to, let direction):
            extend(adapter: adapter, from: from, to: to, direction: direction)
        case .refresh(let start, let end):
            beginRefresh(adapter: adapter, start: start, end: end)
        case .replaceSelection(let start, let end):
            beginSelectionReplacement(adapter: adapter, start: start, end: end)
        }
    }

    /// Reconciles the pending cadence wait against the orchestration's
    /// decision: scheduled only while bounded refresh has every input it
    /// needs and no serialized work is outstanding, making cadence
    /// completion-relative instead of wall-clock based.
    private func reconcileCadence() {
        guard orchestration.wantsCadence else {
            cancelCadence()
            return
        }
        guard cadenceSchedule == nil else {
            return
        }
        cadenceSchedule = cadenceScheduler.schedule(
            after: CalendarEventFetchOrchestration.cadenceInterval
        ) { [weak self] in
            guard let self else {
                return
            }
            cadenceSchedule = nil
            feed(.cadenceFired)
        }
    }

    /// Cancels the pending interval synchronously. Its action captures the
    /// model weakly, so scheduler ownership can never extend model lifetime.
    private func cancelCadence() {
        cadenceSchedule?.cancel()
        cadenceSchedule = nil
    }

    /// Fetches the initial Fetched Window — three months before Today
    /// through three months after — announcing progress in the iOS Header
    /// Status. A failure reports Planner-owned copy and leaves the window
    /// unfetched: an offline failure retries when connectivity returns.
    private func beginInitialFetch(
        adapter: any GoogleCalendarEventsAdapting,
        windowStart: Date,
        windowEnd: Date
    ) {
        let attempt = connectionGeneration
        let resolvedSourceCalendars = sourceCalendars
        let usesResolvedSourceCalendars =
            orchestration.usesResolvedSourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery
        Task { [weak self] in
            let requestedSourceCalendars: [GoogleSourceCalendar]
            if usesResolvedSourceCalendars {
                requestedSourceCalendars = resolvedSourceCalendars
            } else {
                let sourceOutcome = await adapter.fetchPrimarySourceCalendar()
                guard let self else {
                    return
                }
                guard self.connectionGeneration == attempt else {
                    self.feed(.fetchCompleted(.initial, .discarded))
                    return
                }

                switch sourceOutcome {
                case .success(let sourceCalendar):
                    requestedSourceCalendars = [sourceCalendar]
                case .unavailable(let failure):
                    self.feed(.fetchCompleted(.initial, .failed(failure)))
                    return
                }
            }

            let result = await Self.fetchEventsRecoveringSource(
                adapter: adapter,
                recovery: sourceCalendarRecovery,
                from: requestedSourceCalendars,
                start: windowStart,
                end: windowEnd
            )

            // A stale completion must not overwrite a newer decision: after
            // Disconnect on This Device or a newer connection, its events
            // are discarded, but its physical request first releases the
            // serialized adapter seam.
            guard let self else {
                return
            }
            guard attempt == connectionGeneration else {
                feed(.fetchCompleted(.initial, .discarded))
                return
            }
            // Adopt the effective selection even when the retry failed: it
            // is the persisted truth later requests must use.
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                let window = CalendarEventFetchOrchestration.FetchRange(
                    start: windowStart,
                    end: windowEnd
                )
                fetchedWindow = window
                normalizedEvents = CalendarEventNormalization.normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds,
                    environment: environment
                )
                isPresentingStoredEvents = false
                writeStore()
                weekLayouts = [:]
                publishWeeks(covering: (start: windowStart, end: windowEnd))
                feed(.fetchedWindowChanged(to: window))
                feed(.fetchCompleted(.initial, .applied(window)))
            case .unavailable(let failure):
                feed(.fetchCompleted(.initial, .failed(failure)))
            }
        }
    }

    /// One aggregate event request with forbidden/not-found recovery: when a
    /// selected source proves unavailable, the Source Calendars module
    /// reloads live Source Calendars, reconciles, and this request retries
    /// once against the effective selection. The returned selection is the
    /// effective one the caller adopts; a failed reload keeps the durable
    /// selection and lets the caller report the original failure.
    private static func fetchEventsRecoveringSource(
        adapter: any GoogleCalendarEventsAdapting,
        recovery: (any SourceCalendarRecoveryHandling)?,
        from sourceCalendars: [GoogleSourceCalendar],
        start: Date,
        end: Date
    ) async -> (
        outcome: GoogleCalendarEventsOutcome,
        sourceCalendars: [GoogleSourceCalendar]
    ) {
        let outcome = await adapter.fetchEvents(
            from: sourceCalendars,
            start: start,
            end: end
        )
        guard case .unavailable(.sourceUnavailable) = outcome,
              let recovery
        else {
            return (outcome, sourceCalendars)
        }
        guard
            let reconciled =
                await recovery.reconcileSelectionAfterSourceFailure()
        else {
            return (outcome, sourceCalendars)
        }
        let retry = await adapter.fetchEvents(
            from: reconciled,
            start: start,
            end: end
        )
        return (retry, reconciled)
    }

    /// Publishes foreground-active versus inactive scene state. Foreground
    /// entry requests the immediate bounded refresh delivered by the refresh
    /// slice; leaving the foreground cancels cadence and any queued refresh
    /// signal while allowing a physical request already in flight to finish.
    func setSceneActive(_ active: Bool) {
        feed(.sceneActive(active))
    }

    /// Requests a bounded Calendar Event Refresh after the app returns to
    /// the foreground. One pending signal survives initial, slab, or refresh
    /// work and later uses the newest visible range.
    func refreshOnForeground() {
        feed(.foregroundRefresh)
    }

    /// Runs the orchestration's bounded Calendar Event Refresh decision.
    /// The latest visible dates grow by one month on each side and clamp
    /// to the Fetched Window; refresh never expands it.
    private func beginRefresh(
        adapter: any GoogleCalendarEventsAdapting,
        start refreshStart: Date,
        end refreshEnd: Date
    ) {
        let attempt = connectionGeneration
        let requestedSourceCalendars = sourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery
        Task { [weak self] in
            let result = await Self.fetchEventsRecoveringSource(
                adapter: adapter,
                recovery: sourceCalendarRecovery,
                from: requestedSourceCalendars,
                start: refreshStart,
                end: refreshEnd
            )
            guard let self else {
                return
            }
            guard attempt == connectionGeneration else {
                feed(.fetchCompleted(.refresh, .discarded))
                return
            }
            // Adopt the effective selection even when the retry failed: it
            // is the persisted truth later requests must use.
            sourceCalendars = result.sourceCalendars

            let range = CalendarEventFetchOrchestration.FetchRange(
                start: refreshStart,
                end: refreshEnd
            )
            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                applyRefresh(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds,
                    range: (start: refreshStart, end: refreshEnd)
                )
                writeStore()
                feed(.fetchCompleted(.refresh, .applied(range)))
            case .unavailable(let failure):
                feed(.fetchCompleted(.refresh, .failed(failure)))
            }
        }
    }

    /// Atomically replaces Calendar Events intersecting one successful
    /// bounded refresh while preserving unrelated events. Returned canonical
    /// identities also evict an old off-range form of an occurrence that
    /// moved into the refreshed range; cancelled and declined events
    /// therefore remove their prior presentation even though normalization
    /// drops them.
    private func applyRefresh(
        _ events: [GoogleSourceCalendarEvent],
        eventColorBackgrounds: [String: String],
        range: (start: Date, end: Date)
    ) {
        let returnedIDs = Set(
            events.map { CalendarEventCanonicalIdentity.id(of: $0) }
        )
        let removedEvents = normalizedEvents.filter {
            intersects($0, range: range) || returnedIDs.contains($0.id)
        }
        var nextEvents = normalizedEvents.filter {
            !intersects($0, range: range) && !returnedIDs.contains($0.id)
        }
        let refreshedEvents = CalendarEventNormalization.normalize(
            events,
            eventColorBackgrounds: eventColorBackgrounds,
            environment: environment
        )
        for event in refreshedEvents {
            nextEvents.removeAll { $0.id == event.id }
            nextEvents.append(event)
        }

        var affectedWeeks = Set<Date>()
        for event in removedEvents + refreshedEvents {
            affectedWeeks.formUnion(weekStarts(intersecting: event))
        }

        var nextLayouts = weekLayouts
        for weekStart in affectedWeeks {
            let layout = layoutWeek(nextEvents, weekStart: weekStart)
            if layout.bars.isEmpty
                && !layout.cells.contains(where: { !$0.rows.isEmpty })
            {
                nextLayouts.removeValue(forKey: weekStart)
            } else {
                nextLayouts[weekStart] = layout
            }
        }

        normalizedEvents = nextEvents
        weekLayouts = nextLayouts
        reconcileSelectedEvent()
        reconcileSelectedDayEvents()
    }

    /// Whether one normalized event's presented local dates intersect a
    /// half-open fetched range.
    private func intersects(
        _ event: CalendarEvent,
        range: (start: Date, end: Date)
    ) -> Bool {
        switch event.kind {
        case .row(let date, _, _):
            return date >= range.start && date < range.end
        case .bar(let startDate, let endDate, _):
            return startDate < range.end && endDate >= range.start
        }
    }

    /// Every Monday-first Week Row touched by one normalized event.
    private func weekStarts(intersecting event: CalendarEvent) -> Set<Date> {
        let calendar = environment.calendar
        let firstDate: Date
        let lastDate: Date
        switch event.kind {
        case .row(let date, _, _):
            firstDate = date
            lastDate = date
        case .bar(let startDate, let endDate, _):
            firstDate = startDate
            lastDate = endDate
        }

        var result = Set<Date>()
        var weekStart = startOfMondayWeek(containing: firstDate)
        let lastWeekStart = startOfMondayWeek(containing: lastDate)
        while weekStart <= lastWeekStart {
            result.insert(weekStart)
            guard let next = calendar.date(
                byAdding: .day,
                value: 7,
                to: weekStart
            ) else {
                break
            }
            weekStart = next
        }
        return result
    }

    /// Handles connectivity returning after an offline period: an unfetched
    /// initial window, failed Calendar Event Refresh, or failed slab retries
    /// against the latest visible range.
    private func handleConnectivityReturn() {
        feed(.connectivityReturned)
    }

    /// Reports the currently visible local-date range (as Week Row start
    /// instants) and grows the Fetched Window when either edge comes within
    /// one month of it: a two-month slab fetch in that direction, once per
    /// range per process run. A failed slab leaves the window unchanged, so
    /// the next approach retries it. Approaches before the initial window
    /// lands do nothing — the initial fetch owns that range.
    func showVisibleRange(from visibleStart: Date, through visibleEnd: Date) {
        feed(.visibleRange(start: visibleStart, end: visibleEnd))
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
        direction: CalendarEventFetchOrchestration.ExtensionDirection
    ) {
        let kind: CalendarEventFetchOrchestration.FetchKind =
            switch direction {
            case .forward: .slabForward
            case .backward: .slabBackward
            }
        let attempt = connectionGeneration
        let requestedSourceCalendars = sourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery
        Task { [weak self] in
            let result = await Self.fetchEventsRecoveringSource(
                adapter: adapter,
                recovery: sourceCalendarRecovery,
                from: requestedSourceCalendars,
                start: fetchStart,
                end: fetchEnd
            )

            guard let self else {
                return
            }
            guard attempt == connectionGeneration else {
                feed(.fetchCompleted(kind, .discarded))
                return
            }
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                // Google delivers every event overlapping the requested
                // range, so an event spanning a previously fetched range's
                // boundary arrives again here. The fresh copy replaces the
                // retained one: one entry per event id keeps every Week
                // Row to one segment per event.
                let slabEvents = CalendarEventNormalization.normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds,
                    environment: environment
                )
                let redeliveredIds = Set(slabEvents.map(\.id))
                normalizedEvents.removeAll { redeliveredIds.contains($0.id) }
                normalizedEvents.append(contentsOf: slabEvents)
                writeStore()
                reconcileSelectedEvent()
                reconcileSelectedDayEvents()
                switch direction {
                case .forward:
                    fetchedWindow?.end = fetchEnd
                case .backward:
                    fetchedWindow?.start = fetchStart
                }
                publishWeeks(covering: (start: fetchStart, end: fetchEnd))
                feed(.fetchedWindowChanged(to: fetchedWindow))
                feed(
                    .fetchCompleted(
                        kind,
                        .applied(
                            CalendarEventFetchOrchestration.FetchRange(
                                start: fetchStart,
                                end: fetchEnd
                            )
                        )
                    )
                )
            case .unavailable(let failure):
                feed(.fetchCompleted(kind, .failed(failure)))
            }
        }
    }

    /// Replaces the complete Calendar Event snapshot around the latest visible
    /// dates after a final Selected Source Calendars change. The prior snapshot
    /// and Fetched Window stay intact until the complete aggregate succeeds.
    private func beginSelectionReplacement(
        adapter: any GoogleCalendarEventsAdapting,
        start rangeStart: Date,
        end rangeEnd: Date
    ) {
        let attempt = connectionGeneration
        let requestedSourceCalendars = sourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery

        Task { [weak self] in
            let result = await Self.fetchEventsRecoveringSource(
                adapter: adapter,
                recovery: sourceCalendarRecovery,
                from: requestedSourceCalendars,
                start: rangeStart,
                end: rangeEnd
            )
            guard let self else {
                return
            }
            guard attempt == connectionGeneration else {
                feed(.fetchCompleted(.selectionReplacement, .discarded))
                return
            }
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                let range = CalendarEventFetchOrchestration.FetchRange(
                    start: rangeStart,
                    end: rangeEnd
                )
                fetchedWindow = range
                normalizedEvents = CalendarEventNormalization.normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds,
                    environment: environment
                )
                isPresentingStoredEvents = false
                writeStore()
                weekLayouts = [:]
                publishWeeks(covering: (start: rangeStart, end: rangeEnd))
                reconcileSelectedEvent()
                reconcileSelectedDayEvents()
                feed(.fetchedWindowChanged(to: range))
                feed(.fetchCompleted(.selectionReplacement, .applied(range)))
            case .unavailable(let failure):
                feed(.fetchCompleted(.selectionReplacement, .failed(failure)))
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
        _ events: [CalendarEvent],
        weekStart: Date
    ) -> CalendarEventWeekLayout {
        let calendar = environment.calendar
        let segments = placedBarSegments(events, weekStart: weekStart)

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
                        sourceCalendar: event.sourceCalendar,
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

    /// Every Calendar Event Bar segment of one Week Row with its assigned
    /// lane, before the visible cap filters: bars clipped to the Week Row,
    /// lane-packed in global order — start date, then start time, then
    /// longer duration first. The visible cell layout and the Day Events
    /// Popover's complete day list share this one placement so their lane
    /// ordering can never drift.
    private func placedBarSegments(
        _ events: [CalendarEvent],
        weekStart: Date
    ) -> [CalendarEventBarSegment] {
        let calendar = environment.calendar
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!

        struct PlacedBar {
            let event: CalendarEvent
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
                    sourceCalendar: bar.event.sourceCalendar,
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
        return segments
    }

    // MARK: Local dates

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

    /// A Week Row renders at most this many bar lanes at the fixed
    /// 96-point height; further lanes count into Events Overflow instead
    /// of rendering.
    private static let maxVisibleBarLanes = 3
}
