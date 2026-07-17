import Foundation
import Testing
@testable import Planner

@Suite("Google Account Connection Configuration")
struct GoogleAccountConnectionConfigurationTests {
    private static let validClientID =
        "1050123456789-abcdefghijklmnopqrstuvwxyz012345.apps.googleusercontent.com"
    private static let validReversedClientID =
        "com.googleusercontent.apps.1050123456789-abcdefghijklmnopqrstuvwxyz012345"
    private static let validPrivacyPolicyURL = "https://planner.example/privacy"

    private func infoDictionary(
        gate: String? = "YES",
        clientID: String? = Self.validClientID,
        reversedClientID: String? = Self.validReversedClientID,
        privacyPolicyURL: String? = Self.validPrivacyPolicyURL
    ) -> [String: Any] {
        var dictionary: [String: Any] = [:]
        dictionary["PlannerGoogleConnectionEnabled"] = gate
        dictionary["GIDClientID"] = clientID
        dictionary["PlannerGoogleReversedClientID"] = reversedClientID
        dictionary["PlannerPrivacyPolicyURL"] = privacyPolicyURL
        return dictionary
    }

    @Test("A missing release gate leaves the connection addition off")
    func missingGateStaysOff() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(gate: nil)
        )

        #expect(configuration == .gatedOff)
    }

    @Test("The disabled release gate ignores any connection inputs")
    func disabledGateStaysOff() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(gate: "NO")
        )

        #expect(configuration == .gatedOff)
    }

    @Test("The committed app bundle keeps the release gate off")
    func committedBundleStaysOff() {
        #expect(GoogleAccountConnectionConfiguration.load(from: .main) == .gatedOff)
    }

    @Test("An enabled build with complete valid inputs is configured")
    func enabledWithValidInputsIsConfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary()
        )

        guard case .configured(let configured) = configuration else {
            Issue.record("Expected a configured connection, got \(configuration)")
            return
        }
        #expect(configured.clientID == Self.validClientID)
        #expect(configured.reversedClientID == Self.validReversedClientID)
        #expect(configured.privacyPolicyURL.absoluteString == Self.validPrivacyPolicyURL)
    }

    @Test("An enabled build without any inputs is unconfigured")
    func enabledWithoutInputsIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(
                clientID: nil,
                reversedClientID: nil,
                privacyPolicyURL: nil
            )
        )

        #expect(configuration == .unconfigured)
    }

    @Test("An enabled build with empty inputs is unconfigured")
    func enabledWithEmptyInputsIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(
                clientID: "",
                reversedClientID: "",
                privacyPolicyURL: ""
            )
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A client ID outside Google's hosted suffix is unconfigured")
    func clientIDWithWrongSuffixIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(clientID: "planner.example.com")
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A client ID without a project-local prefix is unconfigured")
    func clientIDWithoutPrefixIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(
                clientID: ".apps.googleusercontent.com",
                reversedClientID: "com.googleusercontent.apps."
            )
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A reversed callback scheme that does not match the client ID is unconfigured")
    func mismatchedReversedClientIDIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(
                reversedClientID: "com.example.apps.1050123456789-abcdefghijklmnopqrstuvwxyz012345"
            )
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A non-HTTPS Privacy Policy URL is unconfigured")
    func nonHTTPSPrivacyPolicyURLIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(
                privacyPolicyURL: "http://planner.example/privacy"
            )
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A malformed Privacy Policy URL is unconfigured")
    func malformedPrivacyPolicyURLIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(privacyPolicyURL: "not a url")
        )

        #expect(configuration == .unconfigured)
    }

    @Test("A Privacy Policy URL without a host is unconfigured")
    func hostlessPrivacyPolicyURLIsUnconfigured() {
        let configuration = GoogleAccountConnectionConfiguration(
            infoDictionary: infoDictionary(privacyPolicyURL: "https:///privacy")
        )

        #expect(configuration == .unconfigured)
    }
}
