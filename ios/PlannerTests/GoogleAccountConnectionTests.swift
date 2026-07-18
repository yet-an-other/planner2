import Foundation
import Testing
@testable import Planner

/// The deterministic Google Sign-In fake: it records every call and resolves
/// Connect and restoration from test-supplied handlers, so module behavior
/// is asserted through the same product-oriented interface the production
/// SDK adapter satisfies.
@MainActor
private final class FakeGoogleSignInAdapter: GoogleSignInAdapting {
    var signInCallCount = 0
    var requestedScopes: [[String]] = []
    var restoreCallCount = 0
    var signOutCallCount = 0
    var handledCallbackURLs: [URL] = []
    var callbackResult = true
    var signInHandler: () async -> GoogleAuthorizationOutcome = {
        .unavailable(.failed)
    }
    var restoreHandler: () async -> GoogleRestorationOutcome = {
        .noSavedUser
    }

    func signIn(
        requestingScopes scopes: [String]
    ) async -> GoogleAuthorizationOutcome {
        signInCallCount += 1
        requestedScopes.append(scopes)
        return await signInHandler()
    }

    func restorePreviousSignIn() async -> GoogleRestorationOutcome {
        restoreCallCount += 1
        return await restoreHandler()
    }

    func signOut() {
        signOutCallCount += 1
    }

    func handleCallbackURL(_ url: URL) -> Bool {
        handledCallbackURLs.append(url)
        return callbackResult
    }
}

/// The deterministic disclosure store: an in-memory acknowledgement marker
/// behind the same seam the production UserDefaults store satisfies.
private final class FakeGoogleConnectionDisclosureStore: GoogleConnectionDisclosureStoring {
    var acknowledgedVersion: Int?
    var recordCallCount = 0

    init(acknowledgedVersion: Int? = nil) {
        self.acknowledgedVersion = acknowledgedVersion
    }

    func acknowledgedDisclosureVersion() -> Int? {
        acknowledgedVersion
    }

    func recordAcknowledgedDisclosureVersion(_ version: Int) {
        recordCallCount += 1
        acknowledgedVersion = version
    }
}

@Suite("Google Account Connection")
@MainActor
struct GoogleAccountConnectionTests {
    private static let calendarReadScope =
        "https://www.googleapis.com/auth/calendar.readonly"

    // MARK: Launch restoration

