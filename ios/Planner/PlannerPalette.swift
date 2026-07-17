import SwiftUI

/// Planner's fixed warm beige/olive presentation palette.
///
/// Shared by the iOS Calendar Header and the Calendar Surface so presentation
/// details stay consistent and free of authentication or status concerns.
enum PlannerPalette {
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
    static let statusWarning = Color(red: 0.541, green: 0.353, blue: 0.0)
    static let statusError = Color(red: 0.639, green: 0.176, blue: 0.129)
}
