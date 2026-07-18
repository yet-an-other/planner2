import Foundation
import Observation

/// The product-oriented outcome of one Google authorization attempt.
///
/// The adapter seam speaks in Planner terms only: whether the user connected
/// (with the granted scopes to validate), cancelled, or could not complete.
/// SDK-specific error types never cross this boundary.
enum GoogleAuthorizationOutcome: Equatable, Sendable {
    /// Google returned an authorized account; the granted scopes still need
    /// product validation before connected state may be published.
    case connected(GoogleAuthorizedAccount)

    /// The user cancelled Google's authorization UI.
    case cancelled

    /// Authorization could not complete.
    case unavailable(GoogleAuthorizationFailure)
}

/// The product-oriented outcome of one silent validation of saved Google
/// authorization: launch restoration and foreground revalidation share it.
enum GoogleRestorationOutcome: Equatable, Sendable {
    /// A saved account was restored, refreshing expired credentials when
    /// Google Sign-In could refresh them.
    case restored(GoogleAuthorizedAccount)

    /// No saved sign-in exists: an ordinary disconnected result, never an
    /// error.
    case noSavedUser

    /// The saved authorization is confirmed invalid or revoked; the local
    /// connection must be cleared.
    case invalidAuthorization

    /// Validation could not complete.
    case unavailable(GoogleAuthorizationFailure)
}

/// Planner-relevant authorization failure kinds.
enum GoogleAuthorizationFailure: Equatable, Sendable {
    /// A transient connectivity failure; connectivity-aware recovery copy
    /// and retry arrive with the offline/lifecycle slice.
    case offline

    /// Any other failure, reported through stable Planner-owned copy.
    case failed
}

/// The memory-only result of a successful Google authorization.
///
/// Planner keeps only what the iOS Account Control presents and never
/// persists it: Google Sign-In owns credential persistence, and email,
/// tokens, and raw SDK responses are deliberately absent here.
struct GoogleAuthorizedAccount: Equatable, Sendable {
    /// The account display name, when Google provides one.
    let displayName: String?

    /// The profile image URL for presentation, when the account has one.
    let imageURL: URL?

    /// Every scope the project-wide grant holds for this account.
    let grantedScopes: Set<String>
}

/// The first-connect explanation the module asks the view to present.
///
/// The copy itself is stable Planner-owned text; the sheet only needs the
/// configured HTTPS Privacy Policy URL. Presenting it is a connection
/// decision, so it supersedes any silent validation still in flight.
struct GoogleConnectionExplanation: Equatable, Sendable, Identifiable {
    /// The configured HTTPS Privacy Policy URL opened by the sheet's
    /// Privacy Policy action.
    let privacyPolicyURL: URL

    var id: URL { privacyPolicyURL }
}

/// The store for the versioned, non-identifying disclosure acknowledgement.
///
/// Only the acknowledged version number is persisted — install-local marker
/// data, never account identity — so a later disclosure version presents the
/// sheet again while an acknowledged one is suppressed.
protocol GoogleConnectionDisclosureStoring {
    /// The disclosure version this installation has acknowledged, if any.
    func acknowledgedDisclosureVersion() -> Int?

    /// Records acknowledgement of a disclosure version.
    func recordAcknowledgedDisclosureVersion(_ version: Int)
}

/// The production disclosure store, backed by install-local user defaults.
struct UserDefaultsGoogleConnectionDisclosureStore: GoogleConnectionDisclosureStoring {
    private let defaults: UserDefaults
    private let key = "PlannerGoogleConnectionDisclosureAcknowledgedVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func acknowledgedDisclosureVersion() -> Int? {
        defaults.object(forKey: key) as? Int
    }

    func recordAcknowledgedDisclosureVersion(_ version: Int) {
        defaults.set(version, forKey: key)
    }
}

/// The connectivity seam behind offline recovery.
///
/// Production observes path changes event-driven (no polling, no timers,
/// no background processing); tests drive transitions directly. The module
/// only needs to know when connectivity returns after an offline period, so
/// it can retry a validation it owes.
protocol GoogleConnectionConnectivityMonitoring: AnyObject {
    /// Starts observation. The handler runs on the main actor whenever
    /// connectivity returns after an offline period.
    func start(onConnectivityReturn: @escaping @MainActor () -> Void)

    /// Stops observation permanently.
    func stop()
}

