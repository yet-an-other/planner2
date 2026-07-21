import Foundation
import SwiftUI

struct CalendarScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CalendarGridModel
    @State private var scrollPosition: WeekRow.ID?
    @State private var midnightScheduleGeneration = 0
    @State private var scrollViewportHeight: CGFloat = 0

    private let currentEnvironment: @MainActor () -> CalendarEnvironment
    private let connection: GoogleAccountConnection?
    private let events: CalendarEventsModel?

    init(
        environment: CalendarEnvironment,
        currentEnvironment: @escaping @MainActor () -> CalendarEnvironment,
        connection: GoogleAccountConnection? = nil,
        events: CalendarEventsModel? = nil
    ) {
        let model = CalendarGridModel(environment: environment)
        _model = State(initialValue: model)
        _scrollPosition = State(initialValue: model.todayWeek.id)
        self.currentEnvironment = currentEnvironment
        self.connection = connection
        self.events = events
    }

    var body: some View {
        VStack(spacing: 0) {
            IOSCalendarHeader(
                visibleMonth: model.visibleMonth,
                productVersion: ProductVersion.current,
                weekdayLabels: model.weekdayLabels,
                onJumpToToday: jumpToToday,
                accountControl: { accountControl },
                headerStatus: { headerStatus }
            )

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(model.weekRows) { weekRow in
                        WeekRowView(
                            weekRow: weekRow,
                            eventWeek: events?.layout(forWeekStarting: weekRow.id)
                        )
                    }
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(name: CalendarSurfaceCoordinateSpace.name)
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .onPreferenceChange(WeekRowOffsetsKey.self, perform: updateTopWeek)
            .onGeometryChange(
                for: CGFloat.self,
                of: { $0.size.height }
            ) { height in
                scrollViewportHeight = height
                reportVisibleRange()
            }
            .background(PlannerPalette.grid)
        }
        .background(PlannerPalette.canvas)
        .preferredColorScheme(.light)
        .sheet(item: explanationItem) { explanation in
            IOSConnectionExplanation(
                privacyPolicyURL: explanation.privacyPolicyURL,
                onContinue: { connection?.continueConnect() },
                onCancel: { connection?.cancelConnectExplanation() }
            )
        }
        .environment(
            \.layoutDirection,
            model.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        )
        .task {
            // The events module follows the connection: fetch while
            // connected, clear on Disconnect on This Device. While the gate
            // is off, neither module exists and nothing changes here.
            events?.setConnected(connection?.isConnected ?? false)
        }
        .onChange(of: connection?.control) { _, control in
            events?.setConnected(control?.isConnected ?? false)
        }
        .onChange(of: scenePhase) { _, nextScenePhase in
            midnightScheduleGeneration += 1
            if nextScenePhase == .active {
                refreshCalendarGrid()
                // A foreground refresh asks the module to revalidate the
                // connection; no SDK detail crosses this boundary.
                connection?.validateOnForeground()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange)
        ) { _ in
            handleSystemChange()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
        ) { _ in
            handleSystemChange()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSLocale.currentLocaleDidChangeNotification
            )
        ) { _ in
            handleSystemChange()
        }
        .task(id: midnightScheduleGeneration) {
            await refreshAtNextLocalMidnight()
        }
    }

    /// The iOS Account Control mounted through the header's trailing seam.
    /// While the build-time release gate is off, no connection module exists
    /// and the seam stays empty; the module publishes the presentation for
    /// every other case, including the disabled unconfigured build.
    @ViewBuilder
    private var accountControl: some View {
        if let connection {
            IOSAccountControl(
                presentation: connection.control,
                connect: connection.connect,
                disconnectOnThisDevice: connection.disconnectOnThisDevice
            )
        }
    }

    /// The iOS Header Status mounted through the header's status seam. While
    /// the gate is on, the row always reserves its 20 points so messages
    /// never move the Calendar Grid; the connection and the events module
    /// publish into it through the shared resolution.
    @ViewBuilder
    private var headerStatus: some View {
        if let connection {
            let content = resolveHeaderStatus(
                connection: connection.status,
                events: events?.status
            )
            IOSHeaderStatus(
                message: content.message,
                tone: content.tone
            )
        }
    }

    /// The sheet presentation binding for the first-connect explanation.
    /// Interactive dismissal routes through the module's cancellation, so a
    /// dismissed sheet never opens Google authorization UI.
    private var explanationItem: Binding<GoogleConnectionExplanation?> {
        Binding(
            get: { connection?.explanation },
            set: { presented in
                if presented == nil {
                    connection?.cancelConnectExplanation()
                }
            }
        )
    }

    private func refreshCalendarGrid() {
        let target = model.refresh(environment: currentEnvironment())
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollPosition = target
        }
    }

    private func handleSystemChange() {
        guard scenePhase == .active else {
            return
        }

        refreshCalendarGrid()
        midnightScheduleGeneration += 1
    }

    private func refreshAtNextLocalMidnight() async {
        guard scenePhase == .active else {
            return
        }

        let environment = currentEnvironment()
        let startOfToday = environment.calendar.startOfDay(for: environment.now)
        guard let nextMidnight = environment.calendar.date(
            byAdding: .day,
            value: 1,
            to: startOfToday
        ) else {
            return
        }
        let delay = max(0, nextMidnight.timeIntervalSince(environment.now))

        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }

        guard !Task.isCancelled, scenePhase == .active else {
            return
        }

        refreshCalendarGrid()
        midnightScheduleGeneration += 1
    }

    private func jumpToToday() {
        guard let target = model.todayJumpTarget() else {
            return
        }

        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                scrollPosition = target
            }
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                scrollPosition = target
            }
        }
    }

    private func updateTopWeek(_ offsets: [WeekRow.ID: CGFloat]) {
        let topWeekStart = offsets
            .filter { $0.value <= 0.5 }
            .max { $0.value < $1.value }?
            .key
            ?? offsets.min { $0.value < $1.value }?.key

        if let topWeekStart, topWeekStart != model.topWeekStart {
            model.showWeek(starting: topWeekStart)
        }

        reportVisibleRange()
    }

    /// Tells the Calendar Events module which local dates are on screen so
    /// it can grow the Fetched Window ahead of the user's scrolling. The
    /// bottom of the visible range is estimated from the viewport height
    /// and the fixed 96-point Week Row.
    private func reportVisibleRange() {
        guard let events else {
            return
        }

        let visibleWeeks = max(
            1,
            Int(ceil(scrollViewportHeight / WeekRowMetrics.height)) + 1
        )
        guard
            let bottomWeek = currentEnvironment().calendar.date(
                byAdding: .day,
                value: 7 * visibleWeeks,
                to: model.topWeekStart
            )
        else {
            return
        }

        events.showVisibleRange(
            from: model.topWeekStart,
            through: bottomWeek
        )
    }
}

