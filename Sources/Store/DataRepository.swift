import Foundation
import Observation

/// The single source of truth for all screens. Fetches every endpoint, joins by
/// id, caches results, exposes display-ready models.
@MainActor
@Observable
final class DataRepository {
    let session: LibrusSession
    private let api: LibrusAPI
    private let messages: MessagesClient

    // Published state -------------------------------------------------------
    var studentName: String = ""
    var schoolYear = SchoolYearInfo()

    var luckyNumber: LuckyNumberInfo?
    var subjectGrades: [SubjectGrades] = []
    var attendanceSummary = AttendanceSummary()
    var attendanceItems: [AttendanceItem] = []
    var announcements: [AnnouncementItem] = []
    var homework: [HomeworkItem] = []
    var events: [CalendarEvent] = []
    var notes: [NoteItem] = []
    var messagesInbox: [MessageItem] = []

    var currentSemester: Int { schoolYear.semester() }

    /// week-start (yyyy-MM-dd) -> day list
    var timetableWeeks: [String: [TimetableDay]] = [:]

    var lastSync: Date?
    var isRefreshing = false
    var lastError: String?
    var messagesError: String?

    /// Set by `AppState`; invoked when a request proves the session is dead.
    @ObservationIgnored var onSessionExpired: (@MainActor () -> Void)?

    // Last-known lookup tables, kept so a single blipping endpoint doesn't break joins.
    @ObservationIgnored private var rawSubjects: [RawSubject] = []
    @ObservationIgnored private var rawUsers: [RawUser] = []
    @ObservationIgnored private var rawCategories: [RawGradeCategory] = []
    @ObservationIgnored private var rawComments: [RawGradeComment] = []
    @ObservationIgnored private var rawLessons: [RawLessonDef] = []
    @ObservationIgnored private var rawAttTypes: [RawAttendanceType] = []
    @ObservationIgnored private var rawNoteCats: [RawNoteCategory] = []
    @ObservationIgnored private var rawEventCats: [RawEventCategory] = []

    /// Locally-tracked "read" state for announcements (Librus has no student-side write here).
    private var readAnnouncementIDs: Set<String> = []

    /// Bumped after every grade sync so the `SeenGrades`-backed views recompute.
    private var gradeSeenTick = 0

    /// Grades that appeared since the user last opened the Oceny tab. Empty on first sync.
    var unseenGradeCount: Int {
        _ = gradeSeenTick
        return SeenGrades.newIDs(in: allGradeIDs).count
    }

    func isGradeUnseen(_ grade: GradeItem) -> Bool {
        _ = gradeSeenTick
        return SeenGrades.newIDs(in: allGradeIDs).contains(grade.id)
    }

    func markGradesSeen() {
        SeenGrades.merge(allGradeIDs)
        gradeSeenTick &+= 1
    }

    private var allGradeIDs: Set<Int> {
        Set(subjectGrades.flatMap { $0.grades.map(\.id) })
    }

    init(session: LibrusSession) {
        self.session = session
        self.api = LibrusAPI(session: session)
        self.messages = MessagesClient(session: session)
        loadCache()
    }

    // MARK: - Cache

    private struct Snapshot: Codable {
        var studentName: String
        var schoolYear: SchoolYearInfo
        var lucky: LuckyNumberInfo?
        var subjectGrades: [SubjectGrades]
        var attendanceSummary: AttendanceSummary
        var attendanceItems: [AttendanceItem]
        var announcements: [AnnouncementItem]
        var homework: [HomeworkItem]
        var events: [CalendarEvent]?
        var notes: [NoteItem]
        var messagesInbox: [MessageItem]
        var lastSync: Date?
        var readAnnouncementIDs: [String]
    }

    private func loadCache() {
        guard let s = Cache.load(Snapshot.self, from: "snapshot") else { return }
        studentName = s.studentName
        schoolYear = s.schoolYear
        luckyNumber = s.lucky
        subjectGrades = s.subjectGrades
        attendanceSummary = s.attendanceSummary
        attendanceItems = s.attendanceItems
        announcements = s.announcements
        homework = s.homework
        events = s.events ?? []
        notes = s.notes
        messagesInbox = s.messagesInbox
        lastSync = s.lastSync
        readAnnouncementIDs = Set(s.readAnnouncementIDs)
        if let cachedWeeks = Cache.load([String: [TimetableDay]].self, from: "timetable") {
            timetableWeeks = cachedWeeks
        }
    }

