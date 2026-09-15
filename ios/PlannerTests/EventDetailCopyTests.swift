import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Planner

/// Copying text from the Event Detail Popover (issue #113). Whole-field copy
/// is pinned through the popover's copy projection, fed by real Calendar
/// Event Normalization so the strings are exactly what the popover shows.
/// Notes range selection is pinned on the UIKit text view itself: its
/// read-only, detector-free configuration, http(s)-only links, Select All,
/// selection across refreshes, and the height cap.
@Suite("Event Detail Copy")
@MainActor
struct EventDetailCopyTests {
    private static let primary = GoogleSourceCalendar(
        id: "primary@example.com",
        summary: "Primary",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    )

    private static let environment: CalendarEnvironment = {
        guard let timeZone = TimeZone(secondsFromGMT: 0) else {
            preconditionFailure("GMT must be available for deterministic tests")
        }
        return CalendarEnvironment(
            now: Date(timeIntervalSince1970: 1_784_116_800),
            calendar: Calendar(identifier: .gregorian),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone
        )
    }()

    private static let defaultStyle = IOSEventDetailNotesStyle(
        contentSizeCategory: .large,
        layoutDirection: .leftToRight
    )

    /// Normalizes one Google event from 9:00 to 10:00 on 2026-07-15 and
    /// returns the popover's copy projection for it.
    private static func copyableFields(
        summary: String?,
        location: String? = nil,
        attendees: [GoogleCalendarEventAttendee] = []
    ) throws -> IOSEventDetailCopyableFields {
        let start = Date(timeIntervalSince1970: 1_784_106_000)
        let events = CalendarEventNormalization.normalize(
            [
                GoogleSourceCalendarEvent(
                    sourceCalendar: primary,
                    event: GoogleCalendarEvent(
                        id: "copy",
                        summary: summary,
                        start: .timed(start),
                        end: .timed(start.addingTimeInterval(3_600)),
                        isCancelled: false,
                        isDeclinedByViewer: false,
                        location: location,
                        attendees: attendees
                    )
                ),
            ],
            eventColorBackgrounds: [:],
            environment: environment
        )
        let event = try #require(events.first)
        return IOSEventDetailPopover.copyableFields(for: event.detail)
    }

    private static func presentedNotesView(
        _ notes: String,
        style: IOSEventDetailNotesStyle = defaultStyle
    ) -> IOSEventDetailNotesTextView {
        let textView = IOSEventDetailNotesTextView()
        textView.present(notes: notes, style: style)
        return textView
    }