private struct WeekRowView: View {
    let weekRow: WeekRow
    let eventWeek: CalendarEventWeekLayout?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(
                Array(weekRow.dateCells.enumerated()),
                id: \.element.id
            ) { column, dateCell in
                DateCellView(
                    dateCell: dateCell,
                    rows: eventWeek?.cells[column].rows ?? [],
                    maxBarLane: eventWeek?.cells[column].maxBarLane ?? -1,
                    overflowCount: eventWeek?.cells[column].overflowCount
                )
            }
        }
        .frame(height: WeekRowMetrics.height)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: WeekRowOffsetsKey.self,
                    value: [
                        weekRow.id: geometry.frame(
                            in: .named(CalendarSurfaceCoordinateSpace.name)
                        ).minY
                    ]
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PlannerPalette.separator)
                .frame(height: 1)
        }
        .overlay(alignment: .topLeading) {
            if let eventWeek {
                CalendarEventBarsOverlay(bars: eventWeek.bars)
            }
        }
    }
}

/// The fixed Week Row dimensions shared by the row view and the
/// visible-range estimate, so the two can never drift.
private enum WeekRowMetrics {
    static let height: CGFloat = 96
}

/// The shared vertical rhythm of Calendar Event presentation within a
/// 96-point Week Row: the bar layer and the per-cell rows must agree on
/// where lanes begin and how tall they are.
private enum CalendarEventLayoutMetrics {
    /// The first lane's distance from the row's top: below the day-number
    /// area (6pt padding + 18pt label + 2pt gap).
    static let barsTop: CGFloat = 26
    /// The height of one Calendar Event Bar or Calendar Event Row: the
    /// platform fitting of the Web Experience's denser presentation
    /// (ticket #75).
    static let itemHeight: CGFloat = 14
    /// The distance between lane origins.
    static let lanePitch: CGFloat = 16
    /// The vertical gap between a cell's rows.
    static let rowSpacing: CGFloat = 2
}

