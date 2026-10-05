import XCTest

/// The Where pin's finger-scale regression test: launches the app with
/// the Maps-pin harness, opens the Event Detail Popover, and asserts that
/// a fingertip-sized tap on the pin opens the Google Maps search URL.
/// The pin's visible glyph is ~11×17pt; a fingertip contact is ~44pt, so
/// the test pins the 44pt minimum hit target and taps with realistic
/// offset from the glyph's center. Red when the pin cannot be hit by a
/// finger — the defect where tapping the pin did nothing because the
/// SwiftUI `Link`'s target was the bare symbol's frame.
final class EventDetailMapsPinUITests: XCTestCase {
    @MainActor
    func testTappingMapsPinDispatchesGoogleMapsSearchURL() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-eventDetailMapsPinHarness"]
        app.launch()

        let open = app.buttons["Show Event Detail"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()

        let pin = app.buttons["Open in Google Maps"]
        XCTAssertTrue(
            pin.waitForExistence(timeout: 10),
            "The Where pin must expose its accessibility element"
        )
        XCTAssertGreaterThanOrEqual(
            min(pin.frame.width, pin.frame.height),
            44,
            "The Where pin's hit target is \(pin.frame.width)×"
                + "\(pin.frame.height)pt; a fingertip (~44pt) cannot land "
                + "in it reliably"
        )

        // A finger aiming at the pin lands within a few points of the
        // glyph; a finger-sized hit target still catches this tap.
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 8, dy: 0))
            .tap()

        let record = app.staticTexts["openURL-record"]
        XCTAssertTrue(
            record.waitForExistence(timeout: 10),
            "The openURL recorder must exist"
        )
        let expected = "OPENED:https://www.google.com/maps/search/"
            + "?api=1&query=Studio%204%2C%20King%20Street%2C%20Copenhagen"
        XCTAssertEqual(
            record.label,
            expected,
            "Tapping the pin must open the Maps URL"
        )
    }
}
