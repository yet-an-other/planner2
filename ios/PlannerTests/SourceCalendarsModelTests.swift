import Foundation
import Testing
@testable import Planner

@MainActor
private final class FakeSourceCalendarsAdapter: GoogleSourceCalendarsAdapting {
    var callCount = 0
    var handler: () async -> GoogleSourceCalendarsOutcome = { .success([]) }

    func fetchSourceCalendars() async -> GoogleSourceCalendarsOutcome {
        callCount += 1
        return await handler()
    }
}

@MainActor
private final class RecordingSelectionConsumer: SelectedSourceCalendarsConsuming {
    private(set) var selections: [[GoogleSourceCalendar]?] = []
    private(set) var pickerOpenCallCount = 0
    private(set) var pickerClosures: [([GoogleSourceCalendar], Bool)] = []
    var onSelection: (([GoogleSourceCalendar]?) -> Void)?

    func setSelectedSourceCalendars(
        _ sourceCalendars: [GoogleSourceCalendar]?
    ) {
        selections.append(sourceCalendars)
        onSelection?(sourceCalendars)
    }

    func sourceCalendarPickerDidOpen() {
        pickerOpenCallCount += 1
    }

    func sourceCalendarPickerDidClose(
        selectedSourceCalendars: [GoogleSourceCalendar],
        selectionChanged: Bool
    ) {
        pickerClosures.append((selectedSourceCalendars, selectionChanged))
    }
}

private final class RecordingSelectedSourceCalendarsStore:
    SelectedSourceCalendarsStoring
{
    var values: [String: [String]] = [:]
    var saveCallCount = 0
    var onSave: ((String, [String]) -> Void)?

    func selectedSourceCalendarIDs(for accountID: String) -> [String]? {
        values[accountID]
    }

    func saveSelectedSourceCalendarIDs(
        _ calendarIDs: [String],
        for accountID: String
    ) {
        saveCallCount += 1
        values[accountID] = calendarIDs
        onSave?(accountID, calendarIDs)
    }

    func clearAllSelectedSourceCalendars() {
        values = [:]
    }
}

private final class FakeSourceCalendarsConnectivityMonitor:
    GoogleConnectionConnectivityMonitoring
{
    private var onConnectivityReturn: (@MainActor () -> Void)?

    func start(onConnectivityReturn: @escaping @MainActor () -> Void) {
        self.onConnectivityReturn = onConnectivityReturn
    }

    func stop() {
        onConnectivityReturn = nil
    }

    @MainActor
    func simulateConnectivityReturn() {
        onConnectivityReturn?()
    }
}

@Suite("Source Calendars Model")
@MainActor
struct SourceCalendarsModelTests {
    private static let primary = GoogleSourceCalendar(
        id: "primary",
        summary: "Personal",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    )
    private static let family = GoogleSourceCalendar(
        id: "family",
        summary: "Family",
        backgroundColorHex: "#7CB342",
        isPrimary: false
    )
    private static let work = GoogleSourceCalendar(
        id: "work",
        summary: "work",
        backgroundColorHex: "#7986CB",
        isPrimary: false
    )

