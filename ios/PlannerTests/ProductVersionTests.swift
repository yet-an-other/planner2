import Foundation
import Testing
@testable import Planner

@Suite("Product Version")
struct ProductVersionTests {
    @Test("Marketing version and build number compose the full identifier")
    func fullIdentifier() {
        #expect(
            ProductVersion.display(
                marketingVersion: "1.0",
                buildNumber: "1"
            ) == "v1.0.1"
        )
    }

    @Test("The v-prefix applies only when the marketing version starts with a digit")
    func prefixRule() {
        #expect(
            ProductVersion.display(
                marketingVersion: "2026.1",
                buildNumber: "42"
            ) == "v2026.1.42"
        )
        #expect(
            ProductVersion.display(
                marketingVersion: "beta",
                buildNumber: "3"
            ) == "beta.3"
        )
        // Parity with the web rule's ASCII-only `/^\d/`.
        #expect(
            ProductVersion.display(
                marketingVersion: "٢.0",
                buildNumber: "1"
            ) == "٢.0.1"
        )
    }

    @Test("A missing build number renders the marketing version alone")
    func missingBuild() {
        #expect(
            ProductVersion.display(
                marketingVersion: "1.0",
                buildNumber: nil
            ) == "v1.0"
        )
    }

    @Test("A missing marketing version hides the version entirely")
    func missingMarketing() {
        #expect(
            ProductVersion.display(
                marketingVersion: nil,
                buildNumber: "1"
            ) == nil
        )
        #expect(
            ProductVersion.display(
                marketingVersion: nil,
                buildNumber: nil
            ) == nil
        )
    }

    @Test("Empty values behave as missing")
    func emptyValues() {
        #expect(
            ProductVersion.display(
                marketingVersion: "",
                buildNumber: "1"
            ) == nil
        )
        #expect(
            ProductVersion.display(
                marketingVersion: "1.0",
                buildNumber: ""
            ) == "v1.0"
        )
    }
}
