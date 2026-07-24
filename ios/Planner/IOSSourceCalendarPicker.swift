import SwiftUI

/// The native iOS Source Calendar Picker happy path: one immediately-applied
/// list plus Done. Live-list recovery, bulk actions, duplicate labels, and
/// advanced accessibility behavior are delivered by the follow-up slices.
struct IOSSourceCalendarPicker: View {
    let sourceCalendars: [GoogleSourceCalendar]
    let selectedSourceCalendarIDs: Set<String>
    let minimumSelectionMessage: String?
    let toggle: (String) -> Void
    let done: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(sourceCalendars, id: \.id) { sourceCalendar in
                    Button {
                        toggle(sourceCalendar.id)
                    } label: {
                        sourceCalendarRow(sourceCalendar)
                    }
                    .buttonStyle(.plain)
                }

                if let minimumSelectionMessage {
                    Text(minimumSelectionMessage)
                        .font(.footnote)
                        .foregroundStyle(PlannerPalette.statusWarning)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
        .frame(idealWidth: 360, idealHeight: 440)
    }

    private func sourceCalendarRow(
        _ sourceCalendar: GoogleSourceCalendar
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(eventHex: sourceCalendar.backgroundColorHex))
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .strokeBorder(PlannerPalette.separator, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(sourceCalendar.summary)
                    .foregroundStyle(PlannerPalette.ink)
                    .lineLimit(2)

                if sourceCalendar.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .foregroundStyle(PlannerPalette.monthText)
                }
            }

            Spacer(minLength: 8)

            if selectedSourceCalendarIDs.contains(sourceCalendar.id) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PlannerPalette.olive)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

#if DEBUG
private let sourceCalendarPickerPreviewSources = [
    GoogleSourceCalendar(
        id: "primary",
        summary: "Personal",
        backgroundColorHex: "#039BE5",
        isPrimary: true
    ),
    GoogleSourceCalendar(
        id: "family",
        summary: "Family and shared plans",
        backgroundColorHex: "#7CB342",
        isPrimary: false
    ),
    GoogleSourceCalendar(
        id: "work",
        summary: "Work",
        backgroundColorHex: "#7986CB",
        isPrimary: false
    ),
]

#Preview("Source Calendar Picker · Compact") {
    IOSSourceCalendarPicker(
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary", "family"],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Regular · Minimum One") {
    IOSSourceCalendarPicker(
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary"],
        minimumSelectionMessage: SourceCalendarsCopy.minimumSelection,
        toggle: { _ in },
        done: {}
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 360, height: 440)
}
#endif
