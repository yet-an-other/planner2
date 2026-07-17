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
/// When both seams are left at their default, the header renders neither and
/// keeps its accepted 64-point title row plus 36-point weekday row: the
/// account-control overlay and the header-status row contribute nothing when
/// they are empty, so today's event-free header is unchanged.
struct IOSCalendarHeader<AccountControl: View, HeaderStatus: View>: View {
    @FocusState private var visibleMonthFocused: Bool
    @State private var visibleMonthHovered = false

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
                .overlay(alignment: .trailing) {
                    accountControl
                        .padding(.horizontal, 16)
                }

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
                            maxWidth: max(24, geometry.size.width - 288)
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
        }
        .frame(height: 64)
        .background(PlannerPalette.canvas)
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
