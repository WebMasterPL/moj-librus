import Foundation
import Security

/// Data shared between the app and the widget extension via an App Group.
///
/// SideStore rewrites the App Group identifier at sign time, so we can't rely on
/// the one declared in the entitlements file — instead we ask the runtime which
/// groups we're actually entitled to and use the first that has a container.
/// Degrades to a no-op when no shared container is available.
enum SharedStore {
    static let declaredGroup = "group.com.olekd.mojlibrus"
    private static let timetableKey = "widget.timetable.v1"

    private static let resolvedGroup: String? = {
        let fm = FileManager.default
        if fm.containerURL(forSecurityApplicationGroupIdentifier: declaredGroup) != nil {
            return declaredGroup
        }
        for group in entitledAppGroups() {
            if fm.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
                return group
            }
        }
        return nil
    }()

    private static var defaults: UserDefaults? {
        resolvedGroup.flatMap { UserDefaults(suiteName: $0) }
    }

    private static func entitledAppGroups() -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        let value = SecTaskCopyValueForEntitlement(
            task, "com.apple.security.application-groups" as CFString, nil)
        if let list = value as? [String] { return list }
        if let list = value as? [Any] { return list.compactMap { $0 as? String } }
        return []
    }

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

    /// Human-readable state for the diagnostics / settings screen.
    static var status: String {
        guard let g = resolvedGroup else { return "niedostępna (App Group nie działa)" }
        let has = loadTimetable() != nil
        return "OK: \(g)\(has ? "" : " (jeszcze bez danych)")"
    }
}
