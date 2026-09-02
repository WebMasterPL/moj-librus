import Foundation

// Joined, display-ready models produced by `DataRepository`.

// MARK: - Grades

enum GradeKind: String, Codable {
    case normal
    case semesterProposed, semesterFinal
    case yearProposed, yearFinal
}

struct GradeItem: Identifiable, Codable, Hashable {
    let id: Int
    let raw: String
    let value: Double?
    let weight: Double
    let semester: Int
    let kind: GradeKind
    let categoryName: String
    let teacherName: String
    let subjectId: Int
    let subjectName: String
    let date: Date?
    let comment: String?

    var countsToAverage: Bool { kind == .normal && value != nil && weight > 0 }
}

struct SubjectGrades: Identifiable, Codable, Hashable {
    var id: Int { subjectId }
    let subjectId: Int
    let subjectName: String
    var grades: [GradeItem]

    var semesterGrades: [GradeItem] { grades.filter { $0.kind == .normal } }

    var average: Double? {
        GradeMath.weightedAverage(semesterGrades)
    }

    var proposedFinal: GradeItem? { grades.first { $0.kind == .yearProposed || $0.kind == .semesterProposed } }
    var final: GradeItem? { grades.first { $0.kind == .yearFinal || $0.kind == .semesterFinal } }
}

// MARK: - Timetable

struct TimetableEntry: Identifiable, Codable, Hashable {
    let id: String
    let lessonNo: Int
    let start: String
    let end: String
    let subject: String
    let teacher: String?
    let classroom: String?
    let isCancelled: Bool
    let isSubstitution: Bool
    let note: String?
}

struct TimetableDay: Identifiable, Codable, Hashable {
    var id: Date { date }
    let date: Date
    let entries: [TimetableEntry]

    var hasLessons: Bool { !entries.isEmpty }
}

// MARK: - Attendance

enum AttendanceKind: String, Codable, CaseIterable {
    case present, presentCustom, absent, absentExcused, belated, released

    var label: String {
        switch self {
        case .present: return "Obecność"
        case .presentCustom: return "Obecność (inne)"
        case .absent: return "Nieobecność"
        case .absentExcused: return "Nieob. usprawiedliwiona"
        case .belated: return "Spóźnienie"
        case .released: return "Zwolnienie"
        }
    }

    var countsAsAbsence: Bool { self == .absent }
}

struct AttendanceItem: Identifiable, Codable, Hashable {
    let id: Int
    let kind: AttendanceKind
    let typeName: String
    let typeShort: String
    let colorHex: String?
    let date: Date?
    let lessonNo: Int?
    let subjectName: String?
    let semester: Int?
}

struct AttendanceSummary: Codable, Hashable {
    var counts: [AttendanceKind: Int] = [:]

    var total: Int { counts.values.reduce(0, +) }
    var present: Int { (counts[.present] ?? 0) + (counts[.presentCustom] ?? 0) }
    var absent: Int { counts[.absent] ?? 0 }
    var absentExcused: Int { counts[.absentExcused] ?? 0 }
    var belated: Int { counts[.belated] ?? 0 }
    var released: Int { counts[.released] ?? 0 }

    /// present / (present + all absence types)
    var attendancePercent: Double? {
        let considered = present + absent + absentExcused + belated + released
        guard considered > 0 else { return nil }
        return Double(present + belated) / Double(considered) * 100
    }
}

// MARK: - Announcements / homework / lucky number

struct AnnouncementItem: Identifiable, Codable, Hashable {
    let id: String
    let subject: String
    let content: String
    let author: String?
    let date: Date?
    let wasReadOnServer: Bool
}

struct HomeworkItem: Identifiable, Codable, Hashable {
    let id: Int
    let topic: String
    let text: String
    let dueDate: Date?
    let createdDate: Date?
    let teacher: String?
    let subject: String?
}

struct LuckyNumberInfo: Codable, Hashable {
    let number: Int
    let day: Date?
}

// MARK: - Messages

struct MessageItem: Identifiable, Codable, Hashable {
    let id: Int
    let subject: String
    let correspondent: String
    let sentDate: Date?
    let readDateServer: Date?
    let hasAttachments: Bool
    var body: String?

    var isUnread: Bool { readDateServer == nil }
}
