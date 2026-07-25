import Foundation
import Observation

/// Planner-relevant Source Calendar loading failures. Raw Google failures
/// never cross this boundary.
enum GoogleSourceCalendarsFailure: Equatable, Sendable {
    case offline
    case failed
}

/// The complete readable Source Calendars returned by Google.
enum GoogleSourceCalendarsOutcome: Equatable, Sendable {
    case success([GoogleSourceCalendar])
    case unavailable(GoogleSourceCalendarsFailure)
}

/// The product-oriented boundary for loading live Source Calendars.
@MainActor
protocol GoogleSourceCalendarsAdapting {
    func fetchSourceCalendars() async -> GoogleSourceCalendarsOutcome
}

/// Receives the account that may begin Calendar-data behavior after the
/// current disclosure has been acknowledged. `nil` suspends all such work.
@MainActor
protocol CalendarDataAccountConsuming: AnyObject {
    func setCalendarDataAccountID(_ accountID: String?)
}

/// Receives the reconciled Selected Source Calendars. `nil` means Calendar
/// data is suspended or disconnected; an empty array is the valid no-source
/// exception.
@MainActor
protocol SelectedSourceCalendarsConsuming: AnyObject {
    func setSelectedSourceCalendars(_ sourceCalendars: [GoogleSourceCalendar]?)
    func sourceCalendarPickerDidOpen()
    func sourceCalendarPickerDidClose(
        selectedSourceCalendars: [GoogleSourceCalendar],
        selectionChanged: Bool
    )
}

/// The compact iOS Source Calendar Control presentation. A suspended account
/// has no control; a disclosure-released account keeps a stable control
/// footprint through loading, failure, and ready states. The control
/// indicates and disables only during the initial Source Calendar load:
/// after any completed attempt it is usable, so a failure or the zero-source
/// exception can still open the picker's recovery state.
enum SourceCalendarControlPresentation: Equatable, Sendable {
    case hidden
    case loading
    case ready(selectedCount: Int)
}

enum SourceCalendarToggleOutcome: Equatable, Sendable {
    case changed
    case minimumRequired
    case unavailable
}

/// The native picker's content state: opening-refresh progress, a
/// recoverable Planner-owned failure with an explicit Retry, or the ready
/// list. A failure never discards the prior selection.
enum SourceCalendarPickerContent: Equatable, Sendable {
    case loading
    case unavailable(GoogleSourceCalendarsFailure)
    case ready
}

/// Handles a selected source's forbidden or not-found event failure with
/// one live Source Calendar reload and reconciliation.
@MainActor
protocol SourceCalendarRecoveryHandling: AnyObject {
    /// Reloads live Source Calendars, reconciles against the confirmed
    /// result, persists it immediately, and returns the effective Selected
    /// Source Calendars for one aggregate event retry. `nil` means the
    /// reload itself failed: the durable selection remains and the caller
    /// reports the fetch failure.
    func reconcileSelectionAfterSourceFailure() async
        -> [GoogleSourceCalendar]?
}

struct SourceCalendarsStatus: Equatable, Sendable {
    let message: String?
    let tone: Tone

    enum Tone: Equatable, Sendable {
        case info
        case warning
        case error
    }
}

enum SourceCalendarsCopy {
    static let loading = "Loading calendars…"
    static let offline = "You’re offline. Calendars will load when online"
    static let failed = "Couldn’t load calendars. Try again"
    static let minimumSelection = "Select at least one calendar"
    static let retry = "Retry"
    static let noAvailable = "No calendars available"
}

