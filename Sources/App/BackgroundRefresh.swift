import Foundation
import BackgroundTasks

/// Opt-in background check for new grades. iOS decides if/when this actually runs
/// and throttles sideloaded apps heavily, so it's best-effort — the in-app
/// "nowe" badge is the reliable path.
enum BackgroundRefresh {
    static let taskIdentifier = "com.olekd.mojlibrus.refresh"
    static let enabledKey = "notifyNewGrades"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// Call once, before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func scheduleIfEnabled() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        scheduleIfEnabled() // chain the next run

        let work = Task {
            await runGradeCheck()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Fetch grades, notify about any not yet seen, then mark them seen.
    static func runGradeCheck() async {
        guard isEnabled, SeenGrades.hasBaseline else { return }

        let session = LibrusSession()
        guard await session.isLoggedIn else { return }
        let api = LibrusAPI(session: session)

        guard let rawGrades = await api.grades() else { return }

        var subjectByID: [Int: RawSubject] = [:]
        if let subjects = await api.subjects() {
            subjectByID = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        }

        let allIDs = Set(rawGrades.map(\.id))
        let newIDs = SeenGrades.newIDs(in: allIDs)
        guard !newIDs.isEmpty else { return }

        let newGrades: [GradeItem] = rawGrades
            .filter { newIDs.contains($0.id) }
            .map { g in
                GradeItem(
                    id: g.id, raw: g.grade, value: GradeMath.numericValue(of: g.grade),
                    weight: 0, semester: g.semester, kind: .normal, categoryName: "",
                    teacherName: "", subjectId: g.subject?.id ?? -1,
                    subjectName: g.subject.flatMap { subjectByID[$0.id]?.name } ?? "przedmiot",
                    date: nil, comment: nil
                )
            }

        await NotificationManager.notifyNewGrades(newGrades)
        SeenGrades.merge(newIDs)
    }
}
