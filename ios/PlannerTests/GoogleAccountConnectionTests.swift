import Foundation
import Testing
@testable import Planner

/// The deterministic Google Sign-In fake: it records every call and resolves
/// Connect from a test-supplied handler, so module behavior is asserted
/// through the same product-oriented interface the production SDK adapter
/// satisfies.
@MainActor
private final class FakeGoogleSignInAdapter: GoogleSignInAdapting {
    var signInCallCount = 0
    var requestedScopes: [[String]] = []
    var signOutCallCount = 0
    var handledCallbackURLs: [URL] = []
    var callbackResult = true
    var signInHandler: () async -> GoogleAuthorizationOutcome = {
        .unavailable(.failed)
    }

    func signIn(
        requestingScopes scopes: [String]
    ) async -> GoogleAuthorizationOutcome {
        signInCallCount += 1
        requestedScopes.append(scopes)
        return await signInHandler()
    }

    func signOut() {
        signOutCallCount += 1
    }

    func handleCallbackURL(_ url: URL) -> Bool {
        handledCallbackURLs.append(url)
        return callbackResult
    }
}

@Suite("Google Account Connection")
@MainActor
struct GoogleAccountConnectionTests {
    private static let calendarReadScope =
        "https://www.googleapis.com/auth/calendar.readonly"

    private let adapter: FakeGoogleSignInAdapter
    private let connection: GoogleAccountConnection

    init() {
        let adapter = FakeGoogleSignInAdapter()
        self.adapter = adapter
        self.connection = GoogleAccountConnection(
            configuration: Self.configuredConnection(),
            makeAdapter: { _ in adapter }
        )
    }

    // MARK: Initial presentation

    @Test("A configured build starts disconnected with a blank status")
    func configuredStartsDisconnectedBlank() {
        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(
            connection.status
                == GoogleAccountConnection.Status(message: nil, tone: .info)
        )
    }

    @Test("An unconfigured build disables Connect and reports configuration")
    func unconfiguredDisablesConnect() {
        var adapterCreated = false
        let connection = GoogleAccountConnection(
            configuration: .unconfigured,
            makeAdapter: { _ in
                adapterCreated = true
                return FakeGoogleSignInAdapter()
            }
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
    }

    // MARK: Connect

    @Test("A successful Connect publishes the connected account")
    func successfulConnect() async {
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(connection.control == .connecting)
        #expect(
            connection.status.message == GoogleAccountConnectionCopy.connecting
        )

        #expect(await controlEventuallyEquals(.connected(Self.profile)))

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
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }

        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile)))
        #expect(adapter.signInCallCount == 1)
        #expect(
            adapter.requestedScopes
                == [["openid", "email", "profile", Self.calendarReadScope]]
        )
    }

    @Test("A missing Calendar scope clears the partial local sign-in")
    func missingCalendarScope() async {
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
                )
            )
        )

        #expect(adapter.signOutCallCount == 1)
        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("User cancellation remains disconnected")
    func cancellation() async {
        adapter.signInHandler = { .cancelled }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.cancelled,
                    tone: .info
                )
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(adapter.signOutCallCount == 0)
    }

    @Test("A generic failure maps to stable Planner-owned copy")
    func genericFailure() async {
        adapter.signInHandler = { .unavailable(.failed) }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.failed,
                    tone: .error
                )
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("A connectivity failure maps to stable Planner-owned copy")
    func connectivityFailure() async {
        adapter.signInHandler = { .unavailable(.offline) }

        connection.connect()
        #expect(
            await statusEventuallyEquals(
                GoogleAccountConnection.Status(
                    message: GoogleAccountConnectionCopy.failed,
                    tone: .error
                )
            )
        )

        #expect(connection.control == .disconnected(connectEnabled: true))
    }

    @Test("Duplicate Connect activations launch one authorization")
    func duplicateConnectProtection() async {
        var release: CheckedContinuation<GoogleAuthorizationOutcome, Never>?
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
        #expect(await controlEventuallyEquals(.connected(Self.profile)))
        #expect(adapter.signInCallCount == 1)
    }

    @Test("Connect is unavailable while connected")
    func connectWhileConnected() async {
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }
        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile)))

        connection.connect()
        #expect(adapter.signInCallCount == 1)
        #expect(connection.control == .connected(Self.profile))
    }

    // MARK: Disconnect on This Device

    @Test("Disconnect on This Device signs out locally and immediately")
    func disconnectOnThisDevice() async {
        adapter.signInHandler = { .connected(Self.authorizedAccount()) }
        connection.connect()
        #expect(await controlEventuallyEquals(.connected(Self.profile)))

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
    func disconnectWithoutConnection() {
        connection.disconnectOnThisDevice()

        #expect(adapter.signOutCallCount == 0)
        #expect(connection.control == .disconnected(connectEnabled: true))
        #expect(connection.status.message == nil)
    }

    // MARK: Callback route

    @Test("The callback route forwards to the adapter")
    func callbackRoute() {
        let url = URL(string: "com.googleusercontent.apps.example:/oauth")!

        #expect(connection.handleCallbackURL(url))
        #expect(adapter.handledCallbackURLs == [url])
    }

    @Test("An unconfigured build owns no callback")
    func callbackRouteUnconfigured() {
        let connection = GoogleAccountConnection(
            configuration: .unconfigured,
            makeAdapter: { _ in FakeGoogleSignInAdapter() }
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

    // MARK: Eventual assertions

    /// Waits for the module's asynchronous Connect completion to publish the
    /// expected control presentation, polling on the main actor.
    private func controlEventuallyEquals(
        _ expected: GoogleAccountConnection.ControlPresentation
    ) async -> Bool {
        await eventually { connection.control == expected }
    }

    private func statusEventuallyEquals(
        _ expected: GoogleAccountConnection.Status
    ) async -> Bool {
        await eventually { connection.status == expected }
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
