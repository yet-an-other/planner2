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

/// Canonical cross-calendar occurrence identity: the same occurrence
/// returned through multiple Selected Source Calendars presents once.
/// Google's `iCalUID` plus `originalStartTime` when supplied — otherwise
/// the occurrence's all-day date or timed start — identifies one
/// occurrence across sources, so distinct recurring instances, including
/// moved ones, never collapse. Without an `iCalUID`, identity falls back
/// to Source Calendar ID plus Google's event ID: Planner never guesses
/// that unrelated fallback events across calendars are duplicates.
enum CalendarEventCanonicalIdentity {
    /// The canonical occurrence identity of one fetched copy, used as the
    /// Calendar Event's identity for deduplication, layout, and the Event
    /// Detail selection. Opaque beyond its uniqueness and stability
    /// guarantees; it persists inside Stored Calendar Events exactly so a
    /// stored event keeps its canonical identity (iOS ADR 0007).
    static func id(of sourceEvent: GoogleSourceCalendarEvent) -> String {
        let event = sourceEvent.event
        if let iCalUID = event.iCalUID?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !iCalUID.isEmpty {
            let occurrence = event.originalStartTime ?? event.start
            return "ical:\(iCalUID):occurrence:\(occurrenceStamp(occurrence))"
        }
        return "src:\(sourceEvent.sourceCalendar.id):event:\(event.id)"
    }

    private static func occurrenceStamp(
        _ time: GoogleCalendarEventTime
    ) -> String {
        switch time {
        case .allDay(let year, let month, let day):
            return "date-\(year)-\(month)-\(day)"
        case .timed(let instant):
            return "time-\(instant.timeIntervalSince1970)"
        }
    }
}

/// The readable text tone on top of an Event Color.
enum CalendarEventTextTone: Equatable, Sendable, Codable {
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

    /// The last visible range reported by the Calendar Screen, re-checked
    /// when connectivity returns so owed slabs retry.
    @ObservationIgnored
    private var lastVisibleRange: (start: Date, end: Date)?

    /// Whether the initial Fetched Window fetch is in flight.
    @ObservationIgnored
    private var isFetchingInitialWindow = false

    /// Whether a bounded Calendar Event Refresh is in flight.
    @ObservationIgnored
    private var isRefreshingEvents = false

    /// Foreground and recovery signals coalesce here while another Calendar
    /// Event request owns the serialized adapter seam.
    @ObservationIgnored
    private var isRefreshPending = false

    /// Routine Calendar Event work pauses while the native Source Calendar
    /// Picker is open. Signals still coalesce in their existing pending flags.
    @ObservationIgnored
    private var isSourceCalendarPickerPresented = false

    /// A final changed selection owes one whole-snapshot, visible-centered
    /// replacement. It takes priority over slabs and bounded refreshes.
    @ObservationIgnored
    private var isSelectionReplacementPending = false

    /// Whether that whole-snapshot replacement currently owns the serialized
    /// aggregate adapter seam.
    @ObservationIgnored
    private var isReplacingSelection = false

    /// A changed visible range leaves one freshness decision owed while
    /// another Calendar Event request owns the serialized adapter seam.
    @ObservationIgnored
    private var needsBrowsingFreshnessCheck = false

    /// A failed Calendar Event Refresh remains owed so connectivity return
    /// can retry it and other fetch progress can restore its warning.
    @ObservationIgnored
    private var refreshFailure: GoogleCalendarEventsFailure?

    /// The local-date bounds of the Fetched Window, when it has been
    /// fetched: `[windowStart, windowEnd)` as start-of-day instants.
    @ObservationIgnored
    private var fetchedWindow: (start: Date, end: Date)?

    /// Every fetched event in normalized form, retained so a slab can
    /// recompute its boundary Week Row from old and new events together.
    /// At most one entry per event id: slabs redeliver events spanning a
    /// fetched range's boundary, and the fresh copy replaces the retained
    /// one. Persisted only through the Stored Calendar Events boundary
    /// (ADR 0007) and cleared on Disconnect on This Device.
    @ObservationIgnored
    private var normalizedEvents: [NormalizedEvent] = []

    /// Successful initial, slab, and refresh completion coverage. This is
    /// process-local bookkeeping only: it is never persisted and vanishes
    /// with Disconnect on This Device or model teardown.
    @ObservationIgnored
    private var freshnessCoverage: [FreshnessCoverage] = []

    /// In-flight slab directions, so repeated edge approaches can never
    /// duplicate a fetch.
    @ObservationIgnored
    private var isExtendingForward = false

    @ObservationIgnored
    private var isExtendingBackward = false

