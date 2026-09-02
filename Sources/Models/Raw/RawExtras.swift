import Foundation

// MARK: - Classes (school-year dates, class name, tutor)

struct RawClassesResponse: Decodable {
    let studentClass: RawStudentClass?
    enum CodingKeys: String, CodingKey { case studentClass = "Class" }
}

struct RawStudentClass: Decodable {
    let id: Int
    let number: String?
    let symbol: String?
    let classTutor: Ref?
    let beginSchoolYear: String?
    let endFirstSemester: String?
    let endSchoolYear: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", number = "Number", symbol = "Symbol", classTutor = "ClassTutor"
        case beginSchoolYear = "BeginSchoolYear"
        case endFirstSemester = "EndFirstSemester"
        case endSchoolYear = "EndSchoolYear"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexInt(.id) ?? -1
        number = try? c.decode(String.self, forKey: .number)
        symbol = try? c.decode(String.self, forKey: .symbol)
        classTutor = try? c.decode(Ref.self, forKey: .classTutor)
        beginSchoolYear = try? c.decode(String.self, forKey: .beginSchoolYear)
        endFirstSemester = try? c.decode(String.self, forKey: .endFirstSemester)
        endSchoolYear = try? c.decode(String.self, forKey: .endSchoolYear)
    }

    var name: String {
        "\((number ?? ""))\((symbol ?? ""))".trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Behaviour notes (uwagi)

struct RawNotesResponse: Decodable {
    let notes: [RawNote]
    enum CodingKeys: String, CodingKey { case notes = "Notes" }
}

struct RawNote: Decodable {
    let id: Int
    let text: String
    let category: Ref?
    let teacher: Ref?
    let date: String?
    /// 0 = negatywna, 1 = pozytywna, 2 = neutralna
    let positive: Int

    enum CodingKeys: String, CodingKey {
        case id = "Id", text = "Text", category = "Category"
        case teacher = "Teacher", date = "Date", positive = "Positive"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexInt(.id) ?? -1
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        category = try? c.decode(Ref.self, forKey: .category)
        teacher = try? c.decode(Ref.self, forKey: .teacher)
        date = try? c.decode(String.self, forKey: .date)
        positive = c.decodeFlexInt(.positive) ?? 2
    }
}

struct RawNoteCategoriesResponse: Decodable {
    let categories: [RawNoteCategory]
    enum CodingKeys: String, CodingKey { case categories = "Categories" }
}

struct RawNoteCategory: Decodable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey { case id = "Id", name = "CategoryName" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeFlexInt(.id) ?? -1
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
    }
}
