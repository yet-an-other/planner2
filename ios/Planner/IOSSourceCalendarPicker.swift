import SwiftUI

/// The native iOS Source Calendar Picker: one immediately-applied list plus
/// Done, with opening-refresh loading, a recoverable Planner-owned error
/// state with an explicit Retry, and the distinct no-available-sources
/// state. Bulk actions, duplicate labels, and advanced accessibility
/// behavior are delivered by the follow-up slice.
struct IOSSourceCalendarPicker: View {
    let content: SourceCalendarPickerContent
    let sourceCalendars: [GoogleSourceCalendar]
    let selectedSourceCalendarIDs: Set<String>
    let minimumSelectionMessage: String?
    let toggle: (String) -> Void
    let retry: () -> Void
    let done: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch content {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .unavailable(let failure):
                    VStack(spacing: 12) {
                        Text(message(for: failure))
                            .font(.footnote)
                            .foregroundStyle(PlannerPalette.statusError)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isStaticText)
                        Button(SourceCalendarsCopy.retry, action: retry)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .ready:
                    if sourceCalendars.isEmpty {
                        Text(SourceCalendarsCopy.noAvailable)
                            .font(.footnote)
                            .foregroundStyle(PlannerPalette.monthText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityAddTraits(.isStaticText)
                    } else {
                        sourceCalendarList
                    }
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

    private var sourceCalendarList: some View {
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
    }

    private func message(
        for failure: GoogleSourceCalendarsFailure
    ) -> String {
        switch failure {
        case .offline:
            return SourceCalendarsCopy.offline
        case .failed:
            return SourceCalendarsCopy.failed
        }
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
        content: .ready,
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary", "family"],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Regular · Minimum One") {
    IOSSourceCalendarPicker(
        content: .ready,
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary"],
        minimumSelectionMessage: SourceCalendarsCopy.minimumSelection,
        toggle: { _ in },
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 360, height: 440)
}

#Preview("Source Calendar Picker · Loading") {
    IOSSourceCalendarPicker(
        content: .loading,
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary"],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Error") {
    IOSSourceCalendarPicker(
        content: .unavailable(.failed),
        sourceCalendars: sourceCalendarPickerPreviewSources,
        selectedSourceCalendarIDs: ["primary"],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · No Available Calendars") {
    IOSSourceCalendarPicker(
        content: .ready,
        sourceCalendars: [],
        selectedSourceCalendarIDs: [],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}
#endif
