import Foundation

/// The Product Version displayed beneath the Product Name in the iOS
/// Calendar Header, composed from the bundle's marketing version and build
/// number. Pure formatting rules, separated from the bundle so they are
/// deterministic to test; the composition mirrors the web Product Version's
/// digit-leading `v`-prefix rule.
enum ProductVersion {
    /// The displayed identifier: `v1.0.1` with marketing version and
    /// build number, `v1.0` when the build number is absent, and `nil` —
    /// the header hides the version — when the marketing version is absent.
    /// Never a bare build number. Empty values behave as absent.
    static func display(
        marketingVersion: String?,
        buildNumber: String?
    ) -> String? {
        guard let marketingVersion, !marketingVersion.isEmpty else {
            return nil
        }

        // ASCII digits only, mirroring the web rule's `/^\d/`: a version
        // leading with a non-ASCII numeral gets no prefix on either
        // platform.
        let startsWithDigit = marketingVersion.first.map {
            $0.isASCII && $0.isNumber
        } ?? false
        let prefixed = startsWithDigit
            ? "v\(marketingVersion)"
            : marketingVersion

        guard let buildNumber, !buildNumber.isEmpty else {
            return prefixed
        }
        return "\(prefixed).\(buildNumber)"
    }

    /// The Product Version composed from the app's own bundle, or `nil`
    /// when the bundle provides no marketing version.
    static var current: String? {
        display(
            marketingVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String,
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String
        )
    }
}
