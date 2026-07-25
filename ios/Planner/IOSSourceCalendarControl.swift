import SwiftUI

/// The compact, connected-only iOS Source Calendar Control. Its stable
/// calendar glyph carries no visual count badge — VoiceOver announces the
/// selected count instead — and keeps a 44-point native activation target
/// in every presentation.
struct IOSSourceCalendarControl: View {
    let presentation: SourceCalendarControlPresentation
    let presentPicker: () -> Void

    @FocusState private var focused: Bool
    @State private var hovered = false

    var body: some View {
        Button(action: presentPicker) {
            Group {
                if presentation == .loading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "calendar")
                        .font(.system(size: 17, weight: .semibold))
                }
            }
            .foregroundStyle(PlannerPalette.olive)
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(Color.white.opacity(0.8))
                    .overlay {
                        Circle()
                            .strokeBorder(
                                focused || hovered
                                    ? PlannerPalette.olive
                                    : PlannerPalette.separator,
                                lineWidth: focused || hovered ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .focused($focused)
        .onHover { hovered = $0 }
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .hoverEffect()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isEnabled: Bool {
        if case .ready = presentation {
            return true
        }
        return false
    }

    /// The glyph carries no visual count badge; VoiceOver announces the
    /// selected count instead, for example “Choose calendars, 3 selected.”
    private var accessibilityLabel: String {
        if case .ready(let selectedCount) = presentation {
            return SourceCalendarsCopy.controlAccessibilityLabel(
                selectedCount: selectedCount
            )
        }
        return "Choose calendars"
    }
}