/// The Calendar Event Bar layer for one Week Row: continuous colored strips
/// spanning Date Cells in their lanes. Bars are pure paint — the layer is
/// inert, keeping Date Cells free of gestures.
private struct CalendarEventBarsOverlay: View {
    @Environment(\.layoutDirection) private var layoutDirection

    let bars: [CalendarEventBarSegment]

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = geometry.size.width / 7
            ForEach(bars) { bar in
                // Logical columns are Monday-first either way; in a
                // right-to-left presentation the leading edge is the
                // trailing physical side, so the span mirrors.
                let leadingColumn = layoutDirection == .rightToLeft
                    ? 6 - bar.endColumn
                    : bar.startColumn
                let columnCount = bar.endColumn - bar.startColumn + 1
                let x = cellWidth * CGFloat(leadingColumn) + 1
                let width = cellWidth * CGFloat(columnCount) - 2
                let y = CalendarEventLayoutMetrics.barsTop
                    + CGFloat(bar.lane) * CalendarEventLayoutMetrics.lanePitch

                Text(bar.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(
                        bar.textTone == .dark ? PlannerPalette.ink : Color.white
                    )
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .padding(.trailing, 2)
                    .frame(
                        width: width,
                        height: CalendarEventLayoutMetrics.itemHeight,
                        alignment: .leading
                    )
                    .background(
                        Color(eventHex: bar.colorHex),
                        in: UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: bar.isStartTruncated ? 0 : 3,
                                bottomLeading: bar.isStartTruncated ? 0 : 3,
                                bottomTrailing: bar.isEndTruncated ? 0 : 3,
                                topTrailing: bar.isEndTruncated ? 0 : 3
                            )
                        )
                    )
                    .position(
                        x: x + width / 2,
                        y: y + CalendarEventLayoutMetrics.itemHeight / 2
                    )
            }
        }
        .allowsHitTesting(false)
        .clipped()
    }
}

/// A Calendar Event Row: an Event Color dot, the localized start
/// time, and the title, truncating at the cell's trailing edge.
private struct CalendarEventRowView: View {
    let row: CalendarEventRowItem

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Color(eventHex: row.colorHex))
                .frame(width: 5, height: 5)
            Text(row.startTimeText)
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(PlannerPalette.ink)
                .fixedSize()
            Text(row.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(PlannerPalette.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CalendarEventLayoutMetrics.itemHeight)
        .clipped()
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

private enum CalendarSurfaceCoordinateSpace {
    static let name = "iOS Calendar Surface"
}

private struct WeekRowOffsetsKey: PreferenceKey {
    static var defaultValue: [WeekRow.ID: CGFloat] { [:] }

    static func reduce(
        value: inout [WeekRow.ID: CGFloat],
        nextValue: () -> [WeekRow.ID: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct DateCellView: View {
    private static let labelFontSize: CGFloat = 10

    let dateCell: DateCell
    var rows: [CalendarEventRowItem] = []
    var maxBarLane: Int = -1
    var overflowCount: Int?

    private var rowsTop: CGFloat {
        CalendarEventLayoutMetrics.barsTop
            + CGFloat(maxBarLane + 1) * CalendarEventLayoutMetrics.lanePitch
    }

    var body: some View {
        HStack(spacing: 1) {
            if let monthMarker = dateCell.monthMarker {
                Text(monthMarker)
                    .font(.system(size: Self.labelFontSize, weight: .semibold))
                    .foregroundStyle(PlannerPalette.monthText)
                    .lineLimit(1)
                    .allowsTightening(true)
                    .layoutPriority(1)
                    .padding(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 0))
            }

            Spacer(minLength: 0)

            Text(dateCell.dayText)
                .font(
                    .system(
                        size: Self.labelFontSize,
                        weight: dateCell.isToday ? .bold : .medium
                    )
                )
                .monospacedDigit()
                .foregroundStyle(dateCell.isToday ? Color.white : PlannerPalette.ink)
                .frame(width: 18, height: 18)
                .background {
                    if dateCell.isToday {
                        Circle()
                            .fill(PlannerPalette.olive)
                    }
                }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            dateCell.isWeekend ? PlannerPalette.weekendCell : PlannerPalette.grid
        )
        .overlay(alignment: .leading) {
            if dateCell.monthMarker != nil {
                Rectangle()
                    .fill(PlannerPalette.monthRule)
                    .frame(width: 3)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(PlannerPalette.separator)
                .frame(width: 1)
        }
        .overlay(alignment: .topLeading) {
            if !rows.isEmpty || overflowCount != nil {
                VStack(
                    alignment: .leading,
                    spacing: CalendarEventLayoutMetrics.rowSpacing
                ) {
                    ForEach(rows) { row in
                        CalendarEventRowView(row: row)
                    }
                    if let overflowCount {
                        // The inert Events Overflow marker: it reads the
                        // hidden count and summons nothing.
                        Text("+\(overflowCount) more")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(PlannerPalette.monthText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: CalendarEventLayoutMetrics.itemHeight)
                    }
                }
                .padding(.horizontal, 3)
                .padding(.top, rowsTop)
                .allowsHitTesting(false)
                // Rows never paint past the fixed 96-point Week Row; the
                // visible cap already bounds what may appear.
                .clipped()
            }
        }
    }
}

#if DEBUG
#Preview("iPhone · Light") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment }
    )
    .frame(width: 393, height: 852)
}

#Preview("11-inch iPad · Light") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment }
    )
    .frame(width: 834, height: 1_194)
}

