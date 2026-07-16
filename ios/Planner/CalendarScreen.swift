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
        }
        .environment(
            \.layoutDirection,
            model.layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight
        )
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
                        .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.38))
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                        .padding(.horizontal, 16)

                    Button(action: onJumpToToday) {
                        Text(visibleMonth)
                            .font(.headline.bold())
                            .foregroundStyle(Color.primary)
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
            .background(Color(red: 0.96, green: 0.95, blue: 0.90))

            HStack(spacing: 0) {
                ForEach(weekdayLabels) { label in
                    Text(label.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.44, green: 0.45, blue: 0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if label.isWeekend {
                                Color(red: 0.88, green: 0.86, blue: 0.78)
                            }
                        }
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
        Text(dateCell.dayText)
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
            .background {
                if dateCell.isWeekend {
                    Color(red: 0.98, green: 0.97, blue: 0.93)
                }
            }
            .overlay(alignment: .topLeading) {
                if let monthMarker = dateCell.monthMarker {
                    Text(monthMarker)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.38))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 36)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.82, blue: 0.74))
                    .frame(width: 1)
            }
    }
}

#if DEBUG
#Preview("Today Week Row") {
    CalendarScreen(
        environment: previewCalendarEnvironment(
            localeIdentifier: "en_US_POSIX",
            month: 7
        )
    )
}

#Preview("Long Visible Month · Compact") {
    CalendarScreen(
        environment: previewCalendarEnvironment(
            localeIdentifier: "es_ES",
            month: 9
        )
    )
    .frame(width: 320, height: 700)
}

#Preview("Right to Left · Compact iPad") {
    CalendarScreen(
        environment: previewCalendarEnvironment(
            localeIdentifier: "ar_SA",
            month: 9
        )
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