    /// A failed slab waits for another visible-range or connectivity signal
    /// instead of looping immediately through serialized follow-up work.
    @ObservationIgnored
    private var isSlabRetryBlocked = false

    /// Whether the iOS scene is foreground-active. Calendar Event Refresh
    /// cadence exists only while this and the connection are both active.
    @ObservationIgnored
    private var isSceneActive = false

    /// The single cancellable five-minute wait. A new Calendar Event request
    /// cancels it; the next wait begins only after serialized work completes.
    @ObservationIgnored
    private var cadenceSchedule: (any CalendarEventsCadenceSchedule)?

    /// Whether the module currently treats the Google Account Connection
    /// as connected; repeated reports of the same state are no-ops, so a
    /// republished connection can never wedge or duplicate a fetch.
    @ObservationIgnored
    private var isConnected = false

    /// Production receives a disclosure-gated, reconciled selection from the
    /// Source Calendars module. The legacy connection method remains as a
    /// deterministic test and preview seam for the earlier Primary-only path.
    @ObservationIgnored
    private var usesResolvedSourceCalendars = false

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
        guard let adapter else {
            return
        }
        let selected = selectedSourceCalendars ?? []
        let connected = selectedSourceCalendars != nil
        guard !usesResolvedSourceCalendars
                || connected != isConnected
                || selected != sourceCalendars
        else {
            return
        }

        usesResolvedSourceCalendars = true
        isConnected = connected
        connectionGeneration += 1
        cancelCadence()
        isSourceCalendarPickerPresented = false
        isSelectionReplacementPending = false
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
        freshnessCoverage = []
        needsBrowsingFreshnessCheck = false
        isRefreshPending = false
        refreshFailure = nil
        isSlabRetryBlocked = false
        status = CalendarEventsStatus(message: nil, tone: .info)