/// The Google Sign-In seam: one product-oriented interface satisfied by the
/// official SDK in production and by a fake adapter in deterministic tests.
///
/// The interface deliberately excludes SDK disconnect and Google revocation:
/// Disconnect on This Device is local-only, so `signOut()` is the most
/// destructive operation the seam can express.
@MainActor
protocol GoogleSignInAdapting {
    /// Runs the one product Connect flow: account selection, identity, and
    /// the requested scopes in a single authorization request, so existing
    /// project-wide consent is reused without a redundant prompt.
    func signIn(requestingScopes scopes: [String]) async -> GoogleAuthorizationOutcome

    /// Silently restores the saved sign-in, refreshing expired access
    /// credentials when refresh is available. Planner imposes no expiry of
    /// its own: the saved authorization decides the outcome.
    func restorePreviousSignIn() async -> GoogleRestorationOutcome

    /// Removes the local sign-in immediately, without connectivity.
    func signOut()

    /// Forwards an incoming URL to the authorization flow; returns whether
    /// the URL belonged to Google Sign-In.
    func handleCallbackURL(_ url: URL) -> Bool
}

/// The deep native module behind the iOS Account Control and iOS Header
/// Status: it owns the connection state machine — launch restoration,
/// Connect, foreground revalidation, and Disconnect on This Device — and
/// publishes only two observable values: the control's presentation and the
/// current status.
///
/// Exactly one connected account exists at any time. Startup enters a
/// restoring presentation before deciding connected or disconnected, so a
/// saved connection never flashes a false Connect control and a first launch
/// settles into an ordinary blank disconnected state. Connectivity loss is
/// not authorization loss: an established connection survives offline
/// periods with a warning and recovers when connectivity returns or the app
/// next becomes active. Installation identity arrives in a later slice; SDK
/// error classification stays behind the ``GoogleSignInAdapting`` seam.
@MainActor
@Observable
final class GoogleAccountConnection {
    /// Everything the iOS Account Control needs to render.
    enum ControlPresentation: Equatable, Sendable {
        /// Google's supplied button; Connect is disabled when the build is
        /// unconfigured or a connection attempt is being prepared.
        case disconnected(connectEnabled: Bool)

        /// Saved authorization is being restored; the control is disabled
        /// so a false Connect cannot appear or be activated.
        case restoring

        /// An interactive authorization attempt is in flight; the control is
        /// disabled so repeated taps cannot launch a second flow.
        case connecting

        /// The compact connected control with the Disconnect on This Device
        /// affordance.
        case connected(GoogleConnectedProfile)
    }

    /// The memory-only identity the connected control presents.
    struct GoogleConnectedProfile: Equatable, Sendable {
        let displayName: String?
        let imageURL: URL?
    }

    /// The iOS Header Status content: the latest message and its tone. A
    /// `nil` message leaves the reserved status row blank.
    struct Status: Equatable, Sendable {
        let message: String?
        let tone: Tone

        /// Severity mapped to palette tones by the view layer.
        enum Tone: Equatable, Sendable {
            case info
            case warning
            case error
        }
    }

    /// The disclosure version describing this build's Calendar-data
    /// behavior. Increment it when the copy's data-behavior claims change,
    /// so installations that acknowledged an earlier version see the
    /// revised sheet again.
    static let currentDisclosureVersion = 1