/// Pure, deterministic Source Calendar ordering and reconciliation.
enum SourceCalendarReconciliation {
    static func ordered(
        _ sourceCalendars: [GoogleSourceCalendar]
    ) -> [GoogleSourceCalendar] {
        var seen = Set<String>()
        return sourceCalendars
            .filter {
                !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted(by: precedes)
            .filter { seen.insert($0.id).inserted }
    }

    static func reconcile(
        available sourceCalendars: [GoogleSourceCalendar],
        storedIDs: [String]?
    ) -> [GoogleSourceCalendar] {
        let available = ordered(sourceCalendars)
        guard !available.isEmpty else {
            return []
        }

        let stored = Set(storedIDs ?? [])
        let survivors = available.filter { stored.contains($0.id) }
        return survivors.isEmpty ? [available[0]] : survivors
    }

    private static func precedes(
        _ lhs: GoogleSourceCalendar,
        _ rhs: GoogleSourceCalendar
    ) -> Bool {
        if lhs.isPrimary != rhs.isPrimary {
            return lhs.isPrimary
        }

        let locale = Locale(identifier: "en_US_POSIX")
        let lhsFolded = lhs.summary.folding(
            options: [.caseInsensitive],
            locale: locale
        )
        let rhsFolded = rhs.summary.folding(
            options: [.caseInsensitive],
            locale: locale
        )
        if lhsFolded != rhsFolded {
            return lhsFolded < rhsFolded
        }
        if lhs.summary != rhs.summary {
            return lhs.summary < rhs.summary
        }
        return lhs.id < rhs.id
    }
}

/// Owns live Source Calendars, per-account persisted IDs, reconciliation,
/// and the effective selection supplied to Calendar Events. No Source
/// Calendar presentation data is persisted.
@MainActor
@Observable
final class SourceCalendarsModel: CalendarDataAccountConsuming {
    private(set) var availableSourceCalendars: [GoogleSourceCalendar] = []
    private(set) var selectedSourceCalendars: [GoogleSourceCalendar] = []
    private(set) var status = SourceCalendarsStatus(message: nil, tone: .info)
    private(set) var controlPresentation: SourceCalendarControlPresentation = .hidden
    private(set) var isPickerPresented = false
    private(set) var pickerContent: SourceCalendarPickerContent = .ready
    private(set) var minimumSelectionMessage: String?

    @ObservationIgnored
    private let adapter: (any GoogleSourceCalendarsAdapting)?
    @ObservationIgnored
    private let store: any SelectedSourceCalendarsStoring
    @ObservationIgnored
    private weak var selectionConsumer: (any SelectedSourceCalendarsConsuming)?
    @ObservationIgnored
    private let connectivityMonitor:
        (any GoogleConnectionConnectivityMonitoring)?
    @ObservationIgnored
    private var accountID: String?
    @ObservationIgnored
    private var requestGeneration = 0
    @ObservationIgnored
    private var isLoading = false
    @ObservationIgnored
    private var owesConnectivityRetry = false
    /// Whether the account's initial load has only failed so far, so a
    /// republished connection (foreground validation) retries it. Successful
    /// loads — including the zero-source exception — never auto-retry.
    @ObservationIgnored
    private var lastAccountLoadFailed = false
    @ObservationIgnored
    private var openingSelectionIDs: [String]?

    init(
        adapter: (any GoogleSourceCalendarsAdapting)?,
        store: any SelectedSourceCalendarsStoring,
        selectionConsumer: (any SelectedSourceCalendarsConsuming)?,
        connectivityMonitor:
            (any GoogleConnectionConnectivityMonitoring)? = nil
    ) {
        self.adapter = adapter
        self.store = store
        self.selectionConsumer = selectionConsumer
        self.connectivityMonitor = connectivityMonitor
        connectivityMonitor?.start { [weak self] in
            self?.handleConnectivityReturn()
        }
    }

    isolated deinit {
        connectivityMonitor?.stop()
    }

    func setCalendarDataAccountID(_ accountID: String?) {
        if accountID == self.accountID {
            // Foreground connection validation republishes the same account.
            // A prior list failure may retry then; successful and in-flight
            // states remain no-ops. While the picker is presented the retry
            // refreshes the picker's own state instead of the control's.
            if let accountID, lastAccountLoadFailed, let adapter {
                load(
                    accountID: accountID,
                    adapter: adapter,
                    purpose: isPickerPresented ? .picker : .account
                )
            }
            return
        }

        requestGeneration += 1
        self.accountID = accountID
        isLoading = false
        owesConnectivityRetry = false
        lastAccountLoadFailed = false
        availableSourceCalendars = []
        selectedSourceCalendars = []
        status = SourceCalendarsStatus(message: nil, tone: .info)
        controlPresentation = .hidden
        isPickerPresented = false
        pickerContent = .ready
        minimumSelectionMessage = nil
        openingSelectionIDs = nil
        selectionConsumer?.setSelectedSourceCalendars(nil)

        guard let accountID, let adapter else {
            return
        }
        load(accountID: accountID, adapter: adapter, purpose: .account)
    }

    /// Opens the native picker from the usable post-initial-load state and
    /// requests complete live Source Calendars — including as an automatic
    /// retry after an earlier failure, so sources created, deleted, hidden,
    /// or made unreadable since connection appear through reopening.
    func presentPicker() {
        guard case .ready = controlPresentation,
              !isPickerPresented
        else {
            return
        }
        openingSelectionIDs = selectedSourceCalendars.map(\.id)
        minimumSelectionMessage = nil
        isPickerPresented = true
        selectionConsumer?.sourceCalendarPickerDidOpen()
        beginPickerLoad()
    }

