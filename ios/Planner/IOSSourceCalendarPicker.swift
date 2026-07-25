import SwiftUI

/// The native iOS Source Calendar Picker: one immediately-applied list plus
/// Done, a compact actions menu with Select All and Reset to Primary,
/// opening-refresh loading, a recoverable Planner-owned error state with an
/// explicit Retry, and the distinct no-available-sources state. Rows
/// announce summary, Primary marker, checked state, and duplicate
/// disambiguation without relying on color; text follows native Dynamic
/// Type through the largest accessibility sizes. The first release has no
/// search.
struct IOSSourceCalendarPicker: View {
    let content: SourceCalendarPickerContent
    let rows: [SourceCalendarPickerRow]
    let minimumSelectionMessage: String?
    let toggle: (String) -> Void
    let selectAll: () -> Void
    let resetToPrimary: () -> Void
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
                    if rows.isEmpty {
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
                if case .ready = content, !rows.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Menu {
                            Button(
                                SourceCalendarsCopy.selectAll,
                                action: selectAll
                            )
                            Button(
                                SourceCalendarsCopy.resetToPrimary,
                                action: resetToPrimary
                            )
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel(SourceCalendarsCopy.actionsMenu)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
        .frame(idealWidth: 360, idealHeight: 440)
    }

    private var sourceCalendarList: some View {
        List {
            ForEach(rows) { row in
                Button {
                    toggle(row.id)
                } label: {
                    sourceCalendarRow(row)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(rowAccessibilityLabel(row))
                .accessibilityAddTraits(
                    row.isSelected ? .isSelected : []
                )
            }

            if let minimumSelectionMessage {
                Text(minimumSelectionMessage)
                    .font(.footnote)
                    .foregroundStyle(PlannerPalette.statusWarning)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        // VoiceOver announces why the final selected row was not
        // deselected as soon as the explanation appears.
        .onChange(of: minimumSelectionMessage != nil) { _, presented in
            if presented, let minimumSelectionMessage {
                AccessibilityNotification.Announcement(minimumSelectionMessage)
                    .post()
            }
        }
    }

    /// The row's spoken label: the disambiguated summary plus the Primary
    /// marker where applicable; the checked state travels through the
    /// `.isSelected` trait, and the color dot stays silent.
    private func rowAccessibilityLabel(
        _ row: SourceCalendarPickerRow
    ) -> String {
        row.isPrimary
            ? "\(row.summary), \(SourceCalendarsCopy.primaryMarker)"
            : row.summary
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
        _ row: SourceCalendarPickerRow
    ) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(eventHex: row.backgroundColorHex))
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .strokeBorder(PlannerPalette.separator, lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.summary)
                    .foregroundStyle(PlannerPalette.ink)
                    .lineLimit(2)

                if row.isPrimary {
                    Text(SourceCalendarsCopy.primaryMarker)
                        .font(.caption)
                        .foregroundStyle(PlannerPalette.monthText)
                }
            }

            Spacer(minLength: 8)

            if row.isSelected {
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
private func sourceCalendarPickerPreviewRow(
    id: String,
    summary: String,
    backgroundColorHex: String,
    isPrimary: Bool = false,
    isSelected: Bool = false
) -> SourceCalendarPickerRow {
    SourceCalendarPickerRow(
        id: id,
        summary: summary,
        backgroundColorHex: backgroundColorHex,
        isPrimary: isPrimary,
        isSelected: isSelected
    )
}

private let sourceCalendarPickerPreviewRows = [
    sourceCalendarPickerPreviewRow(
        id: "primary",
        summary: "Personal",
        backgroundColorHex: "#039BE5",
        isPrimary: true,
        isSelected: true
    ),
    sourceCalendarPickerPreviewRow(
        id: "family",
        summary: "Family and shared plans",
        backgroundColorHex: "#7CB342",
        isSelected: true
    ),
    sourceCalendarPickerPreviewRow(
        id: "work",
        summary: "Work",
        backgroundColorHex: "#7986CB"
    ),
]

#Preview("Source Calendar Picker · Compact") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: sourceCalendarPickerPreviewRows,
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Regular · Minimum One") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: sourceCalendarPickerPreviewRows.map {
            SourceCalendarPickerRow(
                id: $0.id,
                summary: $0.summary,
                backgroundColorHex: $0.backgroundColorHex,
                isPrimary: $0.isPrimary,
                isSelected: $0.id == "primary"
            )
        },
        minimumSelectionMessage: SourceCalendarsCopy.minimumSelection,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .regular)
    .frame(width: 360, height: 440)
}

#Preview("Source Calendar Picker · Loading") {
    IOSSourceCalendarPicker(
        content: .loading,
        rows: sourceCalendarPickerPreviewRows,
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Error") {
    IOSSourceCalendarPicker(
        content: .unavailable(.failed),
        rows: sourceCalendarPickerPreviewRows,
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · No Available Calendars") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: [],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Duplicate and Blank Summaries") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: [
            sourceCalendarPickerPreviewRow(
                id: "primary",
                summary: "Work",
                backgroundColorHex: "#039BE5",
                isPrimary: true,
                isSelected: true
            ),
            sourceCalendarPickerPreviewRow(
                id: "second",
                summary: "Work (2)",
                backgroundColorHex: "#7CB342",
                isSelected: true
            ),
            sourceCalendarPickerPreviewRow(
                id: "blank",
                summary: "Untitled calendar",
                backgroundColorHex: "#7986CB"
            ),
            sourceCalendarPickerPreviewRow(
                id: "blank-2",
                summary: "Untitled calendar (2)",
                backgroundColorHex: "#D50000"
            ),
        ],
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Many Calendars · Accessibility Text") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: (1...24).map { index in
            sourceCalendarPickerPreviewRow(
                id: "source-\(index)",
                summary: index == 1
                    ? "A Source Calendar with a Deliberately Long Summary \(index)"
                    : "Source Calendar \(index)",
                backgroundColorHex: "#039BE5",
                isPrimary: index == 1,
                isSelected: index <= 3
            )
        },
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .dynamicTypeSize(.accessibility3)
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}

#Preview("Source Calendar Picker · Right to Left") {
    IOSSourceCalendarPicker(
        content: .ready,
        rows: sourceCalendarPickerPreviewRows,
        minimumSelectionMessage: nil,
        toggle: { _ in },
        selectAll: {},
        resetToPrimary: {},
        retry: {},
        done: {}
    )
    .environment(\.layoutDirection, .rightToLeft)
    .environment(\.horizontalSizeClass, .compact)
    .frame(width: 393, height: 700)
}
#endif
