import Foundation

/// The build-time release gate and environment-specific build inputs for the
/// iOS Google Account Connection.
///
/// The release gate is fixed at build time through the
/// `PlannerGoogleConnectionEnabled` Info.plist value, substituted from the
/// `PLANNER_GOOGLE_CONNECTION_ENABLED` build setting. While the gate is off,
/// the app initializes no connection behavior and mounts neither the iOS
/// Account Control nor the iOS Header Status, leaving the accepted 100-point
/// iOS Calendar Header unchanged.
///
/// While the gate is on, the iOS OAuth client ID, reversed callback scheme,
/// and HTTPS Privacy Policy URL arrive as environment-specific build settings
/// substituted into the app bundle. Missing or invalid values yield
/// ``unconfigured`` so the iOS Calendar Surface stays usable with Connect
/// disabled. No client secret key exists here or in the bundle: an installed
/// app cannot keep a secret, so none is accepted or embedded.
enum GoogleAccountConnectionConfiguration: Equatable, Sendable {
    /// The build-time release gate is off.
    case gatedOff

    /// The gate is on, but the OAuth client ID, reversed callback scheme, or
    /// HTTPS Privacy Policy URL is missing or invalid.
    case unconfigured

    /// The gate is on with a complete, valid configuration.
    case configured(Configured)

    /// The validated environment-specific build inputs.
    struct Configured: Equatable, Sendable {
        /// The iOS OAuth client ID, also published as `GIDClientID` for the
        /// Google Sign-In SDK.
        let clientID: String

        /// The reversed client ID registered as the OAuth callback URL scheme.
        let reversedClientID: String

        /// The HTTPS Privacy Policy URL presented before the first Connect.
        let privacyPolicyURL: URL
    }

    /// Info.plist keys substituted from environment-specific build settings.
    private enum InfoKey {
        static let gate = "PlannerGoogleConnectionEnabled"
        static let clientID = "GIDClientID"
        static let reversedClientID = "PlannerGoogleReversedClientID"
        static let privacyPolicyURL = "PlannerPrivacyPolicyURL"
    }

    /// Loads the configuration from a bundle's Info dictionary.
    static func load(from bundle: Bundle) -> GoogleAccountConnectionConfiguration {
        GoogleAccountConnectionConfiguration(
            infoDictionary: bundle.infoDictionary ?? [:]
        )
    }

    /// Builds the configuration from raw Info dictionary values.
    init(infoDictionary: [String: Any]) {
        guard (infoDictionary[InfoKey.gate] as? String) == "YES" else {
            self = .gatedOff
            return
        }

        let clientID = (infoDictionary[InfoKey.clientID] as? String) ?? ""
        let reversedClientID =
            (infoDictionary[InfoKey.reversedClientID] as? String) ?? ""
        let privacyPolicyURLString =
            (infoDictionary[InfoKey.privacyPolicyURL] as? String) ?? ""

        guard
            Self.isValidClientID(clientID),
            reversedClientID == Self.expectedReversedClientID(for: clientID),
            let privacyPolicyURL = URL(string: privacyPolicyURLString),
            privacyPolicyURL.scheme == "https",
            let host = privacyPolicyURL.host(),
            !host.isEmpty
        else {
            self = .unconfigured
            return
        }

        self = .configured(
            Configured(
                clientID: clientID,
                reversedClientID: reversedClientID,
                privacyPolicyURL: privacyPolicyURL
            )
        )
    }

    /// A Google OAuth client ID ends in `.apps.googleusercontent.com` with a
    /// non-empty project-local prefix.
    private static func isValidClientID(_ clientID: String) -> Bool {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else {
            return false
        }
        return !clientID.dropLast(suffix.count).isEmpty
    }

    /// Google derives the callback scheme by reversing the client ID's dotted
    /// components, so a mismatch means the build inputs do not belong
    /// together.
    private static func expectedReversedClientID(for clientID: String) -> String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }
}

/// Planner-owned English copy for Google Account Connection presentation.
///
/// Raw Google errors never reach the iOS Header Status; connection outcomes
/// map to this stable copy instead.
enum GoogleAccountConnectionCopy {
    /// Shown when the gate is on but the build inputs are missing or invalid.
    static let unconfigured = "Google connection is not configured"
}