    /// Retries the picker's failed live Source Calendar request without
    /// discarding the prior selection.
    func retryPickerLoad() {
        guard isPickerPresented,
              case .unavailable = pickerContent
        else {
            return
        }
        beginPickerLoad()
    }

    /// Applies Done and every native dismissal path identically. Toggles have
    /// already persisted; dismissal publishes one final selection decision to
    /// Calendar Events so no request is issued per tap. An opening request
    /// still in flight is invalidated: its late result performs no
    /// reconciliation, persistence, or event refresh.
    func dismissPicker() {
        guard isPickerPresented, let openingSelectionIDs else {
            return
        }
        let finalSelection = selectedSourceCalendars
        let changed = finalSelection.map(\.id) != openingSelectionIDs
        isPickerPresented = false
        pickerContent = .ready
        minimumSelectionMessage = nil
        self.openingSelectionIDs = nil
        // Only picker-purpose loads can be in flight while the picker is
        // presented; the generation bump discards their late completions.
        requestGeneration += 1
        isLoading = false
        selectionConsumer?.sourceCalendarPickerDidClose(
            selectedSourceCalendars: finalSelection,
            selectionChanged: changed
        )
    }

    /// Immediately persists one user toggle while enforcing the minimum-one
    /// invariant. Calendar Event replacement remains deferred until dismissal.
    @discardableResult
    func toggleSourceCalendar(id: String) -> SourceCalendarToggleOutcome {
        guard isPickerPresented,
              let accountID,
              availableSourceCalendars.contains(where: { $0.id == id })
        else {
            return .unavailable
        }

        let selectedIDs = Set(selectedSourceCalendars.map(\.id))
        if selectedIDs.contains(id), selectedIDs.count == 1 {
            minimumSelectionMessage = SourceCalendarsCopy.minimumSelection
            return .minimumRequired
        }

        var nextIDs = selectedIDs
        if !nextIDs.insert(id).inserted {
            nextIDs.remove(id)
        }
        let nextSelection = availableSourceCalendars.filter {
            nextIDs.contains($0.id)
        }
        store.saveSelectedSourceCalendarIDs(
            nextSelection.map(\.id),
            for: accountID
        )
        selectedSourceCalendars = nextSelection
        minimumSelectionMessage = nil
        controlPresentation = .ready(selectedCount: nextSelection.count)
        return .changed
    }

    /// Why a live Source Calendar request runs. Account loads are the
    /// initial load and its retries: they own the control's disabled,
    /// progress-indicating presentation and publish every successful result
    /// — including the zero-source exception — straight to Calendar Events.
    /// Picker loads refresh the presented picker and publish only the
    /// zero-source exception immediately; any other reconciled change is
    /// published once by dismissal.
    private enum LoadPurpose {
        case account
        case picker
    }

    private func beginPickerLoad() {
        guard let accountID, let adapter else {
            pickerContent = .ready
            return
        }
        load(accountID: accountID, adapter: adapter, purpose: .picker)
    }

    private func load(
        accountID: String,
        adapter: any GoogleSourceCalendarsAdapting,
        purpose: LoadPurpose
    ) {
        guard !isLoading else {
            return
        }
        isLoading = true
        owesConnectivityRetry = false
        requestGeneration += 1
        let attempt = requestGeneration
        switch purpose {
        case .account:
            status = SourceCalendarsStatus(
                message: SourceCalendarsCopy.loading,
                tone: .info
            )
            controlPresentation = .loading
        case .picker:
            pickerContent = .loading
        }

        Task { [weak self] in
            let outcome = await adapter.fetchSourceCalendars()
            guard let self,
                  attempt == requestGeneration,
                  self.accountID == accountID
            else {
                return
            }

            isLoading = false
            switch purpose {
            case .account:
                handleAccountOutcome(outcome, accountID: accountID)
            case .picker:
                // Dismissal invalidates the attempt through the generation
                // bump; this guard documents that a late picker result
                // performs no reconciliation, persistence, or event work.
                guard isPickerPresented else {
                    return
                }
                handlePickerOutcome(outcome, accountID: accountID)
            }
        }
    }