    private func saveCache() {
        let snap = Snapshot(
            studentName: studentName, schoolYear: schoolYear, lucky: luckyNumber,
            subjectGrades: subjectGrades, attendanceSummary: attendanceSummary,
            attendanceItems: attendanceItems, announcements: announcements,
            homework: homework, events: events, notes: notes, messagesInbox: messagesInbox,
            lastSync: lastSync, readAnnouncementIDs: Array(readAnnouncementIDs)
        )
        Cache.save(snap, as: "snapshot")
        Cache.save(timetableWeeks, as: "timetable")
    }

    func clearLocal() {
        Cache.clearAll()
        studentName = ""; schoolYear = .init(); luckyNumber = nil; subjectGrades = []
        attendanceSummary = .init(); attendanceItems = []
        announcements = []; homework = []; events = []; notes = []; messagesInbox = []
        SeenGrades.reset()
        timetableWeeks = [:]; lastSync = nil
    }

    // MARK: - Core refresh

    func refreshCore() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            // Dictionaries + primary data, fetched concurrently.
            let api = self.api
            async let meT = api.me()
            async let subjectsT = api.subjects()
            async let usersT = api.users()
            async let categoriesT = api.gradeCategories()
            async let commentsT = api.gradeComments()
            async let gradesT = api.grades()
            async let lessonsT = api.lessons()
            async let attTypesT = api.attendanceTypes()
            async let attsT = api.attendances()
            async let luckyT = api.luckyNumber()
            async let announcementsT = api.announcements()
            async let homeworkT = api.homework()
            async let classesT = api.classes()
            async let notesT = api.notes()
            async let noteCategoriesT = api.noteCategories()
            async let eventsT = api.events()
            async let eventCategoriesT = api.eventCategories()

            let me = try await meT

            // Refresh lookup tables in place; keep the old ones on failure.
            if let v = await subjectsT { rawSubjects = v }
            if let v = await usersT { rawUsers = v }
            if let v = await categoriesT { rawCategories = v }
            if let v = await commentsT { rawComments = v }
            if let v = await lessonsT { rawLessons = v }
            if let v = await attTypesT { rawAttTypes = v }
            if let v = await noteCategoriesT { rawNoteCats = v }
            if let v = await eventCategoriesT { rawEventCats = v }

