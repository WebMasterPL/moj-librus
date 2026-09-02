import Foundation

/// Data shared between the app and the widget extension via an App Group.
/// Degrades to a no-op when the App Group isn't provisioned.
enum SharedStore {
    static let appGroup = "group.com.olekd.mojlibrus"
    private static let timetableKey = "widget.timetable.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    struct WidgetTimetable: Codable {
        struct Lesson: Codable, Identifiable, Hashable {
            var id: String
            var lessonNo: Int
            var start: String
            var end: String
            var subject: String
            var room: String?
            var isCancelled: Bool
            var isSubstitution: Bool
            var roomChanged: Bool
            var note: String?
        }
        struct Day: Codable, Identifiable, Hashable {
            var id: Date { date }
            var date: Date
            var lessons: [Lesson]
        }
        var days: [Day]
        var updated: Date
    }

    static func publishTimetable(_ days: [WidgetTimetable.Day]) {
        guard let defaults else { return }
        let payload = WidgetTimetable(days: days, updated: Date())
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: timetableKey)
        }
    }

    static func loadTimetable() -> WidgetTimetable? {
        guard let data = defaults?.data(forKey: timetableKey) else { return nil }
        return try? JSONDecoder().decode(WidgetTimetable.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: timetableKey)
    }
}
