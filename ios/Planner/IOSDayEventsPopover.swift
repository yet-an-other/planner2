import SwiftUI

/// The Day Events Popover on the iOS Calendar Surface (Planning
/// glossary): a transient, read-only overlay listing every Calendar Event
/// attributed to one Date Cell — visible and hidden alike — summoned
/// from the cell's Events Overflow marker. It renders the model's
/// summoned-day selection: Calendar Event Bars in lane order, then
/// Calendar Event Rows by start time ascending, under a date heading
/// naming the Date Cell. Presentation mirrors the iOS Event Detail
/// Popover — a native anchored popover on regular widths adapting to a
/// sheet on compact ones — and dismissal is native. The list is
/// read-only: no create, edit, or delete affordances exist.
struct IOSDayEventsPopover: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The summoned Date Cell's complete ordered day, projected by the
    /// Calendar Events model when the Events Overflow marker summoned it.
    let selection: CalendarEventDaySelection

    /// Closes the popover: the small close affordance's action.
    let onClose: () -> Void

    init(
        selection: CalendarEventDaySelection,
        onClose: @escaping () -> Void
    ) {
        self.selection = selection
        self.onClose = onClose
    }

    var body: some View {
        // Dense days scroll within the popover; the list never grows past
        // the presentation's own bounds.
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(selection.heading)
                        .font(.headline)
                        .foregroundStyle(PlannerPalette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PlannerPalette.olive)
                            .padding(6)
                    }
                    .accessibilityLabel(Self.closeAccessibilityLabel)
                }

                ForEach(selection.items) { item in
                    switch item {
                    case .bar(let bar):
                        IOSDayEventBarItemView(bar: bar)
                    case .row(let row):
                        IOSDayEventRowItemView(row: row)
                    }
                }
            }
            .padding(16)
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

    /// The Event Detail Popover's maximum width, kept so the two overlays
    /// read alike.
    private static let maxWidth: CGFloat = 360

    static func contentMaxWidth(
        for horizontalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat? {
        horizontalSizeClass == .compact ? .infinity : maxWidth
    }

    /// Compact sheets open at half height and can expand to full height,
    /// mirroring the Event Detail Popover's detent policy.
    static let compactDetents: Set<PresentationDetent> = [.medium, .large]

    private static let closeAccessibilityLabel = "Close"
}

/// A Calendar Event Bar in the day list: the cell's bar visual language —
/// a colored bar with its title in the contrast-safe tone.
private struct IOSDayEventBarItemView: View {
    let bar: CalendarEventDayItem.Bar

    var body: some View {
        Text(bar.title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(
                bar.textTone == .dark ? PlannerPalette.ink : Color.white
            )
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(eventHex: bar.colorHex),
                in: RoundedRectangle(cornerRadius: 3)
            )
    }
}

/// A Calendar Event Row in the day list: the cell's row visual language —
/// an Event Color dot, the localized start time, and the title.
private struct IOSDayEventRowItemView: View {
    let row: CalendarEventDayItem.Row

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(eventHex: row.colorHex))
                .frame(width: 7, height: 7)
            Text(row.startTimeText)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(PlannerPalette.ink)
                .fixedSize()
            Text(row.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(PlannerPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
/// A deterministic summoned day for the popover previews.
private func previewDaySelection(
    heading: String,
    items: [CalendarEventDayItem]
) -> CalendarEventDaySelection {
    CalendarEventDaySelection(
        date: Date(timeIntervalSince1970: 1_784_070_000),
        heading: heading,
        items: items
    )
}

/// A dense Thursday: stacked all-day bars beyond the visible cap plus a
/// full run of intraday rows.
private let previewDenseDayItems: [CalendarEventDayItem] = [
    .bar(
        CalendarEventDayItem.Bar(
            id: "bar-1",
            title: "Team Offsite",
            colorHex: "#5484ED",
            textTone: .light
        )
    ),
    .bar(
        CalendarEventDayItem.Bar(
            id: "bar-2",
            title: "Design Conference",
            colorHex: "#A4BDFC",
            textTone: .dark
        )
    ),
    .bar(
        CalendarEventDayItem.Bar(
            id: "bar-3",
            title: "Hackathon",
            colorHex: "#D50000",
            textTone: .light
        )
    ),
    .bar(
        CalendarEventDayItem.Bar(
            id: "bar-4",
            title: "School Holiday",
            colorHex: "#7CB342",
            textTone: .dark
        )
    ),
    .bar(
        CalendarEventDayItem.Bar(
            id: "bar-5",
            title: "Conference Setup",
            colorHex: "#8E24AA",
            textTone: .light
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-1",
            title: "Breakfast",
            startTimeText: "8:00 AM",
            colorHex: "#039BE5"
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-2",
            title: "Standup",
            startTimeText: "9:30 AM",
            colorHex: "#039BE5"
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-3",
            title: "Pairing",
            startTimeText: "1:00 PM",
            colorHex: "#33B679"
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-4",
            title: "Demo",
            startTimeText: "3:00 PM",
            colorHex: "#F4511E"
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-5",
            title: "Retro",
            startTimeText: "4:30 PM",
            colorHex: "#039BE5"
        )
    ),
    .row(
        CalendarEventDayItem.Row(
            id: "row-6",
            title: "Dinner with the Design Chapter",
            startTimeText: "7:00 PM",
            colorHex: "#D50000"
        )
    ),
]

#Preview("Dense Day · Compact") {
    IOSDayEventsPopover(
        selection: previewDaySelection(
            heading: "Thursday, July 16",
            items: previewDenseDayItems
        ),
        onClose: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 500)
}

#Preview("Dense Day · Wide") {
    IOSDayEventsPopover(
        selection: previewDaySelection(
            heading: "Thursday, July 16",
            items: previewDenseDayItems
        ),
        onClose: {}
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 360, height: 500)
}

#Preview("Sparse Day · Wide") {
    IOSDayEventsPopover(
        selection: previewDaySelection(
            heading: "Wednesday, July 15",
            items: [
                .bar(
                    CalendarEventDayItem.Bar(
                        id: "bar-1",
                        title: "Team Offsite",
                        colorHex: "#5484ED",
                        textTone: .light
                    )
                ),
                .row(
                    CalendarEventDayItem.Row(
                        id: "row-1",
                        title: "Design Review",
                        startTimeText: "1:00 PM",
                        colorHex: "#039BE5"
                    )
                ),
            ]
        ),
        onClose: {}
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 360, height: 220)
}

#Preview("Right to Left") {
    IOSDayEventsPopover(
        selection: previewDaySelection(
            heading: "الخميس، ١٦ يوليو",
            items: [
                .bar(
                    CalendarEventDayItem.Bar(
                        id: "bar-1",
                        title: "رحلة الفريق",
                        colorHex: "#5484ED",
                        textTone: .light
                    )
                ),
                .row(
                    CalendarEventDayItem.Row(
                        id: "row-1",
                        title: "مراجعة التصميم",
                        startTimeText: "1:00 PM",
                        colorHex: "#039BE5"
                    )
                ),
            ]
        ),
        onClose: {}
    )
    .environment(\.layoutDirection, .rightToLeft)
    .frame(width: 360, height: 240)
}
#endif
