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

/// Planner-relevant authorization failure kinds.
enum GoogleAuthorizationFailure: Equatable, Sendable {
    /// A transient connectivity failure; recovery arrives with the
    /// offline/lifecycle slice.
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

    /// Removes the local sign-in immediately, without connectivity.
    func signOut()

    /// Forwards an incoming URL to the authorization flow; returns whether
    /// the URL belonged to Google Sign-In.
    func handleCallbackURL(_ url: URL) -> Bool
}

/// The deep native module behind the iOS Account Control and iOS Header
/// Status: it owns the complete Connect and Disconnect on This Device state
/// machine and publishes only two observable values — the control's
/// presentation and the current status.
///
/// Exactly one connected account exists at any time. Restoration, refresh,
/// connectivity recovery, the first-connect explanation, and installation
/// identity arrive in later slices as hidden implementation growth; SDK
/// error classification stays behind the ``GoogleSignInAdapting`` seam.
@MainActor
@Observable
final class GoogleAccountConnection {
    /// Everything the iOS Account Control needs to render.
    enum ControlPresentation: Equatable, Sendable {
        /// Google's supplied button; Connect is disabled when the build is
        /// unconfigured or a connection attempt is being prepared.
        case disconnected(connectEnabled: Bool)

        /// An authorization attempt is in flight; the control is disabled
        /// so repeated taps cannot launch a second flow.
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

    /// Monotonic marker of the latest connection lifecycle decision, so a
    /// stale asynchronous completion can never overwrite a newer one.
    private var connectionDecision = 0

    /// The current iOS Account Control presentation.
    private(set) var control: ControlPresentation

    /// The current iOS Header Status content.
    private(set) var status: Status

    /// Builds the module for a gate-on build. A configured build receives an
    /// adapter and starts disconnected with a blank status; an unconfigured
    /// build disables Connect and reports that the connection is not
    /// configured. The release gate decision itself stays outside: when the
    /// gate is off, no module exists at all.
    init(
        configuration: GoogleAccountConnectionConfiguration,
        makeAdapter: (GoogleAccountConnectionConfiguration.Configured) ->
            any GoogleSignInAdapting
    ) {
        switch configuration {
        case .configured(let configured):
            adapter = makeAdapter(configured)
            control = .disconnected(connectEnabled: true)
            status = Status(message: nil, tone: .info)
        case .unconfigured, .gatedOff:
            // The composition root never passes a gated-off configuration;
            // defensively it behaves like any other unusable build.
            adapter = nil
            control = .disconnected(connectEnabled: false)
            status = Status(
                message: GoogleAccountConnectionCopy.unconfigured,
                tone: .warning
            )
        }
    }

    #if DEBUG
    /// Deterministic presentation seam for SwiftUI previews. Interactive
    /// transitions still work for Disconnect on This Device; Connect is a
    /// no-op without an adapter.
    init(control: ControlPresentation, status: Status) {
        adapter = nil
        self.control = control
        self.status = status
    }
    #endif

    /// Requests Connect: account selection, identity, and Calendar read
    /// authorization as one product flow.
    ///
    /// Duplicate activations are refused: Connect only starts from the
    /// enabled disconnected presentation, so a connection already in flight
    /// or an established connection can never launch a second authorization.
    func connect() {
        guard
            let adapter,
            case .disconnected(let connectEnabled) = control,
            connectEnabled
        else {
            return
        }

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

    /// Disconnect on This Device: one activation immediately removes the
    /// local connection with no confirmation and no connectivity. The seam
    /// can only express local sign-out, so SDK disconnect and Google
    /// revocation are unreachable here.
    func disconnectOnThisDevice() {
        guard case .connected = control else {
            return
        }

        connectionDecision += 1
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
}

extension GoogleAccountConnectionCopy {
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

    /// Shown for any authorization failure without more specific copy.
    static let failed = "Google connection failed. Try again"
}