    /// The scopes Connect requests in one authorization flow: Google identity
    /// plus read-only Calendar access.
    static let requiredScopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/calendar.readonly",
    ]

    private static let calendarReadScope =
        "https://www.googleapis.com/auth/calendar.readonly"

    private let adapter: (any GoogleSignInAdapting)?

    /// The connectivity observer for offline recovery, when configured.
    private let connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)?

    /// Whether a validation could not complete because connectivity was
    /// lost and is owed a retry when connectivity returns.
    private var owesOfflineValidation = false

    /// The configured HTTPS Privacy Policy URL, present in every configured
    /// build.
    private let privacyPolicyURL: URL?

    /// The versioned acknowledgement store for the first-connect
    /// explanation.
    private let disclosureStore: any GoogleConnectionDisclosureStoring

    /// The disclosure version this build presents.
    private let disclosureVersion: Int

    /// Monotonic marker of the latest connection lifecycle decision, so a
    /// stale asynchronous completion can never overwrite a newer one.
    private var connectionDecision = 0

    /// The current iOS Account Control presentation.
    private(set) var control: ControlPresentation

    /// The current iOS Header Status content.
    private(set) var status: Status

    /// The first-connect explanation awaiting the user's choice, or `nil`
    /// when no sheet should be presented.
    private(set) var explanation: GoogleConnectionExplanation?

    /// Builds the module for a gate-on build. A configured build receives an
    /// adapter, enters the restoring presentation, and immediately validates
    /// the saved authorization; an unconfigured build disables Connect and
    /// reports that the connection is not configured. The release gate
    /// decision itself stays outside: when the gate is off, no module exists
    /// at all.
    init(
        configuration: GoogleAccountConnectionConfiguration,
        makeAdapter: (GoogleAccountConnectionConfiguration.Configured) ->
            any GoogleSignInAdapting,
        disclosureStore: any GoogleConnectionDisclosureStoring,
        connectivityMonitor: (any GoogleConnectionConnectivityMonitoring)? = nil,
        disclosureVersion: Int = GoogleAccountConnection.currentDisclosureVersion
    ) {
        self.disclosureStore = disclosureStore
        self.disclosureVersion = disclosureVersion
        switch configuration {
        case .configured(let configured):
            adapter = makeAdapter(configured)
            self.connectivityMonitor = connectivityMonitor
            privacyPolicyURL = configured.privacyPolicyURL
            control = .restoring
            status = Status(
                message: GoogleAccountConnectionCopy.restoring,
                tone: .info
            )
            beginValidation()
            connectivityMonitor?.start { [weak self] in
                self?.handleConnectivityReturn()
            }
        case .unconfigured, .gatedOff:
            // The composition root never passes a gated-off configuration;
            // defensively it behaves like any other unusable build.
            adapter = nil
            self.connectivityMonitor = nil
            privacyPolicyURL = nil
            control = .disconnected(connectEnabled: false)
            status = Status(
                message: GoogleAccountConnectionCopy.unconfigured,
                tone: .warning
            )
        }
    }

    #if DEBUG
    /// Deterministic presentation seam for SwiftUI previews. Interactive
    /// transitions still work for Disconnect on This Device; Connect and
    /// restoration are no-ops without an adapter.
    init(
        control: ControlPresentation,
        status: Status,
        explanation: GoogleConnectionExplanation? = nil
    ) {
        adapter = nil
        self.connectivityMonitor = nil
        privacyPolicyURL = explanation?.privacyPolicyURL
        disclosureStore = UserDefaultsGoogleConnectionDisclosureStore()
        disclosureVersion = Self.currentDisclosureVersion
        self.control = control
        self.status = status
        self.explanation = explanation
    }
    #endif

    /// The module's lifetime end stops connectivity observation; in-flight
    /// asynchronous work captures the module weakly and is ignored once the
    /// module is gone. (The build-time gate disables the module by never
    /// creating it, so no gated work ever runs.)
    isolated deinit {
        connectivityMonitor?.stop()
    }

    /// Requests Connect. The current disclosure version must be acknowledged
    /// first: an unacknowledged installation gets the first-connect
    /// explanation before any Google authorization UI, and only Continuing
    /// resumes into the one product flow of account selection, identity, and
    /// Calendar read authorization.
    ///
    /// Duplicate activations are refused: Connect only starts from the
    /// enabled disconnected presentation with no explanation already
    /// showing, so restoration, a presented explanation, a connection
    /// already in flight, or an established connection can never launch a
    /// second authorization. Starting Connect supersedes any silent
    /// validation still in flight.
    func connect() {
        guard
            let adapter,
            let privacyPolicyURL,
            case .disconnected(let connectEnabled) = control,
            connectEnabled,
            explanation == nil
        else {
            return
        }

        let acknowledgedVersion =
            disclosureStore.acknowledgedDisclosureVersion() ?? 0
        guard acknowledgedVersion >= disclosureVersion else {
            connectionDecision += 1
            explanation = GoogleConnectionExplanation(
                privacyPolicyURL: privacyPolicyURL
            )
            return
        }

        beginInteractiveConnect(adapter: adapter)
    }

    /// Continues past the first-connect explanation: acknowledges the
    /// current disclosure version for this installation and resumes the same
    /// Connect flow the user requested.
    func continueConnect() {
        guard let adapter, explanation != nil else {
            return
        }

        explanation = nil
        disclosureStore.recordAcknowledgedDisclosureVersion(disclosureVersion)
        beginInteractiveConnect(adapter: adapter)
    }

    /// Cancels the first-connect explanation — by Cancel or by dismissing
    /// the sheet — so no Google authorization UI opens and the cancellation
    /// is reported as ordinary information.
    func cancelConnectExplanation() {
        guard explanation != nil else {
            return
        }

        explanation = nil
        status = Status(
            message: GoogleAccountConnectionCopy.cancelled,
            tone: .info
        )
    }

    /// The one interactive Connect flow: identity plus Calendar read
    /// authorization in a single authorization request.
    private func beginInteractiveConnect(
        adapter: any GoogleSignInAdapting
    ) {
        connectionDecision += 1
        let attempt = connectionDecision
        control = .connecting
        status = Status(
            message: GoogleAccountConnectionCopy.connecting,
            tone: .info
        )

        Task {
            let outcome = await adapter.signIn(
                requestingScopes: Self.requiredScopes
            )

            // A stale completion must not overwrite a newer decision.
            guard attempt == connectionDecision else {
                return
            }

            switch outcome {
            case .connected(let account)
            where account.grantedScopes.contains(Self.calendarReadScope):
                publishConnected(account)
            case .connected:
                // Identity without the Calendar scope is not a connection:
                // clear the partial local sign-in and stay disconnected.
                adapter.signOut()
                control = .disconnected(connectEnabled: true)
                status = Status(
                    message: GoogleAccountConnectionCopy.calendarReadAccessRequired,
                    tone: .warning
                )
            case .cancelled:
                control = .disconnected(connectEnabled: true)
                status = Status(
                    message: GoogleAccountConnectionCopy.cancelled,
                    tone: .info
                )
            case .unavailable:
                control = .disconnected(connectEnabled: true)
                status = Status(
                    message: GoogleAccountConnectionCopy.failed,
                    tone: .error
                )
            }
        }
    }

    /// Revalidates the saved authorization when the app returns to the
    /// foreground. Silent validation never changes the presentation on
    /// entry; only its confirmed outcomes do. An interactive Connect or a
    /// presented explanation owns the pipeline, so foreground refresh is
    /// refused while either is in flight; a newer validation supersedes one
    /// still in flight.
    ///
    /// The Calendar Screen requests this without ever seeing SDK details.
    func validateOnForeground() {
        guard adapter != nil, !isInteractiveFlowInFlight, explanation == nil else {
            return
        }
        beginValidation()
    }

    /// Handles connectivity returning after an offline period: retry the
    /// validation the module owes, unless newer user intent (an interactive
    /// Connect or a presented explanation) owns the pipeline.
    private func handleConnectivityReturn() {
        guard
            adapter != nil,
            owesOfflineValidation,
            !isInteractiveFlowInFlight,
            explanation == nil
        else {
            return
        }
        beginValidation()
    }

    /// Disconnect on This Device: one activation immediately removes the
    /// local connection with no confirmation and no connectivity — including
    /// while offline. The seam can only express local sign-out, so SDK
    /// disconnect and Google revocation are unreachable here.
    func disconnectOnThisDevice() {
        guard case .connected = control else {
            return
        }

        connectionDecision += 1
        owesOfflineValidation = false
        adapter?.signOut()
        control = .disconnected(connectEnabled: true)
        status = Status(
            message: GoogleAccountConnectionCopy.disconnectedOnThisDevice,
            tone: .info
        )
    }

    /// Routes an incoming URL to the authorization flow. Without an adapter
    /// the URL is not ours.
    func handleCallbackURL(_ url: URL) -> Bool {
        adapter?.handleCallbackURL(url) ?? false
    }

    // MARK: Validation pipeline

    private var isInteractiveFlowInFlight: Bool {
        if case .connecting = control {
            return true
        }
        return false
    }

    /// Starts one silent validation attempt: launch restoration and
    /// foreground revalidation share this pipeline. The attempt supersedes
    /// any earlier silent work; its completion applies only while it remains
    /// the latest decision.
    private func beginValidation() {
        guard let adapter else {
            return
        }

        connectionDecision += 1
        let attempt = connectionDecision

        Task { [weak self] in
            let outcome = await adapter.restorePreviousSignIn()

            // A stale completion must not overwrite a newer decision, and a
            // completed module ignores work that outlived it.
            guard let self, attempt == self.connectionDecision else {
                return
            }

            // Any definitive outcome settles the owed offline retry; only an
            // offline failure re-arms it below.
            owesOfflineValidation = false

            switch outcome {
            case .restored(let account)
            where account.grantedScopes.contains(Self.calendarReadScope):
                publishConnected(account)
            case .restored:
                // The grant lost the Calendar scope: the saved identity is
                // not a connection, so clear it and stay disconnected.
                adapter.signOut()
                control = .disconnected(connectEnabled: true)
                status = Status(
                    message: GoogleAccountConnectionCopy.calendarReadAccessRequired,
                    tone: .warning
                )
            case .noSavedUser:
                // An established connection whose saved sign-in vanished
                // expired like any invalid authorization; anything else is
                // an ordinary blank disconnected state.
                let wasConnected = control.isConnected
                control = .disconnected(connectEnabled: true)
                status = wasConnected
                    ? Status(
                        message: GoogleAccountConnectionCopy.expired,
                        tone: .error
                    )
                    : Status(message: nil, tone: .info)
            case .invalidAuthorization:
                adapter.signOut()
                control = .disconnected(connectEnabled: true)
                status = Status(
                    message: GoogleAccountConnectionCopy.expired,
                    tone: .error
                )
            case .unavailable(.offline):
                // Connectivity loss is not authorization loss: an
                // established connection stays connected with a recoverable
                // warning, a launch restoration settles disconnected with
                // the same warning, and either way the module owes a retry
                // when connectivity returns.
                if case .restoring = control {
                    control = .disconnected(connectEnabled: true)
                    status = Status(
                        message: GoogleAccountConnectionCopy.offline,
                        tone: .warning
                    )
                    owesOfflineValidation = true
                } else if control.isConnected {
                    status = Status(
                        message: GoogleAccountConnectionCopy.offline,
                        tone: .warning
                    )
                    owesOfflineValidation = true
                }
            case .unavailable(.failed):
                // A non-connectivity validation failure confirms nothing
                // about the authorization: preserve an established
                // connection silently and settle a launch restoration into
                // the ordinary disconnected presentation.
                if case .restoring = control {
                    control = .disconnected(connectEnabled: true)
                    status = Status(message: nil, tone: .info)
                }
            }
        }
    }

    /// Publishes the connected presentation for an authorized account that
    /// holds the Calendar scope, refreshing the presented identity on every
    /// successful validation.
    private func publishConnected(_ account: GoogleAuthorizedAccount) {
        control = .connected(
            GoogleConnectedProfile(
                displayName: account.displayName,
                imageURL: account.imageURL
            )
        )
        status = Status(
            message: GoogleAccountConnectionCopy.connected,
            tone: .info
        )
    }
}

