import SwiftUI

/// The Event Detail Popover's optional Attachments section projection.
/// Absence hides the whole section; a present value carries the heading and
/// every row in Google order.
struct IOSEventDetailAttachmentSection: Equatable, Sendable {
    let title: String
    let rows: [IOSEventDetailAttachmentRow]
}

/// One attachment row as the Event Detail Popover exposes it to SwiftUI and
/// accessibility. The destination controls whether the row is a native Link;
/// a missing URL leaves the same title as plain text.
struct IOSEventDetailAttachmentRow: Equatable, Sendable {
    let title: String
    let systemImageName: String
    let destination: URL?
    let accessibilityLabel: String

    init(attachment: CalendarEventAttachment) {
        title = attachment.title
        systemImageName = Self.systemImageName(for: attachment.mimeType)
        destination = attachment.fileURL.flatMap { URL(string: $0) }
        accessibilityLabel = attachment.title
    }

    private static func systemImageName(for mimeType: String?) -> String {
        let mimeType = mimeType?.lowercased() ?? ""
        if mimeType.hasPrefix("image/") {
            return "photo"
        }
        if mimeType == "application/pdf" {
            return "doc.richtext"
        }
        if mimeType.contains("spreadsheet")
            || mimeType.contains("excel")
            || mimeType.contains("sheet")
            || mimeType.contains("csv")
        {
            return "tablecells"
        }
        if mimeType.contains("presentation")
            || mimeType.contains("powerpoint")
            || mimeType.contains("slideshow")
        {
            return "rectangle.on.rectangle"
        }
        if mimeType.hasPrefix("text/")
            || mimeType.contains("document")
            || mimeType.contains("wordprocessing")
            || mimeType.contains("msword")
            || mimeType.contains("rtf")
        {
            return "doc.text"
        }
        return "paperclip"
    }
}

/// The Event Detail Popover's whole-field copy targets: the full strings the
/// title, timing line, Where, and attendee labels display. Long-press Copy
/// and the VoiceOver Copy action copy exactly these, so values the popover
/// does not show (an attendee's email, a response status, a Maps URL) are
/// never copied. Notes select by range instead, and headings, statuses,
/// the Source Calendar row, attachments, and links are not copy targets.
struct IOSEventDetailCopyableFields: Equatable, Sendable {
    let title: String
    let timing: String
    let location: String?
    let attendeeLabels: [String]
}