            let subjectByID = Dictionary(rawSubjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let userByID = Dictionary(rawUsers.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let categoryByID = Dictionary(rawCategories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let commentByID = Dictionary(rawComments.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let lessonByID = Dictionary(rawLessons.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let attTypeByID = Dictionary(rawAttTypes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let noteCatByID = Dictionary(rawNoteCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let eventCatByID = Dictionary(rawEventCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            studentName = me.displayName

            if let sc = await classesT {
                schoolYear = SchoolYearInfo(
                    className: sc.name.isEmpty ? nil : sc.name,
                    tutor: sc.classTutor.flatMap { userByID[$0.id]?.displayName },
                    yearStart: LibrusDate.fromYMD(sc.beginSchoolYear),
                    secondSemesterStart: LibrusDate.fromYMD(sc.endFirstSemester),
                    yearEnd: LibrusDate.fromYMD(sc.endSchoolYear)
                )
            }

            if let rawNotes = await notesT {
                notes = rawNotes.map { n in
                    NoteItem(
                        id: n.id, text: n.text,
                        category: n.category.flatMap { noteCatByID[$0.id]?.name },
                        teacher: n.teacher.flatMap { userByID[$0.id]?.displayName },
                        date: LibrusDate.fromYMD(n.date),
                        kind: n.positive == 1 ? .positive : (n.positive == 0 ? .negative : .neutral)
                    )
                }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            if let grades = await gradesT {
                subjectGrades = Self.joinGrades(
                    grades, subjectByID: subjectByID, userByID: userByID,
                    categoryByID: categoryByID, commentByID: commentByID
                )
                if !SeenGrades.hasBaseline {
                    SeenGrades.establishBaseline(allGradeIDs)
                }
                gradeSeenTick &+= 1
            }

            if let lucky = await luckyT, let n = lucky.number {
                luckyNumber = LuckyNumberInfo(number: n, day: LibrusDate.fromYMD(lucky.day))
            }

            if let atts = await attsT {
                (attendanceSummary, attendanceItems) = Self.joinAttendance(
                    atts, typeByID: attTypeByID, lessonDefByID: lessonByID, subjectByID: subjectByID
                )
            }

            if let anns = await announcementsT {
                announcements = anns.map { a in
                    AnnouncementItem(
                        id: a.id, subject: a.subject, content: a.content,
                        author: a.addedBy.flatMap { userByID[$0.id]?.displayName },
                        date: LibrusDate.fromISO(a.creationDate) ?? LibrusDate.fromYMD(a.startDate),
                        wasReadOnServer: a.wasRead
                    )
                }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }

            if let hw = await homeworkT {
                homework = hw.map { h in
                    HomeworkItem(
                        id: h.id, topic: h.topic, text: h.text,
                        dueDate: LibrusDate.fromYMD(h.dueDate),
                        createdDate: LibrusDate.fromYMD(h.createdDate),
                        teacher: h.teacher.flatMap { userByID[$0.id]?.displayName },
                        subject: h.subject.flatMap { subjectByID[$0.id]?.name }
                    )
                }.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            }

            if let rawEvents = await eventsT {
                events = rawEvents.map { e in
                    CalendarEvent(
                        id: e.id, date: LibrusDate.fromYMD(e.date), content: e.content,
                        category: e.category.flatMap { eventCatByID[$0.id]?.name },
                        subject: e.subject.flatMap { subjectByID[$0.id]?.name },
                        teacher: e.createdBy.flatMap { userByID[$0.id]?.displayName },
                        lessonNo: e.lessonNo,
                        time: e.timeFrom
                    )
                }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            }

            lastSync = Date()
            saveCache()
        } catch {
            handle(error, into: \.lastError)
        }
    }

    /// Records the message and, for a dead session, notifies `AppState`.
    private func handle(_ error: Error, into keyPath: ReferenceWritableKeyPath<DataRepository, String?>) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        self[keyPath: keyPath] = text
        if let apiError = error as? APIError, case .tokenExpired = apiError {
            onSessionExpired?()
        }
    }

    // MARK: - Timetable

    func loadTimetable(weekStart: Date) async {
        let key = LibrusDate.ymdString(weekStart)
        do {
            let raw = try await api.timetable(weekStart: weekStart)
            let days: [TimetableDay] = raw.keys.sorted().compactMap { dateStr in
                guard let date = LibrusDate.fromYMD(dateStr) else { return nil }
                let slots = raw[dateStr] ?? []
                let entries: [TimetableEntry] = slots.flatMap { $0 }.compactMap(Self.mapLesson)
                    .sorted { $0.lessonNo < $1.lessonNo }
                return TimetableDay(date: date, entries: entries)
            }
            timetableWeeks[key] = days
            saveCache()
        } catch {
            if timetableWeeks[key] == nil {
                handle(error, into: \.lastError)
            }
        }
    }

    // MARK: - Messages

    func loadMessages() async {
        messagesError = nil
        do {
            let list = try await messages.inbox()
            messagesInbox = list.sorted { ($0.sentDate ?? .distantPast) > ($1.sentDate ?? .distantPast) }
            saveCache()
        } catch {
            handle(error, into: \.messagesError)
        }
    }

    func loadMessageBody(_ id: Int) async -> String? {
        do { return try await messages.body(messageId: id) }
        catch {
            handle(error, into: \.messagesError)
            return nil
        }
    }

    // MARK: - Read tracking (announcements)

    func isAnnouncementRead(_ item: AnnouncementItem) -> Bool {
        item.wasReadOnServer || readAnnouncementIDs.contains(item.id)
    }

    func markAnnouncementRead(_ item: AnnouncementItem) {
        readAnnouncementIDs.insert(item.id)
        saveCache()
    }

    var unreadAnnouncementCount: Int {
        announcements.filter { !isAnnouncementRead($0) }.count
    }

    var unreadMessageCount: Int { messagesInbox.filter(\.isUnread).count }

    var upcomingEventCount: Int {
        events.filter { !$0.isPast }.count
    }

    /// Nearest not-yet-past event, for the dashboard.
    var nextEvent: CalendarEvent? {
        events.filter { !$0.isPast }.min { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }

    // MARK: - Joining helpers

    private static func joinGrades(
        _ grades: [RawGrade],
        subjectByID: [Int: RawSubject],
        userByID: [Int: RawUser],
        categoryByID: [Int: RawGradeCategory],
        commentByID: [Int: RawGradeComment]
    ) -> [SubjectGrades] {
        var bySubject: [Int: SubjectGrades] = [:]
        for g in grades {
            let subjId = g.subject?.id ?? -1
            let subjName = subjectByID[subjId]?.name ?? "Inne"
            let category = g.category.flatMap { categoryByID[$0.id] }
            let kind: GradeKind
            if g.isSemesterProposition { kind = .semesterProposed }
            else if g.isSemester { kind = .semesterFinal }
            else if g.isFinalProposition { kind = .yearProposed }
            else if g.isFinal { kind = .yearFinal }
            else { kind = .normal }

            let value = GradeMath.numericValue(of: g.grade)
            let weight: Double = {
                let s = g.grade.trimmingCharacters(in: .whitespaces).lowercased()
                if ["+", "-", "np", "bz"].contains(s) { return 0 }
                return category?.effectiveWeight ?? 0
            }()

            let comment = g.commentIds.compactMap { commentByID[$0]?.text }
                .filter { !$0.isEmpty }.joined(separator: " • ")

            let item = GradeItem(
                id: g.id, raw: g.grade, value: value, weight: weight,
                semester: g.semester, kind: kind,
                categoryName: category?.name ?? "",
                teacherName: g.addedBy.flatMap { userByID[$0.id]?.displayName } ?? "",
                subjectId: subjId, subjectName: subjName,
                date: LibrusDate.fromISO(g.addDate),
                comment: comment.isEmpty ? nil : comment
            )
            bySubject[subjId, default: SubjectGrades(subjectId: subjId, subjectName: subjName, grades: [])]
                .grades.append(item)
        }
        return bySubject.values
            .map { var s = $0; s.grades.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }; return s }
            .sorted { $0.subjectName.localizedCaseInsensitiveCompare($1.subjectName) == .orderedAscending }
    }

    private static func joinAttendance(
        _ atts: [RawAttendance],
        typeByID: [Int: RawAttendanceType],
        lessonDefByID: [Int: RawLessonDef],
        subjectByID: [Int: RawSubject]
    ) -> (AttendanceSummary, [AttendanceItem]) {
        var summary = AttendanceSummary()
        var items: [AttendanceItem] = []
        for a in atts {
            let type = a.type.flatMap { typeByID[$0.id] }
            let kind = type?.kind ?? .presentCustom
            summary.counts[kind, default: 0] += 1

            let subjName: String? = {
                guard let lessonId = a.lesson?.id, let def = lessonDefByID[lessonId],
                      let sid = def.subject?.id else { return nil }
                return subjectByID[sid]?.name
            }()

            items.append(AttendanceItem(
                id: a.id, kind: kind,
                typeName: type?.name ?? "Nieznany",
                typeShort: type?.short ?? "?",
                colorHex: type?.colorRGB,
                date: LibrusDate.fromYMD(a.date),
                lessonNo: a.lessonNo,
                subjectName: subjName,
                semester: a.semester
            ))
        }
        items.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        return (summary, items)
    }

    private static func mapLesson(_ l: RawLesson) -> TimetableEntry? {
        guard let no = l.lessonNo, let from = l.hourFrom, let to = l.hourTo else { return nil }
        var note: String?
        if l.isCancelled {
            note = "Lekcja odwołana"
        } else if l.isSubstitution {
            var parts = ["Zastępstwo"]
            if let orgName = l.orgSubject?.name, !orgName.isEmpty { parts.append("(było: \(orgName))") }
            if let orgTeacher = l.orgTeacher?.displayName { parts.append(orgTeacher) }
            note = parts.joined(separator: " ")
        }
        return TimetableEntry(
            id: "\(no)-\(from)", lessonNo: no, start: from, end: to,
            subject: l.subject?.name ?? "—",
            teacher: l.teacher?.displayName,
            classroom: l.classroom?.name,
            isCancelled: l.isCancelled,
            isSubstitution: l.isSubstitution,
            note: note
        )
    }
}
