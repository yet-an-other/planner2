import SwiftUI

/// The header collision policy as pure layout math, separated for
/// deterministic tests.
///
/// The trailing account control must collapse before the Visible Month is
/// forced below its accepted minimum behavior, and the centered month must
/// never overlap leading or trailing controls. The control's measured
/// footprint — including its margins — reserves symmetric space around the
/// center, so a wider control shrinks the month's width cap instead of
/// colliding with it.
enum HeaderCollisionLayout {
    /// The width each side of the title row reserves by default for the
    /// Product Name and an optional account control, keeping the Visible
    /// Month geometrically centered and clear of both.
    static let minimumSideReservation: CGFloat = 144

    /// The Visible Month's accepted minimum footprint: the width it keeps
    /// at its minimum scale across supported locales before truncation is
    /// allowed to begin.
    static let visibleMonthMinimumFootprint: CGFloat = 120

    /// The widest control the header offers at a given total width.
    ///
    /// The control (plus its margins) may grow until the month would drop
    /// below its minimum footprint; beyond that it must collapse to a
    /// narrower form. The cap keeps even wide layouts from crowding the
    /// center.
    static func accountControlBudget(in width: CGFloat) -> CGFloat {
        max(
            44,
            min(
                (width - visibleMonthMinimumFootprint) / 2 - 32,
                280
            )
        )
    }

    /// The Visible Month's width cap given the control's measured
    /// footprint: symmetric reservation around the center, growing beyond
    /// the default side reservation only when the control is wider, and
    /// never below the floor where scaling and truncation take over.
    static func visibleMonthMaxWidth(
        in width: CGFloat,
        controlFootprint: CGFloat
    ) -> CGFloat {
        max(
            24,
            width - 2 * max(minimumSideReservation, controlFootprint)
        )
    }
}

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
    @State private var accountControlWidth = HeaderCollisionLayout.minimumSideReservation

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
                        maxWidth: HeaderCollisionLayout.accountControlBudget(
                            in: geometry.size.width
                        ),
                        alignment: .trailing
                    )
                    .padding(.horizontal, 16)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.width
                    } action: { measuredWidth in
                        accountControlWidth = measuredWidth
                    }
            }
        }
        .frame(height: 64)
        .background(PlannerPalette.canvas)
    }

    /// The Visible Month keeps its accepted minimum behavior while leading
    /// and trailing controls stay clear: the reservation grows symmetrically
    /// only when the mounted account control needs more than the default
    /// side reservation, so the month remains centered and never overlaps.
    private func visibleMonthMaxWidth(in width: CGFloat) -> CGFloat {
        HeaderCollisionLayout.visibleMonthMaxWidth(
            in: width,
            controlFootprint: accountControlWidth
        )
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
