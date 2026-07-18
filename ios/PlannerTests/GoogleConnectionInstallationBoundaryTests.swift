import Foundation
import Testing
@testable import Planner

/// The deterministic device-marker store: an in-memory marker behind the
/// same seam the production Keychain store satisfies, shared by the
/// connection test suites.
final class FakeDeviceMarkerStore: GoogleConnectionDeviceMarkerStore {
    var storedMarker: String?
    var setCallCount = 0

    func marker() -> String? {
        storedMarker
    }

    func setMarker(_ marker: String) {
        setCallCount += 1
        storedMarker = marker
    }
}

/// Install-local defaults for one test, isolated from other tests and the
/// host app.
func makeEphemeralUserDefaults() -> UserDefaults {
    guard let defaults = UserDefaults(
        suiteName: "test.google-connection.\(UUID().uuidString)"
    ) else {
        preconditionFailure("An ephemeral UserDefaults suite must be creatable")
    }
    return defaults
}

@Suite("Google Connection Installation Boundary")
struct GoogleConnectionInstallationBoundaryTests {
    private static let markerKey =
        GoogleConnectionInstallationBoundary.installMarkerKey

    @Test("A first install generates the marker pair, then relaunches as the same installation")
    func firstInstallThenRelaunch() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        #expect(boundary.establish() == .fresh)
        #expect(store.setCallCount == 1)

        let generated = defaults.string(forKey: Self.markerKey)
        #expect(generated != nil)
        #expect(generated.flatMap { UUID(uuidString: $0) } != nil)
        #expect(store.storedMarker == generated)

        // An ordinary relaunch over the same stores is the same
        // installation and regenerates nothing.
        let relaunch = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )
        #expect(relaunch.establish() == .same)
        #expect(store.setCallCount == 1)
    }

    @Test("An app-update-equivalent state keeps the installation")
    func appUpdateKeepsInstallation() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        let marker = UUID().uuidString
        defaults.set(marker, forKey: Self.markerKey)
        store.storedMarker = marker

        // A new boundary instance over persisted markers models an update:
        // the stores survive, the code version does not matter.
        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        #expect(boundary.establish() == .same)
        #expect(store.setCallCount == 0)
        #expect(defaults.string(forKey: Self.markerKey) == marker)
    }

    @Test("A reinstall with surviving device marker starts fresh")
    func reinstallWithSurvivingDeviceMarker() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        let staleMarker = UUID().uuidString
        // Uninstall removes user defaults but the device marker survives.
        store.storedMarker = staleMarker

        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        #expect(boundary.establish() == .fresh)
        #expect(store.storedMarker != staleMarker)
        #expect(
            defaults.string(forKey: Self.markerKey) == store.storedMarker
        )
    }

    @Test("A backup migrated to different hardware is distinguished")
    func migratedBackup() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        let originalMarker = UUID().uuidString
        // The backup carries the install-local marker; the new device has
        // no matching device marker.
        defaults.set(originalMarker, forKey: Self.markerKey)

        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        #expect(boundary.establish() == .migrated)
        #expect(store.storedMarker != nil)
        #expect(store.storedMarker != originalMarker)
        #expect(
            defaults.string(forKey: Self.markerKey) == store.storedMarker
        )
    }

    @Test("A mismatched device marker is treated as migrated")
    func markerMismatch() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        defaults.set(UUID().uuidString, forKey: Self.markerKey)
        store.storedMarker = UUID().uuidString

        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        #expect(boundary.establish() == .migrated)
        #expect(
            defaults.string(forKey: Self.markerKey) == store.storedMarker
        )
    }

    @Test("Corrupted matching markers never establish an installation")
    func corruptedMarkers() {
        let defaults = makeEphemeralUserDefaults()
        let store = FakeDeviceMarkerStore()
        defaults.set("corrupted", forKey: Self.markerKey)
        store.storedMarker = "corrupted"

        let boundary = GoogleConnectionInstallationBoundary(
            defaults: defaults,
            deviceMarkerStore: store
        )

        let installation = boundary.establish()
        #expect(installation != .same)

        let regenerated = defaults.string(forKey: Self.markerKey)
        #expect(regenerated.flatMap { UUID(uuidString: $0) } != nil)
        #expect(store.storedMarker == regenerated)
    }
}

@Suite("Google Account Connection installation boundary integration")
@MainActor
struct GoogleAccountConnectionInstallationTests {
    @Test("A fresh installation clears stale sign-in state before restoration")
    func freshInstallClearsBeforeRestore() async {
        let adapter = FakeGoogleSignInAdapter()
        let connection = GoogleAccountConnection(
            configuration: GoogleAccountConnectionTests.configuredConnection(),
            makeAdapter: { _ in adapter },
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion: GoogleAccountConnection.currentDisclosureVersion
            ),
            installationBoundary: GoogleConnectionInstallationBoundary(
                defaults: makeEphemeralUserDefaults(),
                deviceMarkerStore: FakeDeviceMarkerStore()
            )
        )

        // The stale sign-in is cleared locally, then the ordinary blank
        // disconnected result arrives from restoration.
        #expect(adapter.signOutCallCount == 1)
        #expect(
            await eventuallySettlesDisconnected(connection)
        )
        #expect(adapter.restoreCallCount == 1)
        #expect(connection.status.message == nil)
    }

    @Test("The same installation restores without clearing")
    func sameInstallationRestores() async {
        let adapter = FakeGoogleSignInAdapter()
        let connection = GoogleAccountConnection(
            configuration: GoogleAccountConnectionTests.configuredConnection(),
            makeAdapter: { _ in adapter },
            disclosureStore: FakeGoogleConnectionDisclosureStore(
                acknowledgedVersion: GoogleAccountConnection.currentDisclosureVersion
            ),
            installationBoundary: GoogleAccountConnectionTests.sameInstallationBoundary()
        )

        #expect(adapter.signOutCallCount == 0)
        #expect(
            await eventuallySettlesDisconnected(connection)
        )
    }

    private func eventuallySettlesDisconnected(
        _ connection: GoogleAccountConnection
    ) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while connection.control != .disconnected(connectEnabled: true) {
            if ContinuousClock.now >= deadline {
                return false
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return true
    }
}