#Preview("Long Visible Month · Compact") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "es_ES",
        month: 9
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment }
    )
    .frame(width: 320, height: 700)
}

#Preview("Right to Left · Compact iPad") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "ar_SA",
        month: 9
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment }
    )
    .frame(width: 507, height: 700)
}

#Preview("Account Control · Compact") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection()
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Wide") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection()
    )
    .frame(width: 834, height: 1_194)
}

#Preview("Account Control · Unconfigured") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewUnconfiguredConnection()
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Restoring") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewRestoringConnection()
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Explanation") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: GoogleAccountConnection(
            control: .disconnected(connectEnabled: true),
            status: GoogleAccountConnection.Status(message: nil, tone: .info),
            explanation: GoogleConnectionExplanation(
                privacyPolicyURL: URL(string: "https://planner.example/privacy")!
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connecting") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: GoogleAccountConnection(
            control: .connecting,
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.connecting,
                tone: .info
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connected") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection()
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connected · Wide") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection()
    )
    .frame(width: 834, height: 1_194)
}

#Preview("Account Control · Connected · Offline") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .connected(
                GoogleAccountConnection.GoogleConnectedProfile(
                    displayName: "Rua Did",
                    imageURL: nil
                )
            ),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.offline,
                tone: .warning
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connected · Long Name") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .connected(
                GoogleAccountConnection.GoogleConnectedProfile(
                    displayName: "Maximilian Alexander Montgomery-Fitzgerald",
                    imageURL: nil
                )
            ),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.connected,
                tone: .info
            )
        )
    )
    .frame(width: 834, height: 1_194)
}

#Preview("Account Control · Connected · No Name") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .connected(
                GoogleAccountConnection.GoogleConnectedProfile(
                    displayName: nil,
                    imageURL: nil
                )
            ),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.connected,
                tone: .info
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Cancelled") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .disconnected(connectEnabled: true),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.cancelled,
                tone: .info
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Failed") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .disconnected(connectEnabled: true),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.failed,
                tone: .error
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Expired") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection(
            control: .disconnected(connectEnabled: true),
            status: GoogleAccountConnection.Status(
                message: GoogleAccountConnectionCopy.expired,
                tone: .error
            )
        )
    )
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connected · Dynamic Type") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection()
    )
    .dynamicTypeSize(.xxxLarge)
    .frame(width: 393, height: 852)
}

#Preview("Account Control · Connected · Landscape") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection()
    )
    .frame(width: 852, height: 393)
}

#Preview("Account Control · Long Visible Month · Compact") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "es_ES",
        month: 9
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection()
    )
    .frame(width: 320, height: 700)
}

#Preview("Account Control · Right to Left") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "ar_SA",
        month: 9
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnection()
    )
    .frame(width: 507, height: 700)
}

/// A connection module fixed in a given presentation for deterministic
/// shell previews.
@MainActor
private func previewConnection(
    control: GoogleAccountConnection.ControlPresentation,
    status: GoogleAccountConnection.Status
) -> GoogleAccountConnection {
    GoogleAccountConnection(control: control, status: status)
}