/// The Event Detail Popover on the iOS Calendar Surface (Planning
/// glossary; iOS ADR 0005): a transient, read-only, native anchored
/// popover presenting one Calendar Event's details, adapting to a sheet
/// on compact widths. It renders from the Calendar Events model's selected
/// canonical identity projection, so successful replacement updates it and
/// disappearance or Disconnect on This Device dismisses it. The title, timing
/// line, Where, and attendee labels copy as whole fields, and Notes selects
/// by range. The surface stays write-read-only: no edit affordances exist.
struct IOSEventDetailPopover: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The selected event's model-published canonical detail projection.
    let detail: CalendarEventDetail

    /// The winning Source Calendar for the selected canonical occurrence,
    /// presented as a subdued source row so source identity never relies
    /// on color alone. `nil` omits the row (deterministic previews).
    let sourceCalendar: GoogleSourceCalendar?

    /// Closes the popover: the small close affordance's action.
    let onClose: () -> Void

    init(
        detail: CalendarEventDetail,
        sourceCalendar: GoogleSourceCalendar? = nil,
        onClose: @escaping () -> Void
    ) {
        self.detail = detail
        self.sourceCalendar = sourceCalendar
        self.onClose = onClose
    }

    var body: some View {
        let copyable = Self.copyableFields(for: detail)
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

                        Text(copyable.title)
                            .font(.headline)
                            .foregroundStyle(PlannerPalette.ink)
                            .eventDetailCopyable(copyable.title)
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

                    if let sourceCalendar {
                        // The subdued source row: the winning Source
                        // Calendar's color and summary as text, so source
                        // identity is available without relying on color
                        // alone.
                        HStack(spacing: 8) {
                            Circle()
                                .fill(
                                    Color(
                                        eventHex: sourceCalendar
                                            .backgroundColorHex
                                    )
                                )
                                .frame(width: 10, height: 10)
                                .overlay {
                                    Circle()
                                        .strokeBorder(
                                            PlannerPalette.separator,
                                            lineWidth: 0.5
                                        )
                                }
                            Text(Self.sourceSummary(sourceCalendar))
                                .font(.footnote)
                                .foregroundStyle(PlannerPalette.monthText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .accessibilityElement(children: .combine)
                    }

                    IOSEventDetailPopoverSection(title: Self.whenSectionTitle) {
                        Text(copyable.timing)
                            .font(.subheadline)
                            .foregroundStyle(PlannerPalette.ink)
                            .eventDetailCopyable(copyable.timing)
                    }

                    if let location = copyable.location {
                        IOSEventDetailPopoverSection(title: Self.whereSectionTitle) {
                            IOSEventDetailLocationText(location: location)
                        }
                    }

                    if let notes = detail.notes {
                        IOSEventDetailPopoverSection(title: Self.notesSectionTitle) {
                            // Range-selectable plain text with tappable
                            // http(s) URLs; long notes scroll within the
                            // section.
                            IOSEventDetailNotesText(
                                notes: notes,
                                maxHeight: Self.notesMaxHeight
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let attachments = Self.attachmentSection(
                        for: detail.attachments
                    ) {
                        IOSEventDetailPopoverSection(title: attachments.title) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(
                                    Array(attachments.rows.enumerated()),
                                    id: \.offset
                                ) { _, row in
                                    IOSEventDetailAttachmentRowView(row: row)
                                }
                            }
                        }
                    }

                    if !detail.attendees.isEmpty {
                        IOSEventDetailPopoverSection(title: Self.attendeesSectionTitle) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(
                                    Array(detail.attendees.enumerated()),
                                    id: \.offset
                                ) { index, attendee in
                                    let label = copyable.attendeeLabels[index]
                                    HStack(alignment: .firstTextBaseline) {
                                        // A truncated label still copies
                                        // in full.
                                        Text(label)
                                            .font(.subheadline)
                                            .foregroundStyle(PlannerPalette.ink)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .eventDetailCopyable(label)
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

    /// The popover's whole-field copy projection. The view renders these
    /// fields from it, so tests pin exactly what each field displays and
    /// copies.
    static func copyableFields(
        for detail: CalendarEventDetail
    ) -> IOSEventDetailCopyableFields {
        IOSEventDetailCopyableFields(
            title: detail.title,
            timing: detail.timingText,
            location: detail.location,
            attendeeLabels: detail.attendees.map(\.label)
        )
    }

    /// The popover's observable Attachments section projection. Tests pin
    /// this seam rather than private MIME or view-construction helpers.
    static func attachmentSection(
        for attachments: [CalendarEventAttachment]
    ) -> IOSEventDetailAttachmentSection? {
        guard !attachments.isEmpty else {
            return nil
        }
        return IOSEventDetailAttachmentSection(
            title: attachmentsSectionTitle,
            rows: attachments.map {
                IOSEventDetailAttachmentRow(attachment: $0)
            }
        )
    }

    private static let closeAccessibilityLabel = "Close"
    private static let whenSectionTitle = "When"
    private static let whereSectionTitle = "Where"
    private static let notesSectionTitle = "Notes"
    private static let attachmentsSectionTitle = "Attachments"
    private static let attendeesSectionTitle = "Attendees"
    private static let openInGoogleCalendarTitle = "Open in Google Calendar →"

    /// The source row's summary: a blank Google summary never presents as
    /// empty text or a calendar ID.
    private static func sourceSummary(
        _ sourceCalendar: GoogleSourceCalendar
    ) -> String {
        let trimmed = sourceCalendar.summary.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return trimmed.isEmpty
            ? SourceCalendarsCopy.untitledCalendar
            : trimmed
    }

    /// The Notes section's height cap, the web popover's 10-rem cap.
    static let notesMaxHeight: CGFloat = 160

    /// The VoiceOver action name on every whole-field copy target.
    static let copyAccessibilityActionName = "Copy"
}

extension View {
    /// Whole-field copy for one Event Detail Popover field: long-press
    /// offers the system edit-menu Copy for the field's full visible string,
    /// even when the line is truncated, and VoiceOver gets a Copy action for
    /// the same string. Values the field does not show are never copied.
    func eventDetailCopyable(_ text: String) -> some View {
        textSelection(.enabled)
            .accessibilityAction(
                named: Text(IOSEventDetailPopover.copyAccessibilityActionName)
            ) {
                UIPasteboard.general.string = text
            }
    }
}

/// One Calendar Event Attachment row. Linked rows use SwiftUI's native Link,
/// while rows without a destination remain plain text. The icon is decorative;
/// VoiceOver announces the same single-line title visible on screen and the
/// Link supplies its native link trait.
private struct IOSEventDetailAttachmentRowView: View {
    let row: IOSEventDetailAttachmentRow

    var body: some View {
        if let destination = row.destination {
            Link(destination: destination) {
                content(isLinked: true)
            }
            .accessibilityLabel(row.accessibilityLabel)
        } else {
            content(isLinked: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
        }
    }

    private func content(isLinked: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: row.systemImageName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PlannerPalette.monthText)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(row.title)
                .font(.subheadline)
                .foregroundStyle(PlannerPalette.ink)
                .underline(isLinked)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The Where line as an actionable link, presentation-only: the location
/// data model stays a plain string, persisting only inside Stored
/// Calendar Events (iOS ADR 0007). A place
/// or address string renders as text with a Google Maps search link on
/// the pin affordance; a location that is itself an http(s) URL renders
/// as a direct link. Mirrors the Web Experience's location-links module.
/// The location text copies as a whole field in every form.
private struct IOSEventDetailLocationText: View {
    let location: String

    var body: some View {
        let href = CalendarEventLocationLinks.href(for: location)
        if case let .some(.direct(url)) = href {
            // A link run inside Text rather than a SwiftUI Link: long-
            // pressing a Link opens its URL, while a link run still opens
            // on tap and leaves long-press to Copy.
            Text(Self.directLink(location, url: url))
                .font(.subheadline)
                .eventDetailCopyable(location)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .eventDetailCopyable(location)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // An unbuildable Maps URL degrades to plain text rather than
            // a dead link.
            Text(location)
                .font(.subheadline)
                .foregroundStyle(PlannerPalette.ink)
                .eventDetailCopyable(location)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let mapsAccessibilityLabel = "Open in Google Maps"

    private static func directLink(_ location: String, url: URL) -> AttributedString {
        var link = AttributedString(location)
        link.link = url
        link.foregroundColor = PlannerPalette.link
        link.underlineStyle = .single
        return link
    }
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

#Preview("Attachments · Linked and Plain") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Quarterly Planning",
            colorHex: "#039BE5",
            timingText: "Wed, Jul 22, 2026 · 1:00 PM – 2:00 PM",
            notes: "Review before the meeting.",
            attachments: [
                CalendarEventAttachment(
                    title: "Roadmap.pdf",
                    mimeType: "application/pdf",
                    fileURL: "https://drive.google.com/file/d/roadmap"
                ),
                CalendarEventAttachment(
                    title: "Untitled attachment",
                    mimeType: "application/vnd.google-apps.spreadsheet",
                    fileURL: nil
                ),
            ],
            attendees: [
                CalendarEventAttendee(
                    label: "Ada Lovelace",
                    status: .accepted
                ),
            ]
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