private extension GoogleAccountConnection.ControlPresentation {
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

extension GoogleAccountConnectionCopy {
    /// Shown while saved authorization is restored at launch.
    static let restoring = "Restoring Google account…"

    /// Shown while the Google authorization flow is in flight.
    static let connecting = "Connecting Google account…"

    /// Shown after identity and Calendar read authorization succeed.
    static let connected = "Google account connected"

    /// Shown after Disconnect on This Device removes the local connection.
    static let disconnectedOnThisDevice =
        "Google account disconnected on this device"

    /// Shown when the user cancels Google's authorization UI.
    static let cancelled = "Google connection cancelled"

    /// Shown when identity succeeds without the Calendar scope; the partial
    /// local sign-in is cleared and the app stays disconnected.
    static let calendarReadAccessRequired = "Calendar read access is required"

    /// Shown when saved authorization is confirmed invalid or revoked, so
    /// the local connection is cleared.
    static let expired = "Google connection expired. Connect again"

    /// Shown when connectivity loss prevents validation; an established
    /// connection stays connected and validation retries on recovery.
    static let offline =
        "You\u{2019}re offline. Google connection will be checked when online"

    /// Shown for any authorization failure without more specific copy.
    static let failed = "Google connection failed. Try again"

    /// The first-connect explanation title.
    static let explanationTitle = "Connect Google Calendar"

    /// The first-connect explanation: read-only purpose, no-write
    /// assurance, and this build's actual Calendar-data behavior.
    static let explanationBody =
        "Planner requests read-only access to Google Calendar so future "
        + "features can show your calendars and events. Planner cannot "
        + "create, edit, or delete anything in your Google Calendar. "
        + "This build downloads no Calendar data."

    /// The explanation action that acknowledges and resumes Connect.
    static let explanationContinue = "Continue"

    /// The explanation action that cancels Connect.
    static let explanationCancel = "Cancel"

    /// The explanation action opening the configured Privacy Policy URL.
    static let privacyPolicyAction = "Privacy Policy"
}
