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
            }
            .padding(16)
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
}

/// One labelled section of the Event Detail Popover: a small uppercase
/// muted heading above its content, mirroring the Web Experience's
/// section rhythm.
struct IOSEventDetailPopoverSection<Content: View>: View {
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

private extension Color {
    /// An Event Color from its `#RRGGBB` hex form; unparsable
    /// values fall back to the palette's olive.
    init(eventHex hex: String) {
        guard let color = EventColorRGB(hex: hex) else {
            self = PlannerPalette.olive
            return
        }
        self = Color(
            red: Double(color.red) / 255,
            green: Double(color.green) / 255,
            blue: Double(color.blue) / 255
        )
    }
}

#if DEBUG
#Preview("Full Width · iPhone Sheet") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Design Review",
            colorHex: "#039BE5",
            timingText: "All day · Wed, Jul 22, 2026"
        ),
        onClose: {}
    )
    .frame(width: 393, height: 300)
}

#Preview("Popover Width · iPad") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "Team Offsite — Summer Edition with a Deliberately Long Title",
            colorHex: "#5484ED",
            timingText: "All day · Jul 14, 2026 – Jul 16, 2026"
        ),
        onClose: {}
    )
    .frame(width: 360, height: 300)
}

#Preview("Right to Left") {
    IOSEventDetailPopover(
        detail: CalendarEventDetail(
            title: "مراجعة التصميم",
            colorHex: "#039BE5",
            timingText: "All day · Wed, Jul 22, 2026"
        ),
        onClose: {}
    )
    .environment(\.layoutDirection, .rightToLeft)
    .frame(width: 360, height: 300)
}
#endif
