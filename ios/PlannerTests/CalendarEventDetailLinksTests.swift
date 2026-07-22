import Foundation
import Testing
@testable import Planner

/// Direct pins for the popover's presentation-only linkification: the
/// notes splitter and the location href builder are pure functions, so
/// they are pinned without view-layer tests — the same discipline the
/// Web Experience's text-links and location-links units keep.
@Suite("Event Detail Links")
struct CalendarEventDetailLinksTests {
    // MARK: Notes linkification

    @Test("Text without URLs stays one text segment")
    func plainTextStaysOneSegment() {
        #expect(
            CalendarEventTextLinks.splitIntoSegments("Bring snacks & water.")
                == [.text("Bring snacks & water.")]
        )
    }

    @Test("A URL becomes a link segment between text segments")
    func urlBecomesLinkSegment() {
        #expect(
            CalendarEventTextLinks.splitIntoSegments(
                "See https://example.com/plan now"
            )
                == [
                    .text("See "),
                    .link("https://example.com/plan"),
                    .text(" now"),
                ]
        )
    }

    @Test("URLs stop at whitespace and bracketing characters")
    func urlsStopAtTerminators() {
        #expect(
            CalendarEventTextLinks.splitIntoSegments(
                "(https://example.com/a) and \"https://example.com/b\""
            )
                == [
                    .text("("),
                    .link("https://example.com/a"),
                    .text(") and \""),
                    .link("https://example.com/b"),
                    .text("\""),
                ]
        )
    }

    @Test("Only http(s) schemes linkify")
    func onlyHTTPSchemesLinkify() {
        #expect(
            CalendarEventTextLinks.splitIntoSegments(
                "ftp://example.com and javascript:alert(1)"
            )
                == [.text("ftp://example.com and javascript:alert(1)")]
        )
    }

    @Test("The scheme match is case-insensitive")
    func schemeMatchIsCaseInsensitive() {
        #expect(
            CalendarEventTextLinks.splitIntoSegments("HTTPS://EXAMPLE.COM/x")
                == [.link("HTTPS://EXAMPLE.COM/x")]
        )
    }

    @Test("Empty text yields no segments")
    func emptyTextYieldsNoSegments() {
        #expect(CalendarEventTextLinks.splitIntoSegments("") == [])
    }

    // MARK: Location hrefs

    @Test("A whole-string https URL is a direct link")
    func wholeURLIsDirectLink() {
        #expect(
            CalendarEventLocationLinks.href(
                for: "https://meet.example.com/room"
            )
                == .direct(URL(string: "https://meet.example.com/room")!)
        )
    }

    @Test("An uppercase scheme still counts as a whole URL")
    func uppercaseSchemeIsDirectLink() {
        #expect(
            CalendarEventLocationLinks.href(for: "HTTP://example.com")
                == .direct(URL(string: "HTTP://example.com")!)
        )
    }

    @Test("A place string becomes a Google Maps search, whitespace collapsed")
    func placeStringBecomesMapsSearch() {
        #expect(
            CalendarEventLocationLinks.href(for: "  Studio 4,\nKing Street  ")
                == .maps(
                    URL(
                        string:
                            "https://www.google.com/maps/search/?api=1&query=Studio%204%2C%20King%20Street"
                    )!
                )
        )
    }

    @Test("The Maps query escapes query separators like encodeURIComponent")
    func mapsQueryEscapesSeparators() {
        #expect(
            CalendarEventLocationLinks.href(for: "A & B = C")
                == .maps(
                    URL(
                        string:
                            "https://www.google.com/maps/search/?api=1&query=A%20%26%20B%20%3D%20C"
                    )!
                )
        )
    }

    @Test("Prose containing a URL goes to Maps as a whole string")
    func proseWithURLGoesToMaps() {
        let href = CalendarEventLocationLinks.href(
            for: "Meet at https://example.com later"
        )
        guard case .maps = href else {
            Issue.record("Expected a Maps href, got \(String(describing: href))")
            return
        }
    }
}