    @Test("A configured build starts restoring, then settles disconnected")
    func startsRestoringThenBlankDisconnected() async {
        let (connection, adapter, _) = makeConnection()

        // The restoring presentation is decided synchronously at startup, so
        // a saved connection can never flash a false Connect control.
        #expect(connection.control == .restoring)
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.restoring,
                    tone: .info
                )
        )

        // No saved session is ordinary: blank status, Connect available.
        #expect(await settledDisconnected(connection))
        #expect(connection.status == GoogleAccountConnection.Status(
            message: nil,
            tone: .info
        ))
        #expect(adapter.restoreCallCount == 1)
    }

    @Test("A valid saved connection restores connected identity")
    func validRestoration() async {
        let (connection, _, _) = makeConnection {
            $0.restoreHandler = { .restored(Self.authorizedAccount()) }
        }

        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.connected,
                    tone: .info
                )
        )
    }

    @Test("A connection refreshed during restoration is connected")
    func refreshedRestoration() async {
        // The SDK refreshes expired access credentials as part of restore;
        // a refreshed account reaches the module as an ordinary restored
        // account.
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = { .restored(Self.authorizedAccount()) }
        }

        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
        #expect(adapter.restoreCallCount == 1)
        #expect(adapter.signInCallCount == 0)
    }

    @Test("A restored session missing the Calendar scope is cleared")
    func restoredWithoutCalendarScope() async {
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = {
                .restored(
                    GoogleAuthorizedAccount(
                        displayName: "Rua Did",
                        imageURL: nil,
                        grantedScopes: ["openid", "email", "profile"]
                    )
                )
            }
        }

        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.calendarReadAccessRequired,
                    tone: .warning
                ),
                in: connection
            )
        )
        #expect(adapter.signOutCallCount == 1)
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("Invalid saved authorization clears the connection with guidance")
    func invalidRestoration() async {
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = { .invalidAuthorization }
        }

        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.expired,
                    tone: .error
                ),
                in: connection
            )
        )
        #expect(adapter.signOutCallCount == 1)
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("A stale restoration completion cannot overwrite a newer validation")
    func staleRestorationCompletion() async {
        var firstRestore: CheckedContinuation<GoogleRestorationOutcome, Never>?
        var secondRestore: CheckedContinuation<GoogleRestorationOutcome, Never>?
        let (connection, adapter, _) = makeConnection()
        adapter.restoreHandler = {
            await withCheckedContinuation { continuation in
                if adapter.restoreCallCount == 1 {
                    firstRestore = continuation
                } else {
                    secondRestore = continuation
                }
            }
        }

        // The launch restoration is already in flight; a foreground
        // validation supersedes it.
        #expect(await eventually { adapter.restoreCallCount == 1 })
        connection.validateOnForeground()
        #expect(await eventually { adapter.restoreCallCount == 2 })

        // The newer attempt decides the state…
        secondRestore?.resume(returning: .restored(Self.authorizedAccount()))
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        // …and the stale completion cannot overwrite it.
        firstRestore?.resume(returning: .noSavedUser)
        #expect(
            await neverHappens {
                connection.control != .connected(Self.profile)
            }
        )
    }

    // MARK: Foreground validation

    @Test("A foreground refresh silently keeps a healthy connection")
    func foregroundValidationKeepsConnection() async {
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = { .restored(Self.authorizedAccount()) }
        }
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        connection.validateOnForeground()

        #expect(await eventually { adapter.restoreCallCount == 2 })
        #expect(connection.control == .connected(Self.profile))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.connected,
                    tone: .info
                )
        )
    }

    @Test("A foreground refresh is refused while Connect is in flight")
    func foregroundValidationRefusedDuringConnect() async {
        var release: CheckedContinuation<GoogleAuthorizationOutcome, Never>?
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = {
            await withCheckedContinuation { release = $0 }
        }

        connection.connect()
        #expect(await eventually { adapter.signInCallCount == 1 })

        connection.validateOnForeground()
        #expect(adapter.restoreCallCount == 1)

        release?.resume(returning: .connected(Self.authorizedAccount()))
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
    }

    @Test("Connect supersedes a silent validation still in flight")
    func connectSupersedesSilentValidation() async {
        var releaseValidation: CheckedContinuation<GoogleRestorationOutcome, Never>?
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.restoreHandler = {
            await withCheckedContinuation { releaseValidation = $0 }
        }
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.validateOnForeground()
        #expect(await eventually { adapter.restoreCallCount == 2 })

        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        // The superseded validation completion is ignored.
        releaseValidation?.resume(returning: .noSavedUser)
        #expect(
            await neverHappens {
                connection.control != .connected(Self.profile)
            }
        )
    }

    @Test("A lost saved session during validation reports expiry")
    func validationDiscoversLostSession() async {
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = { .restored(Self.authorizedAccount()) }
        }
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        adapter.restoreHandler = { .noSavedUser }
        connection.validateOnForeground()

        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.expired,
                    tone: .error
                ),
                in: connection
            )
        )
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    // MARK: Initial presentation

    @Test("An unconfigured build disables Connect and reports configuration")
    func unconfiguredDisablesConnect() {
        var adapterCreated = false
        let connection = GoogleAccountConnection(
            configuration: .unconfigured,
            makeAdapter: { _ in
                adapterCreated = true
                return FakeGoogleSignInAdapter()
            },
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )

        #expect(!adapterCreated)
        #expect(connection.control == .disconnected(connectEnabled: false))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.unconfigured,
                    tone: .warning
                )
        )

        connection.connect()
        #expect(connection.control == .disconnected(connectEnabled: false))
        #expect(connection.explanation == nil)
    }

    // MARK: First-connect explanation

    @Test("The first Connect presents the explanation before any Google UI")
    func firstConnectPresentsExplanation() async {
        let (connection, adapter, _) = makeConnection(
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )
        #expect(await settledDisconnected(connection))

        connection.connect()

        #expect(
            connection.explanation
                == GoogleConnectionExplanation(
                    privacyPolicyURL: URL(string: "https://planner.example/privacy")!
                )
        )
        #expect(adapter.signInCallCount == 0)
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("Continue acknowledges the disclosure and resumes the same Connect")
    func continueResumesConnect() async {
        let (connection, adapter, store) = makeConnection(
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(connection.explanation != nil)

        connection.continueConnect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        #expect(connection.explanation == nil)
        #expect(store.recordCallCount == 1)
        #expect(
            store.acknowledgedVersion
                == GoogleAccountConnection.currentDisclosureVersion
        )
        #expect(adapter.signInCallCount == 1)
        #expect(
            adapter.requestedScopes
                == [["openid", "email", "profile", Self.calendarReadScope]]
        )
    }

    @Test("Cancelling the explanation opens no Google UI and reports cancellation")
    func cancelExplanationReportsCancellation() async {
        let (connection, adapter, _) = makeConnection(
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )
        #expect(await settledDisconnected(connection))

        connection.connect()
        #expect(connection.explanation != nil)

        connection.cancelConnectExplanation()

        #expect(connection.explanation == nil)
        #expect(adapter.signInCallCount == 0)
        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.cancelled,
                    tone: .info
                )
        )
    }

    @Test("An acknowledged current version suppresses the explanation")
    func acknowledgedVersionSuppressesSheet() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .cancelled }

        connection.connect()

        #expect(connection.explanation == nil)
        #expect(connection.control == .connecting)
    }

    @Test("An incremented disclosure version presents the explanation again")
    func incrementedVersionPresentsSheetAgain() async {
        let store = FakeGoogleConnectionDisclosureStore(acknowledgedVersion: 1)
        let updatedVersion = GoogleAccountConnection.currentDisclosureVersion + 1
        let (connection, adapter, _) = makeConnection(
            disclosureStore: store,
            disclosureVersion: updatedVersion
        )
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(connection.explanation != nil)
        #expect(adapter.signInCallCount == 0)

        connection.continueConnect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
        #expect(store.acknowledgedVersion == updatedVersion)
    }

    @Test("A repeated Connect while explaining presents one sheet")
    func duplicateConnectWhileExplaining() async {
        let (connection, adapter, _) = makeConnection(
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )
        #expect(await settledDisconnected(connection))

        connection.connect()
        let presented = connection.explanation
        connection.connect()

        #expect(connection.explanation == presented)
        #expect(adapter.signInCallCount == 0)
    }

    // MARK: Connect

    @Test("A successful Connect publishes the connected account")
    func successfulConnect() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(connection.control == .connecting)
        #expect(
            connection.status.message == GoogleAccountConnectionCopy.connecting
        )

        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        #expect(adapter.signInCallCount == 1)
        #expect(
            adapter.requestedScopes
                == [["openid", "email", "profile", Self.calendarReadScope]]
        )
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.connected,
                    tone: .info
                )
        )
    }

    @Test("Existing consent is reused in one authorization request")
    func existingConsentReuse() async {
        // When the project-wide grant already covers the Calendar scope, the
        // single authorization request returns it without a redundant prompt;
        // no incremental scope request follows.
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
        #expect(adapter.signInCallCount == 1)
        #expect(
            adapter.requestedScopes
                == [["openid", "email", "profile", Self.calendarReadScope]]
        )
    }

    @Test("A missing Calendar scope clears the partial local sign-in")
    func missingCalendarScope() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = {
            .connected(
                GoogleAuthorizedAccount(
                    displayName: "Rua Did",
                    imageURL: nil,
                    grantedScopes: ["openid", "email", "profile"]
                )
            )
        }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.calendarReadAccessRequired,
                    tone: .warning
                ),
                in: connection
            )
        )

        #expect(adapter.signOutCallCount == 1)
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("User cancellation remains disconnected")
    func cancellation() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .cancelled }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.cancelled,
                    tone: .info
                ),
                in: connection
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(adapter.signOutCallCount == 0)
    }

    @Test("A generic failure maps to stable Planner-owned copy")
    func genericFailure() async {
        let (connection, _, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        // The fake's default Connect outcome is a generic failure.

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.failed,
                    tone: .error
                ),
                in: connection
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("A connectivity failure maps to stable Planner-owned copy")
    func connectivityFailure() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .unavailable(.offline) }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.failed,
                    tone: .error
                ),
                in: connection
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("Duplicate Connect activations launch one authorization")
    func duplicateConnectProtection() async {
        var release: CheckedContinuation<GoogleAuthorizationOutcome, Never>?
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = {
            await withCheckedContinuation { continuation in
                release = continuation
            }
        }

        connection.connect()
        #expect(await eventually { release != nil })

        // With the authorization in flight, repeated activations are
        // refused: the control already presents the connecting state.
        connection.connect()
        #expect(adapter.signInCallCount == 1)
        #expect(connection.control == .connecting)

        release?.resume(returning: .connected(Self.authorizedAccount()))
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))
        #expect(adapter.signInCallCount == 1)
    }

    @Test("Connect is unavailable while restoring")
    func connectUnavailableWhileRestoring() async {
        var release: CheckedContinuation<GoogleRestorationOutcome, Never>?
        let (connection, adapter, _) = makeConnection {
            $0.restoreHandler = {
                await withCheckedContinuation { release = $0 }
            }
        }

        connection.connect()
        #expect(adapter.signInCallCount == 0)
        #expect(connection.control == .restoring)

        #expect(await eventually { release != nil })
        release?.resume(returning: .noSavedUser)
        #expect(await settledDisconnected(connection))
    }

    @Test("Connect is unavailable while connected")
    func connectWhileConnected() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }
        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        connection.connect()
        #expect(adapter.signInCallCount == 1)
        #expect(connection.control == .connected(Self.profile))
    }

    // MARK: Disconnect on This Device

    @Test("Disconnect on This Device signs out locally and immediately")
    func disconnectOnThisDevice() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }
        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile), in: connection))

        // Local sign-out is synchronous: the disconnected presentation and
        // status apply without awaiting anything or reaching the network.
        connection.disconnectOnThisDevice()

        #expect(adapter.signOutCallCount == 1)
        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.disconnectedOnThisDevice,
                    tone: .info
                )
        )
    }

    @Test("Disconnect is unavailable without a connection")
    func disconnectWithoutConnection() async {
        let (connection, adapter, _) = makeConnection()
        #expect(await settledDisconnected(connection))

        connection.disconnectOnThisDevice()

        #expect(adapter.signOutCallCount == 0)
        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(connection.status.message == nil)
    }

    // MARK: Callback route

    @Test("The callback route forwards to the adapter")
    func callbackRoute() {
        let (connection, adapter, _) = makeConnection()
        let url = URL(string: "com.googleusercontent.apps.example:/oauth")!

        #expect(connection.handleCallbackURL(url))
        #expect(adapter.handledCallbackURLs == [url])
    }

    @Test("An unconfigured build owns no callback")
    func callbackRouteUnconfigured() {
        let connection = GoogleAccountConnection(
            configuration: .unconfigured,
            makeAdapter: { _ in FakeGoogleSignInAdapter() },
            disclosureStore: FakeGoogleConnectionDisclosureStore()
        )
        let url = URL(string: "com.googleusercontent.apps.example:/oauth")!

        #expect(!connection.handleCallbackURL(url))
    }

    // MARK: Fixtures

    private static let profile = GoogleAccountConnection.GoogleConnectedProfile(
        displayName: "Rua Did",
        imageURL: nil
    )

    private static func authorizedAccount() -> GoogleAuthorizedAccount {
        GoogleAuthorizedAccount(
            displayName: "Rua Did",
            imageURL: nil,
            grantedScopes: ["openid", "email", "profile", calendarReadScope]
        )
    }

    private static func configuredConnection() -> GoogleAccountConnectionConfiguration {
        GoogleAccountConnectionConfiguration(
            infoDictionary: [
                "PlannerGoogleConnectionEnabled": "YES",
                "GIDClientID":
                    "1050123456789-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com",
                "PlannerGoogleReversedClientID":
                    "com.googleusercontent.apps.1050123456789-abcdefghijklmnopqrstuvwxyz012345",
                "PlannerPrivacyPolicyURL": "https://planner.example/privacy",
            ]
        )
    }

    /// Builds a module with its fake adapter and disclosure store
    /// configured before the module starts its launch restoration, keeping
    /// every test deterministic. The default disclosure store has already
    /// acknowledged the current version, so Connect tests exercise the
    /// authorization flow directly; explanation tests pass a fresh store.
    private func makeConnection(
        disclosureStore: FakeGoogleConnectionDisclosureStore = FakeGoogleConnectionDisclosureStore(
            acknowledgedVersion: GoogleAccountConnection.currentDisclosureVersion
        ),
        disclosureVersion: Int = GoogleAccountConnection.currentDisclosureVersion,
        configure: (FakeGoogleSignInAdapter) -> Void = { _ in }
    ) -> (
        connection: GoogleAccountConnection,
        adapter: FakeGoogleSignInAdapter,
        disclosureStore: FakeGoogleConnectionDisclosureStore
    ) {
        let adapter = FakeGoogleSignInAdapter()
        configure(adapter)
        let connection = GoogleAccountConnection(
            configuration: Self.configuredConnection(),
            makeAdapter: { _ in adapter },
            disclosureStore: disclosureStore,
            disclosureVersion: disclosureVersion
        )
        return (connection, adapter, disclosureStore)
    }

    // MARK: Eventual assertions

    /// Waits for the launch restoration to settle into the ordinary
    /// disconnected presentation.
    private func settledDisconnected(
        _ connection: GoogleAccountConnection
    ) async -> Bool {
        await eventually {
            connection.control == .disconnected(connectEnabled: true)
        }
    }

    private func controlEventuallyEquals(
        _ expected: GoogleAccountConnection.ControlPresentation,
        in connection: GoogleAccountConnection
    ) async -> Bool {
        await eventually { connection.control == expected }
    }

    private func statusEventuallyEquals(
        _ expected: GoogleAccountConnection.Status,
        in connection: GoogleAccountConnection
    ) async -> Bool {
        await eventually { connection.status == expected }
    }

    /// Confirms a condition stays false for a short settle window, proving a
    /// stale completion was ignored rather than merely late.
    private func neverHappens(
        window: Duration = .milliseconds(100),
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + window
        while ContinuousClock.now < deadline {
            if condition() {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
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
