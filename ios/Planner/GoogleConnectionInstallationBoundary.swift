import Foundation
import Security

/// The non-migrating device-marker store behind the installation boundary.
///
/// Production confines a generic-password Keychain item to this device;
/// tests keep it in memory. The marker is a random identifier — never
/// account identity, tokens, scopes, or Calendar data.
protocol GoogleConnectionDeviceMarkerStore {
    /// The current device marker, or `nil` when none is stored.
    func marker() -> String?

    /// Stores the device marker, replacing any previous value.
    func setMarker(_ marker: String)
}

/// The installation boundary behind the Google Account Connection.
///
/// A connection belongs to one Planner installation on one physical device.
/// Two markers establish that boundary without containing any account data:
///
/// - an **install-local marker** in user defaults — created per
///   installation, deleted by uninstall, and carried along by backups; and
/// - a **device marker** in the Keychain with this-device-only
///   accessibility — never migrated to other hardware by a backup, and
///   potentially surviving uninstall.
///
/// Correlating them distinguishes the cases: markers present, matching, and
/// well-formed mean an ordinary relaunch or app update; a missing
/// install-local marker means a fresh (re-)installation; and a present
/// install-local marker without its matching device marker means a backup
/// arrived on different hardware. Every anomaly is repaired with a freshly
/// generated pair, so partial or corrupted marker state always fails safe:
/// the previous installation's connection is cleared rather than trusted.
struct GoogleConnectionInstallationBoundary {
    /// The evaluated installation status.
    enum Installation: Equatable {
        /// The markers match: an ordinary relaunch or app update.
        case same

        /// No install-local marker exists: a first or repeated installation.
        case fresh

        /// An install-local marker exists without its matching device
        /// marker: a backup migrated to different hardware, or the marker
        /// state is partial or corrupted.
        case migrated
    }

    /// The user-defaults key of the install-local marker.
    static let installMarkerKey = "PlannerInstallationMarker"

    private let defaults: UserDefaults
    private let deviceMarkerStore: any GoogleConnectionDeviceMarkerStore

    init(
        defaults: UserDefaults,
        deviceMarkerStore: any GoogleConnectionDeviceMarkerStore
    ) {
        self.defaults = defaults
        self.deviceMarkerStore = deviceMarkerStore
    }

    /// Evaluates the markers, repairs them for the current installation,
    /// and reports the installation status. When the result is not
    /// ``Installation/same``, the caller must clear any stale Google
    /// Sign-In state before restoring.
    @discardableResult
    func establish() -> Installation {
        let installMarker = defaults.string(forKey: Self.installMarkerKey)
        let deviceMarker = deviceMarkerStore.marker()

        if let installMarker,
           installMarker == deviceMarker,
           Self.isWellFormed(installMarker)
        {
            return .same
        }

        regenerateMarkers()
        return installMarker == nil ? .fresh : .migrated
    }

    /// Replaces both markers with one freshly generated installation
    /// identity, so the current installation owns the boundary from here.
    private func regenerateMarkers() {
        let marker = UUID().uuidString
        defaults.set(marker, forKey: Self.installMarkerKey)
        deviceMarkerStore.setMarker(marker)
    }

    /// A well-formed marker is a UUID string exactly as generated; anything
    /// else is corruption and cannot establish an installation.
    private static func isWellFormed(_ marker: String) -> Bool {
        UUID(uuidString: marker) != nil
    }
}

/// The production device-marker store: a generic-password Keychain item
/// with this-device-only accessibility, so the marker never migrates via
/// backup and stays readable after first unlock.
struct KeychainGoogleConnectionDeviceMarkerStore: GoogleConnectionDeviceMarkerStore {
    private let service = "com.yetanother.planner.installation"
    private let account = "device-marker"

    func marker() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard
            SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
            let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func setMarker(_ marker: String) {
        let data = Data(marker.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