    @Test("Reconciliation orders Primary first and defaults to it")
    func primaryDefault() {
        let selected = SourceCalendarReconciliation.reconcile(
            available: [Self.work, Self.family, Self.primary],
            storedIDs: nil
        )

        #expect(selected == [Self.primary])
        #expect(
            SourceCalendarReconciliation.ordered(
                [Self.work, Self.primary, Self.family]
            ) == [Self.primary, Self.family, Self.work]
        )
    }

    @Test("Without a Primary marker the first deterministic source wins")
    func deterministicFallback() {
        let selected = SourceCalendarReconciliation.reconcile(
            available: [Self.work, Self.family],
            storedIDs: nil
        )

        #expect(selected == [Self.family])
    }

    @Test("Reconciliation preserves survivors and removes unavailable IDs")
    func survivors() {
        let selected = SourceCalendarReconciliation.reconcile(
            available: [Self.work, Self.family, Self.primary],
            storedIDs: ["missing", "work", "family"]
        )

        #expect(selected == [Self.family, Self.work])
    }

    @Test("An empty available list is the only empty selection")
    func emptyAvailable() {
        #expect(
            SourceCalendarReconciliation.reconcile(
                available: [],
                storedIDs: ["primary"]
            ).isEmpty
        )
    }

    @Test("Successful loading persists before publishing the selection")
    func successfulLoadOrdering() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = {
            .success([Self.work, Self.primary, Self.family])
        }
        let store = RecordingSelectedSourceCalendarsStore()
        let consumer = RecordingSelectionConsumer()
        var operations: [String] = []
        store.onSave = { _, ids in
            operations.append("save:\(ids.joined(separator: ","))")
        }
        consumer.onSelection = { selection in
            guard let selection else {
                operations.append("suspend")
                return
            }
            operations.append(
                "publish:\(selection.map(\.id).joined(separator: ","))"
            )
        }
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")

        #expect(await eventually { model.status.message == nil })
        #expect(store.values["account-a"] == ["primary"])
        #expect(model.selectedSourceCalendars == [Self.primary])
        #expect(operations == ["suspend", "save:primary", "publish:primary"])
    }

    @Test("Stored per-account selection is reconciled and restored")
    func storedSelection() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = { .success([Self.primary, Self.family, Self.work]) }
        let store = RecordingSelectedSourceCalendarsStore()
        store.values["account-a"] = ["work", "missing", "family"]
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")

        #expect(
            await eventually {
                model.selectedSourceCalendars == [Self.family, Self.work]
            }
        )
        #expect(store.values["account-a"] == ["family", "work"])
        #expect(consumer.selections.last! == [Self.family, Self.work])
    }

    @Test("A failed load performs no persistence or event publication")
    func failedLoad() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = { .unavailable(.failed) }
        let store = RecordingSelectedSourceCalendarsStore()
        store.values["account-a"] = ["family"]
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")

        #expect(
            await eventually {
                model.status.message == SourceCalendarsCopy.failed
            }
        )
        #expect(store.saveCallCount == 0)
        #expect(consumer.selections == [nil])
        #expect(store.values["account-a"] == ["family"])
    }

    @Test("An offline list failure retries when connectivity returns")
    func connectivityRetry() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = {
            adapter.callCount == 1
                ? .unavailable(.offline)
                : .success([Self.primary])
        }
        let monitor = FakeSourceCalendarsConnectivityMonitor()
        let store = RecordingSelectedSourceCalendarsStore()
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer,
            connectivityMonitor: monitor
        )

        model.setCalendarDataAccountID("account-a")
        #expect(
            await eventually {
                model.status.message == SourceCalendarsCopy.offline
            }
        )

        monitor.simulateConnectivityReturn()

        #expect(
            await eventually {
                adapter.callCount == 2
                    && model.selectedSourceCalendars == [Self.primary]
            }
        )
        #expect(store.values["account-a"] == ["primary"])
    }

    @Test("Disconnect invalidates a late list result before persistence")
    func staleCompletion() async {
        let adapter = FakeSourceCalendarsAdapter()
        var release: CheckedContinuation<GoogleSourceCalendarsOutcome, Never>?
        adapter.handler = {
            await withCheckedContinuation { release = $0 }
        }
        let store = RecordingSelectedSourceCalendarsStore()
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")
        #expect(await eventually { release != nil })
        model.setCalendarDataAccountID(nil)
        release?.resume(returning: .success([Self.primary]))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(store.saveCallCount == 0)
        #expect(model.selectedSourceCalendars.isEmpty)
        #expect(consumer.selections.last! == nil)
    }

    @Test("Picker toggles persist immediately and dismissal publishes once")
    func pickerToggleAndDismissal() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = { .success([Self.work, Self.primary, Self.family]) }
        let store = RecordingSelectedSourceCalendarsStore()
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")
        #expect(
            await eventually {
                model.controlPresentation == .ready(selectedCount: 1)
            }
        )

        model.presentPicker()
        #expect(model.isPickerPresented)
        #expect(consumer.pickerOpenCallCount == 1)

        #expect(model.toggleSourceCalendar(id: "work") == .changed)
        #expect(model.selectedSourceCalendars == [Self.primary, Self.work])
        #expect(store.values["account-a"] == ["primary", "work"])
        #expect(consumer.pickerClosures.isEmpty)

        model.dismissPicker()
        model.dismissPicker()
        #expect(consumer.pickerClosures.count == 1)
        #expect(consumer.pickerClosures.last?.0 == [Self.primary, Self.work])
        #expect(consumer.pickerClosures.last?.1 == true)
    }

    @Test("The final selected Source Calendar cannot be deselected")
    func minimumOne() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = { .success([Self.primary, Self.family]) }
        let store = RecordingSelectedSourceCalendarsStore()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: nil
        )

        model.setCalendarDataAccountID("account-a")
        #expect(await eventually { model.selectedSourceCalendars == [Self.primary] })
        let writesAfterLoad = store.saveCallCount
        model.presentPicker()

        #expect(
            model.toggleSourceCalendar(id: "primary") == .minimumRequired
        )
        #expect(model.selectedSourceCalendars == [Self.primary])
        #expect(store.saveCallCount == writesAfterLoad)
        #expect(
            model.minimumSelectionMessage
                == SourceCalendarsCopy.minimumSelection
        )
    }

    @Test("Returning to the opening selection dismisses without replacement")
    func unchangedFinalSelection() async {
        let adapter = FakeSourceCalendarsAdapter()
        adapter.handler = { .success([Self.primary, Self.family]) }
        let store = RecordingSelectedSourceCalendarsStore()
        let consumer = RecordingSelectionConsumer()
        let model = SourceCalendarsModel(
            adapter: adapter,
            store: store,
            selectionConsumer: consumer
        )

        model.setCalendarDataAccountID("account-a")
        #expect(await eventually { model.selectedSourceCalendars == [Self.primary] })
        model.presentPicker()
        _ = model.toggleSourceCalendar(id: "family")
        _ = model.toggleSourceCalendar(id: "family")
        model.dismissPicker()

        #expect(consumer.pickerClosures.last?.0 == [Self.primary])
        #expect(consumer.pickerClosures.last?.1 == false)
    }

    private func eventually(
        timeout: Duration = .seconds(2),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}
