import Foundation

/// All Librus network constants in one place. If Librus rotates the mobile-app
/// OAuth client, only `basicAuth` / `userAgent` here need to change.
///
/// Values verified against the open-source `github.com/szkolny-eu/szkolny-android`
/// client (`data/api/Constants.kt`). These are the Librus *mobile app's own*
/// credentials, not per-user secrets.
enum Librus {
    /// OAuth token endpoint (password + refresh_token grants).
    static let tokenURL = URL(string: "https://api.librus.pl/OAuth/Token")!

    /// Base for the REST v2.0 API.
    static let apiBase = URL(string: "https://api.librus.pl/2.0")!

    /// `Basic base64("28:<secret>")` — the mobile app client.
    static let basicAuth = "Basic Mjg6ODRmZGQzYTg3YjAzZDNlYTZmZmU3NzdiNThiMzMyYjE="

    static let userAgent = "LibrusMobileApp"

    /// Browser UA used for the Synergia web session + messages module.
    static let browserUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Gecko/20100101 Firefox/62.0"

    static let synergiaBase = URL(string: "https://synergia.librus.pl")!
    static let messagesModuleBase = URL(string: "https://wiadomosci.librus.pl/module")!

    /// `TOKEN` is replaced with the AutoLoginToken value.
    static let synergiaTokenLoginPath = "/loguj/token/TOKEN/przenies"

    // REST v2.0 endpoint paths (relative to `apiBase`).
    enum Path {
        static let me = "Me"
        static let subjects = "Subjects"
        static let users = "Users"
        static let classrooms = "Classrooms"
        static let grades = "Grades"
        static let gradeCategories = "Grades/Categories"
        static let gradeComments = "Grades/Comments"
        static let lessons = "Lessons"
        static let attendances = "Attendances"
        static let attendanceTypes = "Attendances/Types"
        static let luckyNumber = "LuckyNumbers"
        static let schoolNotices = "SchoolNotices"
        static let homeworks = "HomeWorkAssignments"
        static let events = "HomeWorks"
        static let eventCategories = "HomeWorks/Categories"
        static let classes = "Classes"
        static let notes = "Notes"
        static let noteCategories = "Notes/Categories"
        static let autoLoginToken = "AutoLoginToken"
        static func timetable(weekStart: String) -> String { "Timetables?weekStart=\(weekStart)" }
    }
}
