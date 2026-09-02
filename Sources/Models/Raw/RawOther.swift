import Foundation

// MARK: - Attendances

struct RawAttendancesResponse: Decodable {
    let attendances: [RawAttendance]
    enum CodingKeys: String, CodingKey { case attendances = "Attendances" }
}

struct RawAttendance: Decodable {
    let id: Int
    let lesson: Ref?
    let lessonNo: Int?
    let date: String?
    let addedBy: Ref?
    let semester: Int?
    let type: Ref?
    let addDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", lesson = "Lesson", lessonNo = "LessonNo", date = "Date"
        case addedBy = "AddedBy", semester = "Semester", type = "Type", addDate = "AddDate"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `Id` is a string like "12345" — strip anything non-numeric just in case.
        if let s = try? c.decode(String.self, forKey: .id) {
            id = Int(s.filter(\.isNumber)) ?? -1
        } else {
            id = c.decodeFlexInt(.id) ?? -1
        }
        lesson = try? c.decode(Ref.self, forKey: .lesson)
        lessonNo = c.decodeFlexInt(.lessonNo)
        date = try? c.decode(String.self, forKey: .date)
        addedBy = try? c.decode(Ref.self, forKey: .addedBy)
        semester = c.decodeFlexInt(.semester)
        type = try? c.decode(Ref.self, forKey: .type)
        addDate = try? c.decode(String.self, forKey: .addDate)
    }
}

// MARK: - Lucky number

struct RawLuckyNumberResponse: Decodable {
    let luckyNumber: Inner?
    enum CodingKeys: String, CodingKey { case luckyNumber = "LuckyNumber" }

    struct Inner: Decodable {
        let day: String?
        let number: Int?

        enum CodingKeys: String, CodingKey {
            case day = "LuckyNumberDay", number = "LuckyNumber"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            day = try? c.decode(String.self, forKey: .day)
            number = c.decodeFlexInt(.number)
        }
    }
}

// MARK: - Announcements (SchoolNotices)

struct RawAnnouncementsResponse: Decodable {
    let announcements: [RawAnnouncement]
    enum CodingKeys: String, CodingKey { case announcements = "SchoolNotices" }
}

struct RawAnnouncement: Decodable {
    let id: String
    let subject: String
    let content: String
    let startDate: String?
    let endDate: String?
    let creationDate: String?
    let addedBy: Ref?
    let wasRead: Bool

    enum CodingKeys: String, CodingKey {
        case id = "Id", subject = "Subject", content = "Content"
        case startDate = "StartDate", endDate = "EndDate", creationDate = "CreationDate"
        case addedBy = "AddedBy", wasRead = "WasRead"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = c.decodeFlexInt(.id) { id = String(i) }
        else { id = UUID().uuidString }
        subject = (try? c.decode(String.self, forKey: .subject)) ?? ""
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        startDate = try? c.decode(String.self, forKey: .startDate)
        endDate = try? c.decode(String.self, forKey: .endDate)
        creationDate = try? c.decode(String.self, forKey: .creationDate)
        addedBy = try? c.decode(Ref.self, forKey: .addedBy)
        wasRead = (try? c.decode(Bool.self, forKey: .wasRead)) ?? false
    }
}

// MARK: - Homework (HomeWorkAssignments)

struct RawHomeworkResponse: Decodable {
    let items: [RawHomework]
    enum CodingKeys: String, CodingKey { case items = "HomeWorkAssignments" }
}

struct RawHomework: Decodable {
    let id: Int
    let topic: String
    let text: String
    let dueDate: String?
    let createdDate: String?
    let teacher: Ref?
    let subject: Ref?
    let category: Ref?

    enum CodingKeys: String, CodingKey {
        case id = "Id", topic = "Topic", text = "Text"
        case dueDate = "DueDate", date = "Date"
        case teacher = "Teacher", subject = "Subject", category = "Category"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexInt(.id) ?? -1
        topic = (try? c.decode(String.self, forKey: .topic)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        dueDate = try? c.decode(String.self, forKey: .dueDate)
        createdDate = try? c.decode(String.self, forKey: .date)
        teacher = try? c.decode(Ref.self, forKey: .teacher)
        subject = try? c.decode(Ref.self, forKey: .subject)
        category = try? c.decode(Ref.self, forKey: .category)
    }
}