    private func handleAccountOutcome(
        _ outcome: GoogleSourceCalendarsOutcome,
        accountID: String
    ) {
        switch outcome {
        case .success(let sourceCalendars):
            lastAccountLoadFailed = false
            applyLoadedSourceCalendars(sourceCalendars, accountID: accountID)
            // Publication order is privacy-significant: only a successful
            // post-disclosure list load may persist selection and start
            // Calendar Event loading.
            selectionConsumer?.setSelectedSourceCalendars(
                selectedSourceCalendars
            )
        case .unavailable(let failure):
            publishLoadFailure(failure)
        }
    }

    private func handlePickerOutcome(
        _ outcome: GoogleSourceCalendarsOutcome,
        accountID: String
    ) {
        switch outcome {
        case .success(let sourceCalendars):
            lastAccountLoadFailed = false
            applyLoadedSourceCalendars(sourceCalendars, accountID: accountID)
            pickerContent = .ready
            if selectedSourceCalendars.isEmpty {
                // The zero-source exception clears Calendar Events, Fetched
                // Window, selected Event Detail, and freshness atomically
                // through the consumer, without an event request.
                selectionConsumer?.setSelectedSourceCalendars([])
            }
        case .unavailable(let failure):
            publishLoadFailure(failure)
            pickerContent = .unavailable(failure)
        }
    }

    /// A failed request performs no reconciliation, persistence change,
    /// event request, Fetched Window change, or freshness change. The prior
    /// selection remains and the control stays usable so the picker can
    /// expose recovery.
    private func publishLoadFailure(_ failure: GoogleSourceCalendarsFailure) {
        lastAccountLoadFailed = true
        switch failure {
        case .offline:
            owesConnectivityRetry = true
            status = SourceCalendarsStatus(
                message: SourceCalendarsCopy.offline,
                tone: .warning
            )
        case .failed:
            status = SourceCalendarsStatus(
                message: SourceCalendarsCopy.failed,
                tone: .error
            )
        }
        controlPresentation = .ready(
            selectedCount: selectedSourceCalendars.count
        )
    }

    /// The shared success core: reconcile the stored IDs against the
    /// complete live Source Calendars, silently removing unavailable
    /// selections, preserving survivors, defaulting when none survive, and
    /// persisting the result immediately. The zero-source success is the
    /// sole empty-selection exception and presents its distinct state.
    private func applyLoadedSourceCalendars(
        _ sourceCalendars: [GoogleSourceCalendar],
        accountID: String
    ) {
        let available = SourceCalendarReconciliation.ordered(sourceCalendars)
        let selected = SourceCalendarReconciliation.reconcile(
            available: available,
            storedIDs: store.selectedSourceCalendarIDs(for: accountID)
        )
        store.saveSelectedSourceCalendarIDs(
            selected.map(\.id),
            for: accountID
        )
        availableSourceCalendars = available
        selectedSourceCalendars = selected
        status = selected.isEmpty
            ? SourceCalendarsStatus(
                message: SourceCalendarsCopy.noAvailable,
                tone: .error
            )
            : SourceCalendarsStatus(message: nil, tone: .info)
        controlPresentation = .ready(selectedCount: selected.count)
    }

    private func handleConnectivityReturn() {
        guard owesConnectivityRetry,
              let accountID,
              let adapter
        else {
            return
        }
        load(
            accountID: accountID,
            adapter: adapter,
            purpose: isPickerPresented ? .picker : .account
        )
    }
}

extension SourceCalendarsModel: SourceCalendarRecoveryHandling {
    /// One live reload after a selected source returned forbidden or
    /// not-found. A selection is removed only when the live response
    /// confirms it is unavailable; a failed reload changes nothing and
    /// returns `nil` so the caller reports the fetch failure. A confirmed
    /// non-empty result is returned to the caller for its one aggregate
    /// retry rather than published, so the retry replaces events
    /// atomically; the zero-source exception publishes its atomic clear.
    func reconcileSelectionAfterSourceFailure() async
        -> [GoogleSourceCalendar]?
    {
        guard let accountID, let adapter else {
            return nil
        }
        let outcome = await adapter.fetchSourceCalendars()
        // A newer account decision (Disconnect on This Device, expiration,
        // or another account) discards the late reload.
        guard accountID == self.accountID else {
            return nil
        }

        switch outcome {
        case .success(let sourceCalendars):
            lastAccountLoadFailed = false
            applyLoadedSourceCalendars(sourceCalendars, accountID: accountID)
            if selectedSourceCalendars.isEmpty {
                selectionConsumer?.setSelectedSourceCalendars([])
            }
            return selectedSourceCalendars
        case .unavailable:
            return nil
        }
    }
}