    /// The substrings carrying a link attribute and their destinations.
    private static func links(
        in textView: UITextView
    ) -> [(text: String, url: URL?)] {
        var links: [(text: String, url: URL?)] = []
        let text = textView.attributedText ?? NSAttributedString()
        text.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: text.length)
        ) { value, range, _ in
            guard let value else { return }
            links.append(
                (
                    (text.string as NSString).substring(with: range),
                    value as? URL
                )
            )
        }
        return links
    }

    // MARK: Whole-field copy

    @Test("A blank title copies as the Busy title the popover shows")
    func blankTitleCopiesBusy() throws {
        let fields = try Self.copyableFields(summary: "   ")

        #expect(fields.title == "Busy")
    }

    @Test("The title and timing line copy exactly as displayed")
    func titleAndTimingCopyAsDisplayed() throws {
        let fields = try Self.copyableFields(summary: "  Design Review  ")

        #expect(fields.title == "Design Review")
        // Foundation separates the time from its period with a narrow
        // no-break space.
        #expect(
            fields.timing == "Wed, Jul 15, 2026 · 9:00\u{202F}AM – 10:00\u{202F}AM"
        )
    }

    @Test("A URL location copies as the URL string, a place as its text")
    func locationCopiesVisibleString() throws {
        let url = try Self.copyableFields(
            summary: "Call",
            location: "https://meet.example.com/room"
        )
        let place = try Self.copyableFields(
            summary: "Visit",
            location: "  Studio 4, King Street  "
        )
        let none = try Self.copyableFields(summary: "Focus")

        #expect(url.location == "https://meet.example.com/room")
        // Never the Google Maps search URL behind the pin.
        #expect(place.location == "Studio 4, King Street")
        #expect(none.location == nil)
    }

    @Test("Attendee labels copy in full and never the hidden email or status")
    func attendeeLabelsCopyVisibleText() throws {
        let longName =
            "Ada Augusta King, Countess of Lovelace and First Programmer"
        let fields = try Self.copyableFields(
            summary: "All Hands",
            attendees: [
                GoogleCalendarEventAttendee(
                    displayName: longName,
                    email: "ada@example.com",
                    responseStatus: "accepted"
                ),
                GoogleCalendarEventAttendee(
                    displayName: nil,
                    email: "grace@example.com",
                    responseStatus: "declined"
                ),
            ]
        )

        #expect(fields.attendeeLabels == [longName, "grace@example.com"])
    }

    // MARK: Notes range selection

    @Test("Notes are selectable, never editable, with no data detectors")
    func notesTextViewConfiguration() {
        let textView = Self.presentedNotesView(
            "Call +1 555 0100 on Friday at 1 Infinite Loop"
        )

        #expect(textView.isSelectable)
        #expect(!textView.isEditable)
        #expect(textView.dataDetectorTypes.isEmpty)
        #expect(textView.text == "Call +1 555 0100 on Friday at 1 Infinite Loop")
        #expect(Self.links(in: textView).isEmpty)
    }

    @Test("Only http(s) URLs in Notes carry links")
    func notesLinkOnlyHTTPURLs() {
        let textView = Self.presentedNotesView(
            "Agenda https://example.com/agenda and ftp://example.com and (http://example.com/b)"
        )

        let links = Self.links(in: textView)
        #expect(
            links.map(\.text) == [
                "https://example.com/agenda",
                "http://example.com/b",
            ]
        )
        #expect(
            links.map(\.url) == [
                URL(string: "https://example.com/agenda"),
                URL(string: "http://example.com/b"),
            ]
        )
    }

    @Test("Notes offer Select All until the whole note is selected")
    func notesOfferSelectAll() {
        let textView = Self.presentedNotesView("Bring snacks & water.")
        let selectAll = #selector(UIResponder.selectAll(_:))

        #expect(textView.canPerformAction(selectAll, withSender: nil))

        textView.selectedRange = NSRange(location: 0, length: 5)
        #expect(textView.canPerformAction(selectAll, withSender: nil))

        textView.selectedRange = NSRange(
            location: 0,
            length: textView.textStorage.length
        )
        #expect(!textView.canPerformAction(selectAll, withSender: nil))
    }

    @Test("A refresh with unchanged notes keeps the selection, even when restyled")
    func unchangedNotesKeepSelection() {
        let notes = "Agenda at https://example.com/agenda"
        let textView = Self.presentedNotesView(notes)
        let selection = NSRange(location: 3, length: 6)
        textView.selectedRange = selection

        textView.present(notes: notes, style: Self.defaultStyle)
        #expect(textView.selectedRange == selection)

        textView.present(
            notes: notes,
            style: IOSEventDetailNotesStyle(
                contentSizeCategory: .accessibilityLarge,
                layoutDirection: .rightToLeft
            )
        )
        #expect(textView.selectedRange == selection)
    }

    @Test("A refresh that changes the notes clears the selection")
    func changedNotesClearSelection() {
        let textView = Self.presentedNotesView("Original agenda")
        textView.selectedRange = NSRange(location: 0, length: 8)

        textView.present(notes: "Updated agenda", style: Self.defaultStyle)

        #expect(textView.text == "Updated agenda")
        #expect(textView.selectedRange.length == 0)
    }

    @Test("Notes follow Dynamic Type and align to the layout direction")
    func notesFollowDynamicTypeAndLayoutDirection() throws {
        let regular = IOSEventDetailNotesTextView.attributedNotes(
            "Agenda",
            style: Self.defaultStyle
        )
        let accessible = IOSEventDetailNotesTextView.attributedNotes(
            "Agenda",
            style: IOSEventDetailNotesStyle(
                contentSizeCategory: .accessibilityExtraLarge,
                layoutDirection: .rightToLeft
            )
        )

        let regularFont = try #require(
            regular.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        let accessibleFont = try #require(
            accessible.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        #expect(accessibleFont.pointSize > regularFont.pointSize)

        let regularParagraph = try #require(
            regular.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        )
        let accessibleParagraph = try #require(
            accessible.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                as? NSParagraphStyle
        )
        #expect(regularParagraph.alignment == .left)
        #expect(accessibleParagraph.alignment == .right)
    }

    @Test("Short notes size to fit and long notes stop at the section cap")
    func notesHeightStopsAtCap() {
        let cap = IOSEventDetailPopover.notesMaxHeight
        let short = Self.presentedNotesView("Bring snacks & water.")
        let long = Self.presentedNotesView(
            (1...40).map { "Agenda line \($0)" }.joined(separator: "\n")
        )

        let shortHeight = short.fittingHeight(forWidth: 320, maxHeight: cap)
        #expect(shortHeight > 0)
        #expect(shortHeight < cap)
        #expect(long.fittingHeight(forWidth: 320, maxHeight: cap) == cap)
    }
}
