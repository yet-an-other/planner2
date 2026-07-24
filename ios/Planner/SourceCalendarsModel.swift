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
/// footprint through loading, failure, and ready states.
enum SourceCalendarControlPresentation: Equatable, Sendable {
    case hidden
    case loading
    case disabled
    case ready(selectedCount: Int)
}

enum SourceCalendarToggleOutcome: Equatable, Sendable {
    case changed
    case minimumRequired
    case unavailable
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
            // A prior generic list failure may retry then; successful and
            // in-flight states remain no-ops.
            if let accountID, status.message != nil, let adapter {
                load(accountID: accountID, adapter: adapter)
            }
            return
        }

        requestGeneration += 1
        self.accountID = accountID
        isLoading = false
        owesConnectivityRetry = false
        availableSourceCalendars = []
        selectedSourceCalendars = []
        status = SourceCalendarsStatus(message: nil, tone: .info)
        controlPresentation = .hidden
        isPickerPresented = false
        minimumSelectionMessage = nil
        openingSelectionIDs = nil
        selectionConsumer?.setSelectedSourceCalendars(nil)

        guard let accountID, let adapter else {
            return
        }
        load(accountID: accountID, adapter: adapter)
    }

    /// Opens the native picker from the disclosure-released ready state.
    /// Live Source Calendar refresh on opening belongs to the recovery slice.
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
    }

    /// Applies Done and every native dismissal path identically. Toggles have
    /// already persisted; dismissal publishes one final selection decision to
    /// Calendar Events so no request is issued per tap.
    func dismissPicker() {
        guard isPickerPresented, let openingSelectionIDs else {
            return
        }
        let finalSelection = selectedSourceCalendars
        let changed = finalSelection.map(\.id) != openingSelectionIDs
        isPickerPresented = false
        minimumSelectionMessage = nil
        self.openingSelectionIDs = nil
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

    private func load(
        accountID: String,
        adapter: any GoogleSourceCalendarsAdapting
    ) {
        guard !isLoading else {
            return
        }
        isLoading = true
        owesConnectivityRetry = false
        requestGeneration += 1
        let attempt = requestGeneration
        status = SourceCalendarsStatus(
            message: SourceCalendarsCopy.loading,
            tone: .info
        )
        controlPresentation = .loading

        Task { [weak self] in
            let outcome = await adapter.fetchSourceCalendars()
            guard let self,
                  attempt == requestGeneration,
                  self.accountID == accountID
            else {
                return
            }

            isLoading = false
            switch outcome {
            case .success(let sourceCalendars):
                let available = SourceCalendarReconciliation.ordered(
                    sourceCalendars
                )
                let selected = SourceCalendarReconciliation.reconcile(
                    available: available,
                    storedIDs: store.selectedSourceCalendarIDs(
                        for: accountID
                    )
                )
                let selectedIDs = selected.map(\.id)

                // Publication order is privacy-significant: only a successful
                // post-disclosure list load may persist selection and start
                // Calendar Event loading.
                store.saveSelectedSourceCalendarIDs(
                    selectedIDs,
                    for: accountID
                )
                availableSourceCalendars = available
                selectedSourceCalendars = selected
                status = SourceCalendarsStatus(message: nil, tone: .info)
                controlPresentation = selected.isEmpty
                    ? .disabled
                    : .ready(selectedCount: selected.count)
                selectionConsumer?.setSelectedSourceCalendars(selected)
            case .unavailable(.offline):
                owesConnectivityRetry = true
                status = SourceCalendarsStatus(
                    message: SourceCalendarsCopy.offline,
                    tone: .warning
                )
                controlPresentation = .disabled
            case .unavailable(.failed):
                status = SourceCalendarsStatus(
                    message: SourceCalendarsCopy.failed,
                    tone: .error
                )
                controlPresentation = .disabled
            }
        }
    }

    private func handleConnectivityReturn() {
        guard owesConnectivityRetry,
              let accountID,
              let adapter
        else {
            return
        }
        load(accountID: accountID, adapter: adapter)
    }
}
