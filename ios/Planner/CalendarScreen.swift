import Foundation
import SwiftUI

struct CalendarScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: CalendarGridModel
    @State private var scrollPosition: WeekRow.ID?

    init(environment: CalendarEnvironment) {
        let model = CalendarGridModel(environment: environment)
        _model = State(initialValue: model)
        _scrollPosition = State(initialValue: model.todayWeek.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            IOSCalendarHeader(
                visibleMonth: model.visibleMonth,
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
        }
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
    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    @FocusState private var visibleMonthFocused: Bool
    @State private var visibleMonthHovered = false

    let visibleMonth: String
    let onJumpToToday: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Planner")
                    .font(.title.bold())
                    .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.38))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

                Button(action: onJumpToToday) {
                    Text(visibleMonth)
                        .font(.headline.bold())
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
                .buttonStyle(
                    VisibleMonthButtonStyle(
                        emphasized: visibleMonthFocused || visibleMonthHovered
                    )
                )
                .focused($visibleMonthFocused)
                .onHover { visibleMonthHovered = $0 }
            }
            .padding(.horizontal, 16)
            .frame(height: 64)
            .background(Color(red: 0.96, green: 0.95, blue: 0.90))

            HStack(spacing: 0) {
                ForEach(weekdayLabels, id: \.self) { label in
                    Text(label.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.44, green: 0.45, blue: 0.35))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 36)
            .background(Color(red: 0.91, green: 0.89, blue: 0.82))
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
                    .fill(Color(red: 0.92, green: 0.89, blue: 0.82))
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
                .fill(Color(red: 0.85, green: 0.82, blue: 0.74))
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
        Text(dateCell.dayNumber, format: .number)
            .font(.body.weight(dateCell.isToday ? .bold : .regular))
            .monospacedDigit()
            .foregroundStyle(dateCell.isToday ? Color.white : Color.primary)
            .frame(width: 32, height: 32)
            .background {
                if dateCell.isToday {
                    Circle()
                        .fill(Color(red: 0.47, green: 0.49, blue: 0.38))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(6)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.82, blue: 0.74))
                    .frame(width: 1)
            }
    }
}

#if DEBUG
#Preview("Today Week Row") {
    CalendarScreen(environment: previewCalendarEnvironment)
}

@MainActor
private var previewCalendarEnvironment: CalendarEnvironment {
    guard let timeZone = TimeZone(secondsFromGMT: 0) else {
        preconditionFailure("GMT must be available for the deterministic preview")
    }

    let locale = Locale(identifier: "en_US_POSIX")
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = locale
    calendar.timeZone = timeZone

    guard let now = calendar.date(
        from: DateComponents(year: 2026, month: 7, day: 15, hour: 12)
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
