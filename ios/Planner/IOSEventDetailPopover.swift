import SwiftUI

/// The Event Detail Popover on the iOS Calendar Surface (Planning
/// glossary; iOS ADR 0005): a transient, read-only, native anchored
/// popover presenting one Calendar Event's details, adapting to a sheet
/// on compact widths. It renders entirely from the model-published
/// payload the tapped Calendar Event Bar or Calendar Event Row carries,
/// so Disconnect on This Device dismisses it as a consequence of clearing
/// events. The surface stays write-read-only: no edit affordances exist.
struct IOSEventDetailPopover: View {
    /// The tapped event's model-published presentation payload.
    let detail: CalendarEventDetail

    /// Closes the popover: the small close affordance's action.
    let onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        // The Event Color accent: the same event the user
                        // tapped, read at a glance (the Web Experience's
                        // leading stripe).
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(eventHex: detail.colorHex))
                            .frame(width: 4)

                        Text(detail.title)
                            .font(.headline)
                            .foregroundStyle(PlannerPalette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PlannerPalette.olive)
                                .padding(6)
                        }
                        .accessibilityLabel(Self.closeAccessibilityLabel)
                    }

                    IOSEventDetailPopoverSection(title: Self.whenSectionTitle) {
                        Text(detail.timingText)
                            .font(.subheadline)
                            .foregroundStyle(PlannerPalette.ink)
                    }

                    if let location = detail.location {
                        IOSEventDetailPopoverSection(title: Self.whereSectionTitle) {
                            IOSEventDetailLocationText(location: location)
                        }
                    }

                    if let notes = detail.notes {
                        IOSEventDetailPopoverSection(title: Self.notesSectionTitle) {
                            // Plain text with tappable http(s) URLs;
                            // long notes scroll within the section.
                            ScrollView {
                                Text(Self.linkedNotes(notes))
                                    .font(.subheadline)
                                    .foregroundStyle(PlannerPalette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: Self.notesMaxHeight)
                        }
                    }

                    if !detail.attendees.isEmpty {
                        IOSEventDetailPopoverSection(title: Self.attendeesSectionTitle) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(
                                    Array(detail.attendees.enumerated()),
                                    id: \.offset
                                ) { _, attendee in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(attendee.label)
                                            .font(.subheadline)
                                            .foregroundStyle(PlannerPalette.ink)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer(minLength: 8)
                                        // The response status as text,
                                        // never color alone.
                                        Text(attendee.status.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(PlannerPalette.monthText)
                                    }
                                }
                                if detail.hiddenAttendeeCount > 0 {
                                    Text("+\(detail.hiddenAttendeeCount) more")
                                        .font(.caption)
                                        .foregroundStyle(PlannerPalette.monthText)
                                }
                            }
                        }
                    }
                }
                .padding(16)

                if let googleLink = detail.googleLink,
                   let url = URL(string: googleLink)
                {
                    Rectangle()
                        .fill(PlannerPalette.separator)
                        .frame(height: 1)

                    Link(destination: url) {
                        Text(Self.openInGoogleCalendarTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(PlannerPalette.ink)
                            .underline()
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: Self.maxWidth)
        .background(PlannerPalette.canvas)
        // A native anchored popover on regular widths, a sheet on
        // compact ones; outside tap, the close affordance, and the
        // platform gesture all dismiss.
        .presentationCompactAdaptation(.sheet)
    }

    /// The web popover's maximum width, kept so the two experiences read
    /// alike; compact sheet widths stretch within it.
    private static let maxWidth: CGFloat = 360

    private static let closeAccessibilityLabel = "Close"
    private static let whenSectionTitle = "When"
    private static let whereSectionTitle = "Where"
    private static let notesSectionTitle = "Notes"
    private static let attendeesSectionTitle = "Attendees"
    private static let openInGoogleCalendarTitle = "Open in Google Calendar →"

    /// The Notes section's height cap, the web popover's 10-rem cap.
    private static let notesMaxHeight: CGFloat = 160

    /// Renders the pinned, presentation-only text/link segments into one
    /// attributed string. The view owns only styling and the native link
    /// attribute; URL boundary behavior lives in the pure helper.
    private static func linkedNotes(_ notes: String) -> AttributedString {
        CalendarEventTextLinks.splitIntoSegments(notes).reduce(
            into: AttributedString()
        ) { result, segment in
            switch segment {
            case .text(let text):
                result.append(AttributedString(text))
            case .link(let urlText):
                var attributedLink = AttributedString(urlText)
                if let url = URL(string: urlText) {
                    attributedLink.link = url
                    attributedLink.foregroundColor = PlannerPalette.link
                    attributedLink.underlineStyle = .single
                }
                result.append(attributedLink)
            }
        }
    }
}

