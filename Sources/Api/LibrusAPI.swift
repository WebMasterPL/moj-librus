import Foundation

/// Typed wrappers over `LibrusSession.authorizedData` — one method per endpoint,
/// each returning decoded raw models. No joining happens here.
struct LibrusAPI {
    let session: LibrusSession

    private static let decoder = JSONDecoder()

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let data = try await session.authorizedData(path: path)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(path): \(error)")
        }
    }

    /// Endpoints that legitimately 404 / deny when a feature is off return nil
    /// instead of throwing, so one disabled feature can't fail the whole sync.
    private func getOptional<T: Decodable>(_ path: String, as type: T.Type) async -> T? {
        do { return try await get(path, as: type) }
        catch { return nil }
    }

    func me() async throws -> RawMe {
        try await get(Librus.Path.me, as: RawMeResponse.self).me
    }

    func subjects() async throws -> [RawSubject] {
        try await get(Librus.Path.subjects, as: RawSubjectsResponse.self).subjects
    }

    func users() async throws -> [RawUser] {
        try await get(Librus.Path.users, as: RawUsersResponse.self).users
    }

    func classrooms() async -> [RawClassroom] {
        await getOptional(Librus.Path.classrooms, as: RawClassroomsResponse.self)?.classrooms ?? []
    }

    func grades() async throws -> [RawGrade] {
        try await get(Librus.Path.grades, as: RawGradesResponse.self).grades
    }

    func gradeCategories() async -> [RawGradeCategory] {
        await getOptional(Librus.Path.gradeCategories, as: RawGradeCategoriesResponse.self)?.categories ?? []
    }

    func gradeComments() async -> [RawGradeComment] {
        await getOptional(Librus.Path.gradeComments, as: RawGradeCommentsResponse.self)?.comments ?? []
    }

    func lessons() async -> [RawLessonDef] {
        await getOptional(Librus.Path.lessons, as: RawLessonsResponse.self)?.lessons ?? []
    }

    func attendances() async -> [RawAttendance] {
        await getOptional(Librus.Path.attendances, as: RawAttendancesResponse.self)?.attendances ?? []
    }

    func attendanceTypes() async -> [RawAttendanceType] {
        await getOptional(Librus.Path.attendanceTypes, as: RawAttendanceTypesResponse.self)?.types ?? []
    }

    func luckyNumber() async -> RawLuckyNumberResponse.Inner? {
        await getOptional(Librus.Path.luckyNumber, as: RawLuckyNumberResponse.self)?.luckyNumber
    }

    func announcements() async -> [RawAnnouncement] {
        await getOptional(Librus.Path.schoolNotices, as: RawAnnouncementsResponse.self)?.announcements ?? []
    }

    func homework() async -> [RawHomework] {
        await getOptional(Librus.Path.homeworks, as: RawHomeworkResponse.self)?.items ?? []
    }

    func timetable(weekStart: Date) async throws -> [String: [[RawLesson]]] {
        let path = Librus.Path.timetable(weekStart: LibrusDate.ymdString(weekStart))
        return try await get(path, as: RawTimetableResponse.self).days
    }
}
