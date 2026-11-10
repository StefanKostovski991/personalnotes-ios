import SwiftUI

/// Human friendly date and duration formatting. Output matches the Android app's wording, so a
/// note looks the same on both platforms.
enum NotesDateFormatter {
    static func noteTimestamp(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) {
            return "Today, \(time)"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(time)"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(date.formatted(.dateTime.day().month(.abbreviated))), \(time)"
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }

    static func fullTimestamp(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
    }

    /// m:ss, used for recording duration and playback position.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func elapsed(milliseconds: Int) -> String {
        duration(TimeInterval(milliseconds) / 1000)
    }
}