/// A connection module fixed in the disconnected, Connect-enabled
/// presentation for deterministic shell previews.
@MainActor
private func previewConnection() -> GoogleAccountConnection {
    previewConnection(
        control: .disconnected(connectEnabled: true),
        status: GoogleAccountConnection.Status(message: nil, tone: .info)
    )
}

/// A connection module fixed in the restoring presentation that greets a
/// returning user before saved authorization is validated.
@MainActor
private func previewRestoringConnection() -> GoogleAccountConnection {
    GoogleAccountConnection(
        control: .restoring,
        status: GoogleAccountConnection.Status(
            message: GoogleAccountConnectionCopy.restoring,
            tone: .info
        )
    )
}

/// A connection module fixed in the connected presentation. The preview
/// profile deliberately has no image URL, so previews never touch the
/// network and exercise the initials fallback; image presentation belongs
/// to manual acceptance.
@MainActor
private func previewConnectedConnection() -> GoogleAccountConnection {
    GoogleAccountConnection(
        control: .connected(
            GoogleAccountConnection.GoogleConnectedProfile(
                displayName: "Rua Did",
                imageURL: nil
            )
        ),
        status: GoogleAccountConnection.Status(
            message: GoogleAccountConnectionCopy.connected,
            tone: .info
        )
    )
}

/// A connection module for the unconfigured-build presentation, driven
/// through the real configuration path.
@MainActor
private func previewUnconfiguredConnection() -> GoogleAccountConnection {
    GoogleAccountConnection(
        configuration: .unconfigured,
        makeAdapter: { _ in PreviewGoogleSignInAdapter() },
        disclosureStore: UserDefaultsGoogleConnectionDisclosureStore(),
        installationBoundary: GoogleConnectionInstallationBoundary(
            defaults: .standard,
            deviceMarkerStore: KeychainGoogleConnectionDeviceMarkerStore()
        )
    )
}

/// The stub Google Sign-In adapter for the unconfigured preview: it is
/// never invoked because the module owns no adapter in that state.
private struct PreviewGoogleSignInAdapter: GoogleSignInAdapting {
    func signIn(
        requestingScopes scopes: [String]
    ) async -> GoogleAuthorizationOutcome {
        .cancelled
    }

    func restorePreviousSignIn() async -> GoogleRestorationOutcome {
        .noSavedUser
    }

    func signOut() {}

    func handleCallbackURL(_ url: URL) -> Bool {
        false
    }
}

#Preview("Calendar Events · Connected") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection(),
        events: previewEvents(environment: environment)
    )
    .frame(width: 393, height: 852)
}

#Preview("Calendar Events · Wide") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection(),
        events: previewEvents(environment: environment)
    )
    .frame(width: 834, height: 1_194)
}

#Preview("Calendar Events · Dense Day") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection(),
        events: previewEvents(environment: environment)
    )
    .frame(width: 393, height: 852)
}

#Preview("Calendar Events · Compact") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "en_US_POSIX",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection(),
        events: previewEvents(environment: environment)
    )
    .frame(width: 320, height: 700)
}

#Preview("Calendar Events · Right to Left") {
    let environment = previewCalendarEnvironment(
        localeIdentifier: "ar_SA",
        month: 7
    )
    CalendarScreen(
        environment: environment,
        currentEnvironment: { environment },
        connection: previewConnectedConnection(),
        events: previewEvents(environment: environment)
    )
    .frame(width: 507, height: 700)
}

/// A Calendar Events module backed by canned events around the preview's
/// Today (2026-07-15), for deterministic event previews. The preview's
/// connected control drives the module's fetch exactly as production does.
@MainActor
private func previewEvents(
    environment: CalendarEnvironment
) -> CalendarEventsModel {
    CalendarEventsModel(
        environment: environment,
        adapter: PreviewGoogleCalendarEventsAdapter()
    )
}