/// The Where line as an actionable link, presentation-only: the location
/// data model stays a plain string (memory-only, iOS ADR 0003). A place
/// or address string renders as text with a Google Maps search link on
/// the pin affordance; a location that is itself an http(s) URL renders
/// as a direct link. Mirrors the Web Experience's location-links module.
private struct IOSEventDetailLocationText: View {
    let location: String

    var body: some View {
        let href = CalendarEventLocationLinks.href(for: location)
        if case let .some(.direct(url)) = href {
            Link(destination: url) {
                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(PlannerPalette.link)
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if case let .some(.maps(url)) = href {
            HStack(alignment: .top, spacing: 6) {
                Link(destination: url) {
                    Image(systemName: "mappin")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PlannerPalette.link)
                        .padding(.top, 2)
                }
                .accessibilityLabel(Self.mapsAccessibilityLabel)

                Text(location)
                    .font(.subheadline)
                    .foregroundStyle(PlannerPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // An unbuildable Maps URL degrades to plain text rather than
            // a dead link.
            Text(location)
                .font(.subheadline)
                .foregroundStyle(PlannerPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let mapsAccessibilityLabel = "Open in Google Maps"
}

/// One labelled section of the Event Detail Popover: a small uppercase
/// muted heading above its content, mirroring the Web Experience's
/// section rhythm.
private struct IOSEventDetailPopoverSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(PlannerPalette.monthText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Where and Google Link · iPhone Sheet") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Design Review",
            colorHex: "#039BE5",
            timingText: "Wed, Jul 22, 2026 · 1:00 PM – 2:00 PM",
            location: "Studio 4, King Street, Copenhagen",
            googleLink: "https://www.google.com/calendar/event?eid=abc123"
        ),
        onClose: {}
    )
    .frame(width: 393, height: 320)
}

#Preview("URL Location · iPad") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Team Offsite — Summer Edition with a Deliberately Long Title",
            colorHex: "#5484ED",
            timingText: "All day · Jul 14, 2026 – Jul 16, 2026",
            location: "https://meet.example.com/offsite-room",
            googleLink: "https://www.google.com/calendar/event?eid=def456"
        ),
        onClose: {}
    )
    .frame(width: 360, height: 320)
}

#Preview("Long Notes") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Planning Offsite",
            colorHex: "#D50000",
            timingText: "Thu, Jul 23, 2026 · 9:00 AM – 5:00 PM",
            location: "Harbor House",
            googleLink: "https://www.google.com/calendar/event?eid=ghi789",
            notes: "Agenda and logistics at https://example.com/offsite-agenda.\n\n09:00 — Arrival and coffee\n09:30 — Retrospective on the spring release\n11:00 — Roadmap workshop, part one\n12:30 — Lunch at the harbor\n13:30 — Roadmap workshop, part two\n15:00 — Break\n15:30 — Unconference sessions\n16:45 — Wrap-up and next steps"
        ),
        onClose: {}
    )
    .frame(width: 360, height: 420)
}

#Preview("Minimal · No Optional Sections") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Dentist",
            colorHex: "#33B679",
            timingText: "All day · Wed, Jul 22, 2026"
        ),
        onClose: {}
    )
    .frame(width: 360, height: 240)
}

#Preview("Attendees · +N more") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "All Hands",
            colorHex: "#8E24AA",
            timingText: "Wed, Jul 22, 2026 · 4:00 PM – 5:00 PM",
            googleLink: "https://www.google.com/calendar/event?eid=jkl012",
            attendees: [
                CalendarEventAttendee(label: "Ada Lovelace", status: .accepted),
                CalendarEventAttendee(label: "grace@example.com", status: .declined),
                CalendarEventAttendee(label: "Alan Turing", status: .tentative),
                CalendarEventAttendee(label: "Edsger Dijkstra", status: .invited),
                CalendarEventAttendee(label: "Katherine Johnson", status: .unknown),
            ],
            hiddenAttendeeCount: 3
        ),
        onClose: {}
    )
    .frame(width: 360, height: 340)
}

#Preview("Right to Left") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "مراجعة التصميم",
            colorHex: "#039BE5",
            timingText: "All day · Wed, Jul 22, 2026",
            location: "شارع الملك، الاستوديو ٤",
            googleLink: "https://www.google.com/calendar/event?eid=abc123"
        ),
        onClose: {}
    )
    .environment(\.layoutDirection, .rightToLeft)
    .frame(width: 360, height: 320)
}
#endif
