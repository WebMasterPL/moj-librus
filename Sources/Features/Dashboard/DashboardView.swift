import SwiftUI

struct DashboardView: View {
    @Environment(DataRepository.self) private var repo

    private var todayEntries: [TimetableEntry] {
        let key = LibrusDate.ymdString(LibrusDate.weekStart())
        let today = repo.timetableWeeks[key]?.first { LibrusDate.isSameDay($0.date, Date()) }
        return today?.entries.filter { !$0.isCancelled } ?? []
    }

    private var recentGrades: [GradeItem] {
        repo.subjectGrades.flatMap(\.grades)
            .filter { $0.kind == .normal }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = repo.lastError {
                    ErrorBanner(message: error) {
                        Task { await repo.refreshCore() }
                    }
                }

                luckyNumberCard
                nextLessonsCard
                recentGradesCard
                countersRow
            }
            .padding(16)
        }
        .navigationTitle(repo.studentName.isEmpty ? "Pulpit" : repo.studentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if repo.isRefreshing { ProgressView() }
            }
        }
        .refreshable {
            await repo.refreshCore()
            await repo.loadTimetable(weekStart: LibrusDate.weekStart())
        }
        .task {
            if repo.timetableWeeks.isEmpty {
                await repo.loadTimetable(weekStart: LibrusDate.weekStart())
            }
        }
        .overlay(alignment: .bottom) {
            if let sync = repo.lastSync {
                Text("Zsynchronizowano \(sync.formattedPL("d MMM, HH:mm"))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }
        }
    }

    private var luckyNumberCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: "clover.fill")
                    .font(.title)
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Szczęśliwy numerek").font(.subheadline).foregroundStyle(.secondary)
                    if let lucky = repo.luckyNumber {
                        Text("\(lucky.number)").font(.title.bold())
                        if let day = lucky.day {
                            Text(day.dayMonthYear).font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("brak danych").font(.title3).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    private var nextLessonsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Dzisiaj", systemImage: "calendar")
                if todayEntries.isEmpty {
                    Text("Brak lekcji w planie na dziś.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(todayEntries.prefix(6)) { entry in
                        HStack(spacing: 12) {
                            Text(entry.start).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Text(entry.subject).font(.callout).strikethrough(entry.isCancelled)
                            Spacer()
                            if let room = entry.classroom {
                                Text(room).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentGradesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Ostatnie oceny", systemImage: "checkmark.seal")
                if recentGrades.isEmpty {
                    Text("Brak ocen.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(recentGrades) { grade in
                        HStack(spacing: 12) {
                            Text(grade.raw)
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(gradeColor(for: grade.value))
                                .frame(minWidth: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(grade.subjectName).font(.callout)
                                Text(grade.categoryName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let date = grade.date {
                                Text(date.dayMonthShort).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var countersRow: some View {
        HStack(spacing: 12) {
            counter(value: repo.unreadAnnouncementCount, label: "Ogłoszenia", system: "megaphone.fill")
            counter(value: repo.homework.count, label: "Zadania", system: "book.closed.fill")
            counter(value: repo.unreadMessageCount, label: "Wiadomości", system: "envelope.fill")
        }
    }

    private func counter(value: Int, label: String, system: String) -> some View {
        Card {
            VStack(spacing: 4) {
                Image(systemName: system).foregroundStyle(.tint)
                Text("\(value)").font(.title3.bold())
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
