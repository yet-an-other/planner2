import SwiftUI

/// The non-scrolling area above the iOS Calendar Surface.
///
/// The header owns the Product Name on the leading side, the geometrically
/// centered Visible Month (which acts as a Today Jump), and the Monday-first
/// weekday labels. Two optional content seams — `accountControl` and
/// `headerStatus` — let future work mount an iOS Account Control and iOS
/// Header Status through the header rather than accumulating authentication
/// or status behavior inside the Calendar Screen.
///
/// A mounted account control stays clear of the centered Visible Month: the
/// header bounds the control so it collapses before the month is forced
/// below its accepted minimum behavior, measures the mounted control, and
/// shrinks the month's width cap symmetrically when the control needs more
/// than the default side reservation.
///
/// When both seams are left at their default, the header renders neither and
/// keeps its accepted 64-point title row plus 36-point weekday row: the
/// account-control overlay and the header-status row contribute nothing when
/// they are empty, so today's event-free header is unchanged.
struct IOSCalendarHeader<AccountControl: View, HeaderStatus: View>: View {
    @FocusState private var visibleMonthFocused: Bool
    @State private var visibleMonthHovered = false
    @State private var accountControlWidth = HeaderLayout.minimumSideReservation

    let visibleMonth: String
    let weekdayLabels: [WeekdayLabel]
    let onJumpToToday: () -> Void
    @ViewBuilder var accountControl: AccountControl
    @ViewBuilder var headerStatus: HeaderStatus

    init(
        visibleMonth: String,
        weekdayLabels: [WeekdayLabel],
        onJumpToToday: @escaping () -> Void,
        @ViewBuilder accountControl: () -> AccountControl = { EmptyView() },
        @ViewBuilder headerStatus: () -> HeaderStatus = { EmptyView() }
    ) {
        self.visibleMonth = visibleMonth
        self.weekdayLabels = weekdayLabels
        self.onJumpToToday = onJumpToToday
        self.accountControl = accountControl()
        self.headerStatus = headerStatus()
    }

    var body: some View {
        VStack(spacing: 0) {
            titleRow

            headerStatus

            weekdayRow
        }
    }

    private var titleRow: some View {
        GeometryReader { geometry in
            ZStack {
                Text("Planner")
                    .font(.title.bold())
                    .foregroundStyle(PlannerPalette.olive)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .leading
                    )
                    .padding(.horizontal, 16)

                Button(action: onJumpToToday) {
                    Text(visibleMonth)
                        .font(.headline.bold())
                        .foregroundStyle(PlannerPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .frame(
                            maxWidth: visibleMonthMaxWidth(
                                in: geometry.size.width
                            )
                        )
                }
                .buttonStyle(
                    VisibleMonthButtonStyle(
                        emphasized: visibleMonthFocused || visibleMonthHovered
                    )
                )
                .focused($visibleMonthFocused)
                .onHover { visibleMonthHovered = $0 }
            }
            .overlay(alignment: .trailing) {
                accountControl
                    .frame(
                        maxWidth: accountControlBudget(in: geometry.size.width),
                        alignment: .trailing
                    )
                    .padding(.horizontal, 16)
                    .background {
                        GeometryReader { controlGeometry in
                            Color.clear.preference(
                                key: AccountControlWidthKey.self,
                                value: controlGeometry.size.width
                            )
                        }
                    }
            }
        }
        .frame(height: 64)
        .background(PlannerPalette.canvas)
        .onPreferenceChange(AccountControlWidthKey.self) { width in
            accountControlWidth = width
        }
    }

    /// The Visible Month keeps its accepted minimum behavior while leading
    /// and trailing controls stay clear: the reservation grows symmetrically
    /// only when the mounted account control needs more than the default
    /// side reservation, so the month remains centered and never overlaps.
    private func visibleMonthMaxWidth(in width: CGFloat) -> CGFloat {
        max(
            24,
            width - 2 * max(HeaderLayout.minimumSideReservation, accountControlWidth)
        )
    }

    /// The account control may use up to half the row beyond the Visible
    /// Month's minimum footprint and the trailing margin, so it collapses to
    /// its compact form before the month is forced below its minimum
    /// behavior. The cap keeps Google's expanding wide form from crowding
    /// the center on wide layouts.
    private func accountControlBudget(in width: CGFloat) -> CGFloat {
        max(44, min(width / 2 - 28, 280))
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(weekdayLabels) { label in
                Text(label.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(PlannerPalette.monthText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if label.isWeekend {
                            PlannerPalette.weekendStrip
                        }
                    }
            }
        }
        .frame(height: 36)
        .background(PlannerPalette.weekdayStrip)
    }
}

/// Layout constants for the iOS Calendar Header.
private enum HeaderLayout {
    /// The width each side of the title row reserves by default for the
    /// Product Name and an optional account control, keeping the Visible
    /// Month geometrically centered and clear of both.
    static let minimumSideReservation: CGFloat = 144
}

private struct AccountControlWidthKey: PreferenceKey {
    static let defaultValue = HeaderLayout.minimumSideReservation

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct VisibleMonthButtonStyle: ButtonStyle {
    let emphasized: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background {
                Capsule()
                    .fill(PlannerPalette.emphasizedControl)
                    .opacity(configuration.isPressed || emphasized ? 1 : 0)
            }
            .contentShape(Capsule())
    }
}