        guard connected, !selected.isEmpty else {
            // The zero-source exception mirrors an empty Fetched Window:
            // the account's Stored Calendar Events empty with it.
            if connected {
                writeStore()
            }
            return
        }
        beginInitialFetch(adapter: adapter)
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
        guard !isConnected, normalizedEvents.isEmpty,
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
        let stored = snapshot.events.map(Self.normalizedEvent(from:))
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
                events: normalizedEvents.map(Self.storedEvent(from:))
            )
        )
    }

    /// Pauses new routine work while the native picker is open. Physical work
    /// already in flight may finish; all new triggers continue to coalesce.
    func sourceCalendarPickerDidOpen() {
        guard isConnected, !isSourceCalendarPickerPresented else {
            return
        }
        isSourceCalendarPickerPresented = true
        cancelCadence()
    }

    /// Resumes routine work after an unchanged dismissal, or invalidates older
    /// publication and starts one visible-centered atomic replacement after a
    /// changed dismissal.
    func sourceCalendarPickerDidClose(
        selectedSourceCalendars: [GoogleSourceCalendar],
        selectionChanged: Bool
    ) {
        guard isConnected, isSourceCalendarPickerPresented else {
            return
        }
        isSourceCalendarPickerPresented = false

        if selectionChanged {
            sourceCalendars = selectedSourceCalendars
            connectionGeneration += 1
            cancelCadence()
            isSelectionReplacementPending = true
            refreshFailure = nil
            status = CalendarEventsStatus(
                message: CalendarEventsCopy.updatingSelection,
                tone: .info
            )
        }

        drainFetchWork()
        scheduleCadenceIfEligible()
    }

    /// Legacy Primary-only connection seam retained for deterministic tests
    /// and previews. Production uses `setSelectedSourceCalendars(_:)`.
    func setConnected(_ connected: Bool) {
        guard let adapter, connected != isConnected else {
            return
        }

        usesResolvedSourceCalendars = false
        isConnected = connected
        connectionGeneration += 1

        guard connected else {
            cancelCadence()
            isSourceCalendarPickerPresented = false
            isSelectionReplacementPending = false
            fetchedWindow = nil
            sourceCalendars = []
            normalizedEvents = []
            selectedEvent = nil
            selectedDayEvents = nil
            freshnessCoverage = []
            needsBrowsingFreshnessCheck = false
            // The active request keeps its operation flag until its adapter
            // call returns. A reconnect queues behind that physical work;
            // only publication is invalidated immediately.
            isRefreshPending = false
            refreshFailure = nil
            isSlabRetryBlocked = false
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
        guard fetchedWindow == nil, !hasFetchInFlight,
              !isSourceCalendarPickerPresented,
              !usesResolvedSourceCalendars || !sourceCalendars.isEmpty
        else {
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

        cancelCadence()
        isFetchingInitialWindow = true
        status = CalendarEventsStatus(
            message: CalendarEventsCopy.loading,
            tone: .info
        )

        let attempt = connectionGeneration
        let resolvedSourceCalendars = sourceCalendars
        let usesResolvedSourceCalendars = usesResolvedSourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery
        Task { [weak self] in
            let requestedSourceCalendars: [GoogleSourceCalendar]
            if usesResolvedSourceCalendars {
                requestedSourceCalendars = resolvedSourceCalendars
            } else {
                let sourceOutcome = await adapter.fetchPrimarySourceCalendar()
                guard self != nil else {
                    return
                }
                guard self?.connectionGeneration == attempt else {
                    self?.isFetchingInitialWindow = false
                    self?.resumeAfterStaleFetch()
                    return
                }

                switch sourceOutcome {
                case .success(let sourceCalendar):
                    requestedSourceCalendars = [sourceCalendar]
                case .unavailable(let failure):
                    self?.isFetchingInitialWindow = false
                    self?.publishInitialFailure(failure)
                    self?.scheduleCadenceIfEligible()
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
                isFetchingInitialWindow = false
                resumeAfterStaleFetch()
                return
            }
            isFetchingInitialWindow = false
            // Adopt the effective selection even when the retry failed: it
            // is the persisted truth later requests must use.
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                fetchedWindow = (windowStart, windowEnd)
                normalizedEvents = normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds
                )
                isPresentingStoredEvents = false
                writeStore()
                weekLayouts = [:]
                publishWeeks(covering: (start: windowStart, end: windowEnd))
                recordFreshness(
                    for: (start: windowStart, end: windowEnd),
                    completedAt: cadenceScheduler.now
                )
                clearStatusIfIdle()
                drainFetchWork()
                scheduleCadenceIfEligible()
            case .unavailable(let failure):
                publishInitialFailure(failure)
                scheduleCadenceIfEligible()
            }
        }
    }

    /// Publishes Planner-owned initial-fetch failure copy for either Primary
    /// Source Calendar discovery or its aggregate Calendar Event request.
    private func publishInitialFailure(_ failure: GoogleCalendarEventsFailure) {
        status = switch failure {
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
        guard active != isSceneActive else {
            return
        }

        isSceneActive = active
        guard active else {
            isRefreshPending = false
            cancelCadence()
            return
        }
        guard isConnected, let adapter else {
            return
        }
        if isSelectionReplacementPending {
            drainFetchWork()
            scheduleCadenceIfEligible()
        } else if fetchedWindow == nil {
            beginInitialFetch(adapter: adapter)
        } else {
            requestRefresh()
        }
    }

    /// Requests a bounded Calendar Event Refresh after the app returns to
    /// the foreground. One pending signal survives initial, slab, or refresh
    /// work and later uses the newest visible range.
    func refreshOnForeground() {
        if isSceneActive {
            requestRefresh()
        } else {
            setSceneActive(true)
        }
    }

    /// Coalesces one refresh signal against current scene and range state.
    private func requestRefresh() {
        guard adapter != nil, isConnected, isSceneActive,
              (fetchedWindow != nil || isSelectionReplacementPending),
              lastVisibleRange != nil
        else {
            return
        }
        isRefreshPending = true
        drainFetchWork()
    }

    /// Starts the already-authorized refresh decision. The latest visible
    /// dates grow by one month on each side and clamp to the Fetched Window;
    /// refresh never expands it.
    private func beginRefresh(
        adapter: any GoogleCalendarEventsAdapting,
        window: (start: Date, end: Date),
        visible: (start: Date, end: Date)
    ) -> Bool {
        guard let range = boundedRefreshRange(window: window, visible: visible)
        else {
            return false
        }
        let refreshStart = range.start
        let refreshEnd = range.end

        cancelCadence()
        isRefreshingEvents = true
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
            isRefreshingEvents = false
            guard attempt == connectionGeneration else {
                resumeAfterStaleFetch()
                return
            }
            // Adopt the effective selection even when the retry failed: it
            // is the persisted truth later requests must use.
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                applyRefresh(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds,
                    range: (start: refreshStart, end: refreshEnd)
                )
                writeStore()
                recordFreshness(
                    for: (start: refreshStart, end: refreshEnd),
                    completedAt: cadenceScheduler.now
                )
                refreshFailure = nil
                clearStatusIfIdle()
            case .unavailable(let failure):
                refreshFailure = failure
                clearStatusIfIdle()
            }
            drainFetchWork()
            scheduleCadenceIfEligible()
        }
        return true
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
        let refreshedEvents = normalize(
            events,
            eventColorBackgrounds: eventColorBackgrounds
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
        _ event: NormalizedEvent,
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
    private func weekStarts(intersecting event: NormalizedEvent) -> Set<Date> {
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
        guard isConnected, let adapter else {
            return
        }

        isSlabRetryBlocked = false
        if isSelectionReplacementPending {
            drainFetchWork()
        } else if fetchedWindow == nil {
            beginInitialFetch(adapter: adapter)
        } else if isRefreshingEvents || refreshFailure != nil {
            // Preserve this recovery signal if the request that observed the
            // offline state has not completed yet.
            requestRefresh()
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
              !isRefreshingEvents,
              !isExtendingForward,
              !isExtendingBackward
        else {
            return
        }
        status = switch refreshFailure {
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

    /// Reports the currently visible local-date range (as Week Row start
    /// instants) and grows the Fetched Window when either edge comes within
    /// one month of it: a two-month slab fetch in that direction, once per
    /// range per process run. A failed slab leaves the window unchanged, so
    /// the next approach retries it. Approaches before the initial window
    /// lands do nothing — the initial fetch owns that range.
    func showVisibleRange(from visibleStart: Date, through visibleEnd: Date) {
        if lastVisibleRange?.start != visibleStart
            || lastVisibleRange?.end != visibleEnd
        {
            needsBrowsingFreshnessCheck = true
        }
        lastVisibleRange = (visibleStart, visibleEnd)
        isSlabRetryBlocked = false
        drainFetchWork()
        scheduleCadenceIfEligible()
    }

    /// Calendar API requests share one serialized seam. Slab expansion leads
    /// a pending refresh so the latter can clamp against the latest Fetched
    /// Window; all decisions use the newest visible range.
    private func drainFetchWork(allowSlab: Bool = true) {
        guard !hasFetchInFlight, let adapter, isConnected,
              !isSourceCalendarPickerPresented
        else {
            return
        }

        if isSelectionReplacementPending {
            beginSelectionReplacement(adapter: adapter)
            return
        }

        guard let window = fetchedWindow, let visible = lastVisibleRange else {
            return
        }

        let calendar = environment.calendar
        if allowSlab, !isSlabRetryBlocked,
           let lastFetchedDay = calendar.date(
               byAdding: .day,
               value: -1,
               to: window.end
           ),
           let forwardTrigger = addMonthsClamped(-1, to: lastFetchedDay),
           visible.end >= forwardTrigger,
           let newLastDay = addMonthsClamped(2, to: lastFetchedDay),
           let proposedEnd = calendar.date(
               byAdding: .day,
               value: 1,
               to: newLastDay
           ),
           let extendedRange = extendedCalendarRange(),
           case let newEnd = min(proposedEnd, extendedRange.end),
           newEnd > window.end
        {
            isExtendingForward = true
            extend(
                adapter: adapter,
                from: window.end,
                to: newEnd,
                direction: .forward
            )
            return
        }

        if allowSlab, !isSlabRetryBlocked,
           let backwardTrigger = addMonthsClamped(1, to: window.start),
           visible.start <= backwardTrigger,
           let proposedStart = addMonthsClamped(-2, to: window.start),
           let extendedRange = extendedCalendarRange(),
           case let newStart = max(proposedStart, extendedRange.start),
           newStart < window.start
        {
            isExtendingBackward = true
            extend(
                adapter: adapter,
                from: newStart,
                to: window.start,
                direction: .backward
            )
            return
        }

        if needsBrowsingFreshnessCheck, isSceneActive,
           let range = boundedRefreshRange(window: window, visible: visible)
        {
            needsBrowsingFreshnessCheck = false
            if !isFresh(range, at: cadenceScheduler.now) {
                isRefreshPending = true
            }
        }

        guard isRefreshPending, isSceneActive else {
            return
        }
        isRefreshPending = false
        if !beginRefresh(adapter: adapter, window: window, visible: visible) {
            // A visible range can sit beyond a failed expansion slab. Keep
            // the coalesced refresh owed, but re-arm cadence instead of
            // losing it or spinning while no bounded overlap exists.
            isRefreshPending = true
            scheduleCadenceIfEligible()
        }
    }

    /// Starts one five-minute wait only when bounded refresh has every input
    /// it needs. The wait begins after all immediately coalesced fetch work
    /// drains, making cadence completion-relative instead of wall-clock based.
    private func scheduleCadenceIfEligible() {
        guard cadenceSchedule == nil, !hasFetchInFlight, isConnected,
              !isSourceCalendarPickerPresented, isSceneActive,
              (fetchedWindow != nil || isSelectionReplacementPending),
              lastVisibleRange != nil
        else {
            return
        }
        cadenceSchedule = cadenceScheduler.schedule(
            after: Self.refreshCadence
        ) { [weak self] in
            guard let self else {
                return
            }
            cadenceSchedule = nil
            if isSelectionReplacementPending {
                drainFetchWork()
                scheduleCadenceIfEligible()
            } else {
                requestRefresh()
            }
        }
    }

    /// Cancels the pending interval synchronously. Its action captures the
    /// model weakly, so scheduler ownership can never extend model lifetime.
    private func cancelCadence() {
        cadenceSchedule?.cancel()
        cadenceSchedule = nil
    }

    private var hasFetchInFlight: Bool {
        isFetchingInitialWindow || isRefreshingEvents || isExtendingForward
            || isExtendingBackward || isReplacingSelection
    }

    /// Once an obsolete physical request releases the serialized adapter
    /// seam, continue the current connection's initial fetch or queued work.
    private func resumeAfterStaleFetch() {
        guard isConnected, let adapter else {
            return
        }
        if isSelectionReplacementPending {
            drainFetchWork()
            scheduleCadenceIfEligible()
        } else if fetchedWindow == nil {
            beginInitialFetch(adapter: adapter)
        } else {
            drainFetchWork()
            scheduleCadenceIfEligible()
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
        cancelCadence()
        let attempt = connectionGeneration
        status = CalendarEventsStatus(
            message: CalendarEventsCopy.loading,
            tone: .info
        )
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

            switch direction {
            case .forward:
                isExtendingForward = false
            case .backward:
                isExtendingBackward = false
            }
            guard attempt == connectionGeneration else {
                resumeAfterStaleFetch()
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
                let slabEvents = normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds
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
                recordFreshness(
                    for: (start: fetchStart, end: fetchEnd),
                    completedAt: cadenceScheduler.now
                )
                isSlabRetryBlocked = false
                clearStatusIfIdle()
                drainFetchWork()
                scheduleCadenceIfEligible()
            case .unavailable(let failure):
                status = switch failure {
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
                // Do not immediately retry the failed slab. A pending
                // foreground refresh may still run inside the fetched range.
                isSlabRetryBlocked = true
                drainFetchWork(allowSlab: false)
                scheduleCadenceIfEligible()
            }
        }
    }

    /// Replaces the complete Calendar Event snapshot around the latest visible
    /// dates after a final Selected Source Calendars change. The prior snapshot
    /// and Fetched Window stay intact until the complete aggregate succeeds.
    private func beginSelectionReplacement(
        adapter: any GoogleCalendarEventsAdapting
    ) {
        guard !isReplacingSelection,
              let visible = lastVisibleRange,
              let range = selectionReplacementRange(visible: visible)
        else {
            return
        }

        cancelCadence()
        isSelectionReplacementPending = false
        isReplacingSelection = true
        status = CalendarEventsStatus(
            message: CalendarEventsCopy.updatingSelection,
            tone: .info
        )
        let attempt = connectionGeneration
        let requestedSourceCalendars = sourceCalendars
        let sourceCalendarRecovery = sourceCalendarRecovery

        Task { [weak self] in
            let result = await Self.fetchEventsRecoveringSource(
                adapter: adapter,
                recovery: sourceCalendarRecovery,
                from: requestedSourceCalendars,
                start: range.start,
                end: range.end
            )
            guard let self else {
                return
            }
            isReplacingSelection = false
            guard attempt == connectionGeneration else {
                resumeAfterStaleFetch()
                return
            }
            sourceCalendars = result.sourceCalendars

            switch result.outcome {
            case .success(let events, let eventColorBackgrounds):
                fetchedWindow = range
                normalizedEvents = normalize(
                    events,
                    eventColorBackgrounds: eventColorBackgrounds
                )
                isPresentingStoredEvents = false
                writeStore()
                weekLayouts = [:]
                publishWeeks(covering: range)
                freshnessCoverage = []
                recordFreshness(
                    for: range,
                    completedAt: cadenceScheduler.now
                )
                refreshFailure = nil
                isSelectionReplacementPending = false
                reconcileSelectedEvent()
                reconcileSelectedDayEvents()
                clearStatusIfIdle()
                drainFetchWork()
                scheduleCadenceIfEligible()
            case .unavailable(let failure):
                // Keep the prior snapshot, Fetched Window, selected detail,
                // and freshness. The new durable selection remains desired.
                refreshFailure = failure
                isSelectionReplacementPending = true
                clearStatusIfIdle()
                scheduleCadenceIfEligible()
            }
        }
    }

    /// Three clamped calendar months around the latest visible Date Cells,
    /// clipped to the complete Week Rows of the Extended Calendar Range.
    private func selectionReplacementRange(
        visible: (start: Date, end: Date)
    ) -> (start: Date, end: Date)? {
        let calendar = environment.calendar
        guard
            let bufferedStart = addMonthsClamped(-3, to: visible.start),
            let bufferedLastDay = addMonthsClamped(3, to: visible.end),
            let bufferedEnd = calendar.date(
                byAdding: .day,
                value: 1,
                to: bufferedLastDay
            ),
            let extended = extendedCalendarRange()
        else {
            return nil
        }

        let start = max(calendar.startOfDay(for: bufferedStart), extended.start)
        let end = min(calendar.startOfDay(for: bufferedEnd), extended.end)
        return start < end ? (start, end) : nil
    }

    /// The half-open complete Week Rows from the week containing ten years
    /// before Today through the week containing ten years after Today.
    private func extendedCalendarRange() -> (start: Date, end: Date)? {
        let calendar = environment.calendar
        let today = calendar.startOfDay(for: environment.now)
        guard
            let firstDate = addYearsClamped(-10, to: today),
            let finalDate = addYearsClamped(10, to: today),
            let end = calendar.date(
                byAdding: .day,
                value: 7,
                to: startOfMondayWeek(containing: finalDate)
            )
        else {
            return nil
        }
        return (
            startOfMondayWeek(containing: firstDate),
            end
        )
    }

    // MARK: Freshness

    /// One successful request's half-open date coverage and completion time.
    private struct FreshnessCoverage {
        let start: Date
        let end: Date
        let completedAt: Date
    }

    /// The visible dates plus one month on each side, clipped to the Fetched
    /// Window. Both foreground and browsing refresh decisions use this one
    /// calculation so freshness can never authorize a different range from
    /// the request it suppresses or starts.
    private func boundedRefreshRange(
        window: (start: Date, end: Date),
        visible: (start: Date, end: Date)
    ) -> (start: Date, end: Date)? {
        guard
            let bufferedStart = addMonthsClamped(-1, to: visible.start),
            let bufferedEnd = addMonthsClamped(1, to: visible.end)
        else {
            return nil
        }

        let start = max(bufferedStart, window.start)
        let end = min(bufferedEnd, window.end)
        return start < end ? (start, end) : nil
    }

    /// Records only successful request completion. Coverage older than the
    /// freshness horizon can no longer satisfy a future query, so it is
    /// discarded as newer successes arrive to keep this memory-only list
    /// bounded during long foreground sessions.
    private func recordFreshness(
        for range: (start: Date, end: Date),
        completedAt: Date
    ) {
        let cutoff = completedAt.addingTimeInterval(
            -Self.refreshCadenceSeconds
        )
        freshnessCoverage.removeAll { coverage in
            coverage.completedAt < cutoff
                || (range.start <= coverage.start
                    && range.end >= coverage.end
                    && completedAt >= coverage.completedAt)
        }
        freshnessCoverage.append(
            FreshnessCoverage(
                start: range.start,
                end: range.end,
                completedAt: completedAt
            )
        )
    }

    /// Whether recent successful requests jointly cover every instant in a
    /// bounded refresh range. Overlapping initial, slab, and refresh ranges
    /// can form the coverage together; any gap makes the range stale.
    private func isFresh(
        _ range: (start: Date, end: Date),
        at now: Date
    ) -> Bool {
        let cutoff = now.addingTimeInterval(-Self.refreshCadenceSeconds)
        let eligible = freshnessCoverage
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
        for coverage in eligible {
            if coverage.start > coveredThrough {
                return false
            }
            coveredThrough = max(coveredThrough, coverage.end)
            if coveredThrough >= range.end {
                return true
            }
        }
        return false
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

        /// The canonical cross-calendar occurrence identity: one entry per
        /// occurrence across every Selected Source Calendar.
        let id: String
        /// The winning Source Calendar's identity and presentation
        /// attributes, kept intact from the winning copy.
        let sourceCalendar: GoogleSourceCalendar
        let title: String
        let colorHex: String
        let textTone: CalendarEventTextTone
        let kind: Kind
        /// The Event Detail Popover payload, built at normalization and
        /// projected only when this canonical event identity is selected
        /// (iOS ADR 0005).
        let detail: CalendarEventDetail
    }

    /// Applies Planner's product rules: cancelled and declined events drop
    /// out, duplicate copies of one canonical occurrence collapse to their
    /// deterministic winner — the Primary Source Calendar copy when
    /// present, otherwise the earliest in the deterministic Source
    /// Calendar order, kept intact with nothing combined across copies —
    /// blank titles become "Busy", all-day ends turn inclusive, and every
    /// event classifies as a bar or a row in the environment's local
    /// dates.
    private func normalize(
        _ events: [GoogleSourceCalendarEvent],
        eventColorBackgrounds: [String: String]
    ) -> [NormalizedEvent] {
        let calendar = environment.calendar
        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = environment.locale
        timeFormatter.timeZone = environment.timeZone
        timeFormatter.setLocalizedDateFormatFromTemplate("jm")
        let timingContext = CalendarEventTimingLine.Context(
            calendar: calendar,
            locale: environment.locale,
            timeZone: environment.timeZone
        )

        // Collapse duplicate copies of one canonical occurrence, keeping
        // first-appearance order of identities so layout stays
        // deterministic regardless of copy order.
        var identityOrder: [String] = []
        var winners: [String: GoogleSourceCalendarEvent] = [:]
        for sourceEvent in events {
            guard !sourceEvent.event.isCancelled,
                  !sourceEvent.event.isDeclinedByViewer
            else {
                continue
            }
            let identity = CalendarEventCanonicalIdentity.id(of: sourceEvent)
            if let current = winners[identity] {
                if SourceCalendarReconciliation.precedes(
                    sourceEvent.sourceCalendar,
                    current.sourceCalendar
                ) {
                    winners[identity] = sourceEvent
                }
            } else {
                winners[identity] = sourceEvent
                identityOrder.append(identity)
            }
        }

        return identityOrder.compactMap { identity in
            guard let sourceEvent = winners[identity] else {
                return nil
            }
            let sourceCalendar = sourceEvent.sourceCalendar
            let event = sourceEvent.event

            let title = event.summary?.trimmedToNil ?? "Busy"
            // The Event Color (Planning glossary): the explicit Google
            // event color when one is set and known, otherwise the Source
            // Calendar's background color.
            let colorHex = event.colorId
                .flatMap { eventColorBackgrounds[$0] }
                ?? sourceCalendar.backgroundColorHex
            let textTone = CalendarEventsModel.textTone(forHexColor: colorHex)

            // The Event Detail Popover's optional fields, mapped once so
            // every classification branch publishes the same omission
            // rules: blank locations and Google links are absent; HTML
            // notes render plain and blank out to absence.
            let location = event.location?.trimmedToNil
            let googleLink = event.googleLink?.trimmedToNil
            let notes = CalendarEventPlainTextNotes.plainText(
                fromHTML: event.notes
            )
            let attendees = CalendarEventAttendeeNormalization.normalize(
                event.attendees
            )

            let makeDetail = { (timing: CalendarEventTiming) in
                CalendarEventDetail(
                    title: title,
                    colorHex: colorHex,
                    timingText: CalendarEventTimingLine.timingLine(
                        for: timing,
                        context: timingContext
                    ),
                    location: location,
                    googleLink: googleLink,
                    notes: notes,
                    attendees: attendees.visible,
                    hiddenAttendeeCount: attendees.hiddenCount
                )
            }

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
                    id: identity,
                    sourceCalendar: sourceCalendar,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .bar(
                        startDate: startDate,
                        endDate: endDate,
                        startsAt: startDate
                    ),
                    detail: makeDetail(
                        CalendarEventTiming(
                            start: startDate,
                            end: endDate,
                            isAllDay: true,
                            isMultiday: endDate > startDate
                        )
                    )
                )
            case (.timed(let startsAt), .timed(let endsAt)):
                let startDate = calendar.startOfDay(for: startsAt)
                let endDate = calendar.startOfDay(for: endsAt)
                if endDate > startDate {
                    return NormalizedEvent(
                        id: identity,
                        sourceCalendar: sourceCalendar,
                        title: title,
                        colorHex: colorHex,
                        textTone: textTone,
                        kind: .bar(
                            startDate: startDate,
                            endDate: endDate,
                            startsAt: startsAt
                        ),
                        detail: makeDetail(
                            CalendarEventTiming(
                                start: startsAt,
                                end: endsAt,
                                isAllDay: false,
                                isMultiday: true
                            )
                        )
                    )
                }
                return NormalizedEvent(
                    id: identity,
                    sourceCalendar: sourceCalendar,
                    title: title,
                    colorHex: colorHex,
                    textTone: textTone,
                    kind: .row(
                        date: startDate,
                        startsAt: startsAt,
                        startTimeText: timeFormatter.string(from: startsAt)
                    ),
                    detail: makeDetail(
                        CalendarEventTiming(
                            start: startsAt,
                            end: endsAt,
                            isAllDay: false,
                            isMultiday: false
                        )
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
        _ events: [NormalizedEvent],
        weekStart: Date
    ) -> [CalendarEventBarSegment] {
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

    private func addYearsClamped(_ amount: Int, to date: Date) -> Date? {
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
        firstOfTargetMonth.year = year + amount
        firstOfTargetMonth.month = month
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

    /// Foreground Calendar Event Refresh waits five minutes after the prior
    /// serialized Calendar Event request attempt completes.
    private static let refreshCadenceSeconds: TimeInterval = 5 * 60
    private static let refreshCadence: Duration = .seconds(
        refreshCadenceSeconds
    )

    /// The readable text tone on an Event Color: whichever of Planner's
    /// ink or white has the stronger APCA lightness contrast against it.
    /// APCA — the W3C's perceptually calibrated WCAG 3 candidate — ranks
    /// pairings the way the eye reads them; the WCAG 2.x ratio it
    /// replaces overvalued dark text on mid-dark saturated colors,
    /// rendering barely readable ink on Google's blues (iOS ADR 0004).
    static func textTone(forHexColor hexColor: String) -> CalendarEventTextTone {
        guard let color = EventColorRGB(hex: hexColor) else {
            return .light
        }
        let luminance = color.relativeLuminance
        let darkLc = apcaContrast(
            textLuminance: darkTextRelativeLuminance,
            backgroundLuminance: luminance
        )
        let lightLc = apcaContrast(
            textLuminance: 1.0,
            backgroundLuminance: luminance
        )
        return abs(darkLc) >= abs(lightLc) ? .dark : .light
    }

    /// The APCA lightness contrast (Lc) of a text color on a background,
    /// from their WCAG relative luminances: positive for dark text on a
    /// light ground, negative for light text on a dark ground, with
    /// polarity-dependent exponents modeling how the eye reads each
    /// pairing; a pairing too weak to read clips to zero. Constants are
    /// the published apca-w3 ones.
    private static func apcaContrast(
        textLuminance: Double,
        backgroundLuminance: Double
    ) -> Double {
        let blackThreshold = 0.022
        let text = textLuminance > blackThreshold
            ? textLuminance
            : textLuminance + pow(blackThreshold - textLuminance, 1.414)
        let background = backgroundLuminance > blackThreshold
            ? backgroundLuminance
            : backgroundLuminance + pow(blackThreshold - backgroundLuminance, 1.414)
        guard abs(background - text) >= 0.0005 else {
            return 0
        }
        if background > text {
            let contrast = pow(background, 0.56) - pow(text, 0.57)
            return contrast < 0.1 ? 0 : contrast * 1.14 * 100
        }
        let contrast = pow(background, 0.62) - pow(text, 0.65)
        return contrast > -0.1 ? 0 : contrast * 1.14 * 100
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

private extension String {
    /// Trims an optional Google string at the model seam, returning
    /// `nil` when nothing but whitespace remains — the shared
    /// blank-means-absent rule for titles and optional detail fields.
    var trimmedToNil: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension CalendarEventsModel {
    /// Maps one in-memory normalized event to its Stored Calendar Event
    /// record: the full normalized Calendar Event model exactly as the
    /// surface renders it — never a raw Google payload (iOS ADR 0007).
    private static func storedEvent(
        from event: NormalizedEvent
    ) -> StoredCalendarEvent {
        let kind: StoredCalendarEvent.Kind
        switch event.kind {
        case .bar(let startDate, let endDate, let startsAt):
            kind = .bar(
                startDate: startDate,
                endDate: endDate,
                startsAt: startsAt
            )
        case .row(let date, let startsAt, let startTimeText):
            kind = .row(
                date: date,
                startsAt: startsAt,
                startTimeText: startTimeText
            )
        }
        return StoredCalendarEvent(
            id: event.id,
            sourceCalendar: event.sourceCalendar,
            title: event.title,
            colorHex: event.colorHex,
            textTone: event.textTone,
            kind: kind,
            detail: event.detail
        )
    }

    /// Maps one Stored Calendar Event record back to the in-memory
    /// normalized model for launch presentation.
    private static func normalizedEvent(
        from stored: StoredCalendarEvent
    ) -> NormalizedEvent {
        let kind: NormalizedEvent.Kind
        switch stored.kind {
        case .bar(let startDate, let endDate, let startsAt):
            kind = .bar(
                startDate: startDate,
                endDate: endDate,
                startsAt: startsAt
            )
        case .row(let date, let startsAt, let startTimeText):
            kind = .row(
                date: date,
                startsAt: startsAt,
                startTimeText: startTimeText
            )
        }
        return NormalizedEvent(
            id: stored.id,
            sourceCalendar: stored.sourceCalendar,
            title: stored.title,
            colorHex: stored.colorHex,
            textTone: stored.textTone,
            kind: kind,
            detail: stored.detail
        )
    }
}
