import Foundation

/// The Calendar Data coordinator (iOS Experience glossary): the one
/// composition root for the Google Account Connection and the Calendar
/// Data modules derived from it. It owns construction and every flow
/// between the three modules — the disclosure-gated account publication
/// (Source Calendars first: its selection publication settles the
/// Calendar Events module's connection state), the Selected Source
/// Calendars publication, and forbidden/not-found recovery — so no
/// wiring rule lives in the app delegate or in a pass-through between
/// modules. The view observes the three modules directly.
@MainActor
final class CalendarDataCoordinator: CalendarDataAccountConsuming {
    /// The Google Account Connection module. `nil` while the build-time
    /// release gate is off: no connection behavior exists and the
    /// Calendar Screen mounts neither connection seam.
    ///
    /// A `var` with a `nil` start so the fully initialized coordinator
    /// can be the connection's Calendar-data consumer at construction.
    private(set) var connection: GoogleAccountConnection? = nil

    /// Disclosure-gated Source Calendar loading, reconciliation, and
    /// per-account selection persistence.
    let sourceCalendars: SourceCalendarsModel?

    /// The Calendar Events module, persisting events as Stored Calendar
    /// Events (ADR 0007): presented at process start, written through on
    /// every successful response, and wiped on Disconnect on This Device.
    let events: CalendarEventsModel?

    /// Builds the production graph: loads the release gate from the main
    /// bundle and constructs every collaborator for real.
    convenience init() {
        switch GoogleAccountConnectionConfiguration.load(from: .main) {
        case .gatedOff:
            self.init(configuration: nil)
        case let configuration:
            self.init(
                configuration: configuration,
                environment: .current(),
                makeCalendarAPI: { GoogleCalendarAPIAdapter() },
                makeConnectivityMonitor: { NWPathConnectivityMonitor() },
                eventStore: FileStoredCalendarEventsStore(),
                selectionStore: UserDefaultsSelectedSourceCalendarsStore(),
                disclosureStore: UserDefaultsGoogleConnectionDisclosureStore(),
                makeSignInAdapter: { configured in
                    GoogleSignInSDKAdapter(configuration: configured)
                },
                makeInstallationBoundary: { selectionStore in
                    GoogleConnectionInstallationBoundary(
                        defaults: .standard,
                        deviceMarkerStore:
                            KeychainGoogleConnectionDeviceMarkerStore(),
                        selectedSourceCalendarsStore: selectionStore
                    )
                }
            )
        }
    }

    /// Builds the graph with every collaborator injected — the test seam.
    /// A `nil` configuration is the release gate's off position: no
    /// module exists and all three publications are `nil`.
    init(
        configuration: GoogleAccountConnectionConfiguration?,
        environment: CalendarEnvironment = .current(),
        makeCalendarAPI: () -> any GoogleCalendarEventsAdapting
            & GoogleSourceCalendarsAdapting = { GoogleCalendarAPIAdapter() },
        makeConnectivityMonitor: () -> any
            GoogleConnectionConnectivityMonitoring = {
                NWPathConnectivityMonitor()
            },
        eventStore: (any StoredCalendarEventsStoring)? = nil,
        selectionStore: any SelectedSourceCalendarsStoring =
            UserDefaultsSelectedSourceCalendarsStore(),
        disclosureStore: any GoogleConnectionDisclosureStoring =
            UserDefaultsGoogleConnectionDisclosureStore(),
        makeSignInAdapter: (GoogleAccountConnectionConfiguration.Configured)
            -> any GoogleSignInAdapting = { configured in
                GoogleSignInSDKAdapter(configuration: configured)
            },
        makeInstallationBoundary: (any SelectedSourceCalendarsStoring) ->
            GoogleConnectionInstallationBoundary = { selectionStore in
                GoogleConnectionInstallationBoundary(
                    defaults: .standard,
                    deviceMarkerStore:
                        KeychainGoogleConnectionDeviceMarkerStore(),
                    selectedSourceCalendarsStore: selectionStore
                )
            }
    ) {
        guard let configuration else {
            connection = nil
            sourceCalendars = nil
            events = nil
            return
        }

        let calendarAPI = makeCalendarAPI()
        let events = CalendarEventsModel(
            environment: environment,
            adapter: calendarAPI,
            connectivityMonitor: makeConnectivityMonitor(),
            eventStore: eventStore
        )
        let sources = SourceCalendarsModel(
            adapter: calendarAPI,
            store: selectionStore,
            selectionConsumer: events,
            connectivityMonitor: makeConnectivityMonitor()
        )
        // Forbidden/not-found event failures recover through the Source
        // Calendars module's one live reload and reconciliation.
        events.sourceCalendarRecovery = sources
        self.events = events
        self.sourceCalendars = sources
        connection = GoogleAccountConnection(
            configuration: configuration,
            makeAdapter: makeSignInAdapter,
            disclosureStore: disclosureStore,
            connectivityMonitor: makeConnectivityMonitor(),
            installationBoundary: makeInstallationBoundary(selectionStore),
            calendarDataConsumer: self
        )
        // Stored Calendar Events present at process start only for an
        // installation that has acknowledged the current disclosure;
        // an older acknowledgement keeps Calendar Events memory-only
        // until the revised explanation is acknowledged (ADR 0007).
        if (disclosureStore.acknowledgedDisclosureVersion() ?? 0)
            >= GoogleAccountConnection.currentDisclosureVersion
        {
            events.presentStoredCalendarEvents()
        }
    }

    /// Publishes the disclosure-gated Calendar-data account to the
    /// Calendar Data modules: the Source Calendars module first — its
    /// selection publication settles the Calendar Events module's
    /// connection state — then the Calendar Events module, whose Stored
    /// Calendar Events read, write-through, and Disconnect on This
    /// Device wipe follow the same account (ADR 0007).
    func setCalendarDataAccountID(_ accountID: String?) {
        sourceCalendars?.setCalendarDataAccountID(accountID)
        events?.setCalendarDataAccountID(accountID)
    }
}
