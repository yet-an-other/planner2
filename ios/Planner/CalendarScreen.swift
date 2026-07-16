import Foundation
import SwiftUI

private enum PlannerPalette {
    static let canvas = Color(red: 0.961, green: 0.945, blue: 0.902)
    static let grid = Color.white
    static let ink = Color(red: 0.114, green: 0.129, blue: 0.071)
    static let olive = Color(red: 0.471, green: 0.490, blue: 0.380)
    static let monthText = Color(red: 0.435, green: 0.447, blue: 0.353)
    static let monthRule = Color(red: 0.545, green: 0.561, blue: 0.447)
    static let weekdayStrip = Color(red: 0.910, green: 0.890, blue: 0.820)
    static let weekendStrip = Color(red: 0.878, green: 0.859, blue: 0.780)
    static let weekendCell = Color(red: 0.980, green: 0.969, blue: 0.929)
    static let separator = Color(red: 0.851, green: 0.820, blue: 0.741)
    static let emphasizedControl = Color(red: 0.922, green: 0.890, blue: 0.820)
}

struct CalendarScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: CalendarGridModel
    @State private var scrollPosition: WeekRow.ID?
    @State private var midnightScheduleGeneration = 0

    private let currentEnvironment: @MainActor () -> CalendarEnvironment

    init(
        environment: CalendarEnvironment,
        currentEnvironment: @escaping @MainActor () -> CalendarEnvironment
    ) {
        let model = CalendarGridModel(environment: environment)
        _model = State(initialValue: model)
        _scrollPosition = State(initialValue: model.todayWeek.id)
        self.currentEnvironment = currentEnvironment
    }

    var body: some View {
        VStack(spacing: 0) {
            IOSCalendarHeader(
                visibleMonth: model.visibleMonth,
                weekdayLabels: model.weekdayLabels,
                onJumpToToday: jumpToToday
            )

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 0) {
                    ForEach(model.weekRows) { weekRow in
                        WeekRowView(weekRow: weekRow)
                    }
                }
                .scrollTargetLayout()
            }
            .coordinateSpace(name: CalendarSurfaceCoordinateSpace.name)
            .scrollPosition(id: $scrollPosition, anchor: .top)
            .onPreferenceChange(WeekRowOffsetsKey.self, perform: updateTopWeek)
            .background(PlannerPalette.grid)
        }
        .background(PlannerPalette.canvas)
        .preferredColorScheme(.light)
        .environment(
            \.layoutDirection,
            model.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        )
        .onChange(of: scenePhase) { _, nextScenePhase in
            midnightScheduleGeneration += 1
            if nextScenePhase == .active {
                refreshCalendarGrid()
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
    }
}

private struct IOSCalendarHeader: View {
    @FocusState private var visibleMonthFocused: Bool
    @State private var visibleMonthHovered = false

    let visibleMonth: String
    let weekdayLabels: [WeekdayLabel]
    let onJumpToToday: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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

private struct WeekRowView: View {
    let weekRow: WeekRow

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekRow.dateCells) { dateCell in
                DateCellView(dateCell: dateCell)
            }
        }
        .frame(height: 96)
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

private struct DateCellView: View {
    let dateCell: DateCell

    var body: some View {
        Text(dateCell.dayText)
            .font(.body.weight(dateCell.isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(dateCell.isToday ? Color.white : PlannerPalette.ink)
            .frame(width: 32, height: 32)
            .background {
                if dateCell.isToday {
                    Circle()
                        .fill(PlannerPalette.olive)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(6)
            .background(
                dateCell.isWeekend ? PlannerPalette.weekendCell : PlannerPalette.grid
            )
            .overlay(alignment: .topLeading) {
                if let monthMarker = dateCell.monthMarker {
                    Text(monthMarker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(PlannerPalette.monthText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 36)
                }
            }
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
