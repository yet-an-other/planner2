import SwiftUI

/// The Event Detail Popover on the iOS Calendar Surface (Planning
/// glossary; iOS ADR 0005): a transient, read-only, native anchored
/// popover presenting one Calendar Event's details, adapting to a sheet
/// on compact widths. It renders from the Calendar Events model's selected
/// canonical identity projection, so successful replacement updates it and
/// disappearance or Disconnect on This Device dismisses it. The surface stays
/// write-read-only: no edit affordances exist.
struct IOSEventDetailPopover: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The selected event's model-published canonical detail projection.
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
                            .padding(.top, 8)
                            .padding(.bottom, 8)

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
                                        Text(attendee.status.displayText)
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
        .frame(maxWidth: Self.contentMaxWidth(for: horizontalSizeClass))
        .background(PlannerPalette.canvas)
        // A native anchored popover on regular widths, a sheet on
        // compact ones; outside tap, the close affordance, and the
        // platform gesture all dismiss. Match the sheet chrome to the
        // content so no system-white gutters show around compact content.
        .presentationCompactAdaptation(.sheet)
        .presentationBackground(PlannerPalette.canvas)
        .presentationDetents(Self.compactDetents)
    }

    /// The web popover's maximum width, kept so the two experiences read
    /// alike.
    private static let maxWidth: CGFloat = 360

    static func contentMaxWidth(
        for horizontalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat? {
        horizontalSizeClass == .compact ? .infinity : maxWidth
    }

    /// Compact sheets open at half height for ordinary event detail and remain
    /// user-expandable when long notes or attendee lists need more room.
    static let compactDetents: Set<PresentationDetent> = [.medium, .large]

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
                .font(.system(size: 14, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(PlannerPalette.monthText)
                .padding(.bottom, 4)
            content.padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
/// Deterministic SwiftUI validation for issue #90. The same harness runs at
/// compact and regular widths; choosing an outcome keeps the native popover
/// open with the reconciled edit/move/failure detail or dismisses it for
/// deletion, decline, and Disconnect on This Device. Observable model tests
/// separately drive these outcomes through real bounded replacement.
private struct EventDetailRefreshValidationPreview: View {
    enum Outcome: String, CaseIterable, Identifiable {
        case edit = "Edit"
        case move = "Move"
        case deletion = "Deletion"
        case decline = "Decline"
        case failure = "Failure"
        case disconnect = "Disconnect"

        var id: Self { self }

        /// The successful canonical replacement for this outcome. Failure has
        /// no replacement at all: the harness deliberately retains whichever
        /// detail was open before it, matching stale-while-revalidate.
        var replacementDetail: CalendarEventDetail? {
            switch self {
            case .edit:
                CalendarEventDetail(
                    title: "Updated Design Review",
                    colorHex: "#D50000",
                    timingText: "Wed, Jul 22, 2026 · 2:00 PM – 3:30 PM",
                    location: "Studio 5",
                    googleLink: "https://www.google.com/calendar/event?eid=updated",
                    notes: "Updated agenda at https://example.com/agenda",
                    attendees: [
                        CalendarEventAttendee(
                            label: "Ada Lovelace",
                            status: .accepted
                        ),
                    ]
                )
            case .move:
                CalendarEventDetail(
                    title: "Design Review",
                    colorHex: "#039BE5",
                    timingText: "Thu, Jul 23, 2026 · 11:00 AM – 12:00 PM",
                    location: "Studio 4",
                    googleLink: "https://www.google.com/calendar/event?eid=moved"
                )
            case .deletion, .decline, .failure, .disconnect:
                nil
            }
        }

        var dismissesSelection: Bool {
            switch self {
            case .deletion, .decline, .disconnect:
                true
            case .edit, .move, .failure:
                false
            }
        }
    }

    @State private var outcome = Outcome.edit
    @State private var presentedDetail = Outcome.edit.replacementDetail
    @State private var isPresenting = true

    var body: some View {
        VStack(spacing: 16) {
            Picker("Refresh outcome", selection: $outcome) {
                ForEach(Outcome.allCases) { outcome in
                    Text(outcome.rawValue).tag(outcome)
                }
            }
            .pickerStyle(.segmented)

            Text(
                presentedDetail == nil
                    ? "Expected: Event Detail Popover dismissed"
                    : "Expected: Event Detail Popover remains open"
            )
                .font(.footnote)
                .foregroundStyle(PlannerPalette.monthText)

            Button("Reset open selected Calendar Event") {
                presentedDetail = Self.originalDetail
                isPresenting = true
            }
        }
        .padding()
        .background(PlannerPalette.canvas)
        .onChange(of: outcome) { _, outcome in
            if outcome.dismissesSelection {
                presentedDetail = nil
            } else if let replacementDetail = outcome.replacementDetail {
                presentedDetail = replacementDetail
            }
            // Failure intentionally leaves both the selected identity's
            // existing detail and presentation unchanged.
            isPresenting = presentedDetail != nil
        }
        .popover(
            isPresented: Binding(
                get: { isPresenting && presentedDetail != nil },
                set: { isPresenting = $0 }
            )
        ) {
            if let detail = presentedDetail {
                IOSEventDetailPopover(detail: detail) {
                    isPresenting = false
                }
            }
        }
    }

    private static let originalDetail = CalendarEventDetail(
        title: "Design Review",
        colorHex: "#039BE5",
        timingText: "Wed, Jul 22, 2026 · 1:00 PM – 2:00 PM",
        location: "Studio 4",
        googleLink: "https://www.google.com/calendar/event?eid=original"
    )
}

#Preview("Refresh Reconciliation · Compact") {
    EventDetailRefreshValidationPreview()
        .environment(\.horizontalSizeClass, .compact)
        .frame(width: 393, height: 852)
}

#Preview("Refresh Reconciliation · Regular") {
    EventDetailRefreshValidationPreview()
        .environment(\.horizontalSizeClass, .regular)
        .frame(width: 834, height: 1_194)
}

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
