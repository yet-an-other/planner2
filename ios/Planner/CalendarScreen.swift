import Foundation
import SwiftUI

struct CalendarScreen: View {
    @State private var model: CalendarGridModel

    init(environment: CalendarEnvironment) {
        _model = State(initialValue: CalendarGridModel(environment: environment))
    }

    var body: some View {
        VStack(spacing: 0) {
            CalendarShellHeader()
            WeekRowView(weekRow: model.todayWeek)
            Spacer(minLength: 0)
        }
    }
}

private struct CalendarShellHeader: View {
    private let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(spacing: 0) {
            Text("Planner")
                .font(.title.bold())
                .foregroundStyle(Color(red: 0.47, green: 0.49, blue: 0.38))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

private struct WeekRowView: View {
    let weekRow: WeekRow

    var body: some View {
        HStack(spacing: 0) {
            ForEach(weekRow.dateCells) { dateCell in
                DateCellView(dateCell: dateCell)
            }
        }
        .frame(height: 96)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.82, blue: 0.74))
                .frame(height: 1)
        }
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