/// The stub Google Calendar events adapter for deterministic previews: a
/// fixed mix of all-day, multiday, intraday, declined, and cancelled events
/// around 2026-07-15, never the network.
private struct PreviewGoogleCalendarEventsAdapter: GoogleCalendarEventsAdapting {
    func fetchEvents(
        from start: Date,
        to end: Date
    ) async -> GoogleCalendarEventsOutcome {
        .success(
            calendar: GoogleSourceCalendar(backgroundColorHex: "#039BE5"),
            events: [
                GoogleCalendarEvent(
                    id: "offsite",
                    summary: "Team Offsite",
                    start: .allDay(year: 2026, month: 7, day: 14),
                    end: .allDay(year: 2026, month: 7, day: 17),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "conference",
                    summary: "Design Conference",
                    start: .allDay(year: 2026, month: 7, day: 17),
                    end: .allDay(year: 2026, month: 7, day: 22),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "hackathon",
                    summary: "Hackathon",
                    start: .timed(previewInstant(2026, 7, 16, 22, 0)),
                    end: .timed(previewInstant(2026, 7, 18, 3, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "standup",
                    summary: "Standup",
                    start: .timed(previewInstant(2026, 7, 15, 9, 30)),
                    end: .timed(previewInstant(2026, 7, 15, 10, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "review",
                    summary: "Design Review",
                    start: .timed(previewInstant(2026, 7, 15, 13, 0)),
                    end: .timed(previewInstant(2026, 7, 15, 14, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "dentist",
                    summary: "Dentist",
                    start: .timed(previewInstant(2026, 7, 16, 11, 0)),
                    end: .timed(previewInstant(2026, 7, 16, 12, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                // A dense Thursday: six intraday events in one Date Cell,
                // beyond the visible cap, so the inert Events Overflow
                // marker appears.
                GoogleCalendarEvent(
                    id: "dense-1",
                    summary: "Breakfast",
                    start: .timed(previewInstant(2026, 7, 16, 8, 0)),
                    end: .timed(previewInstant(2026, 7, 16, 8, 30)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "dense-2",
                    summary: "Standup",
                    start: .timed(previewInstant(2026, 7, 16, 9, 30)),
                    end: .timed(previewInstant(2026, 7, 16, 9, 45)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "dense-3",
                    summary: "Pairing",
                    start: .timed(previewInstant(2026, 7, 16, 13, 0)),
                    end: .timed(previewInstant(2026, 7, 16, 14, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "dense-4",
                    summary: "Demo",
                    start: .timed(previewInstant(2026, 7, 16, 15, 0)),
                    end: .timed(previewInstant(2026, 7, 16, 16, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "dense-5",
                    summary: "Retro",
                    start: .timed(previewInstant(2026, 7, 16, 16, 30)),
                    end: .timed(previewInstant(2026, 7, 16, 17, 30)),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "month-start",
                    summary: "Month Start",
                    // A Month Marker cell carrying an all-day bar.
                    start: .allDay(year: 2026, month: 8, day: 1),
                    end: .allDay(year: 2026, month: 8, day: 2),
                    isCancelled: false,
                    isDeclinedByViewer: false
                ),
                GoogleCalendarEvent(
                    id: "declined-sync",
                    summary: "Declined Sync",
                    start: .timed(previewInstant(2026, 7, 15, 15, 0)),
                    end: .timed(previewInstant(2026, 7, 15, 16, 0)),
                    isCancelled: false,
                    isDeclinedByViewer: true
                ),
                GoogleCalendarEvent(
                    id: "cancelled-review",
                    summary: "Cancelled Review",
                    start: .timed(previewInstant(2026, 7, 15, 17, 0)),
                    end: .timed(previewInstant(2026, 7, 15, 18, 0)),
                    isCancelled: true,
                    isDeclinedByViewer: false
                ),
            ],
            eventColorBackgrounds: [:]
        )
    }
}

/// A GMT instant for the canned preview events; the preview environment's
/// timezone is GMT, so these land on their stated local dates.
private func previewInstant(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(
        from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
    )!
}

@MainActor
private func previewCalendarEnvironment(
    localeIdentifier: String,
    month: Int
) -> CalendarEnvironment {
    guard let timeZone = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("GMT must be available for the deterministic preview")
    }

    let locale = Locale(identifier: localeIdentifier)
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone

    guard let now = calendar.date(
        from: DateComponents(year: 2026, month: month, day: 15, hour: 12)
    ) else {
        preconditionFailure("The Gregorian Calendar must create the preview date")
    }

    return CalendarEnvironment(
        now: now,
        calendar: calendar,
        locale: locale,
        timeZone: timeZone
    )
}
#endif
