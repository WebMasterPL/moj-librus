import SwiftUI

struct TimetableView: View {
    @Environment(DataRepository.self) private var repo

    @State private var weekStart = LibrusDate.weekStart()
    @State private var isLoading = false

    private var weekKey: String { LibrusDate.ymdString(weekStart) }
    private var days: [TimetableDay] { repo.timetableWeeks[weekKey] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            weekSwitcher

            if days.isEmpty {
                if isLoading {
                    ProgressView().frame(maxHeight: .infinity)
                } else {
                    EmptyStateView(systemImage: "calendar", title: "Brak planu",
                                   message: "Dla tego tygodnia nie ma danych.")
                    .frame(maxHeight: .infinity)
                }
            } else {
                List {
                    ForEach(days) { day in
                        Section(day.date.weekdayName.capitalized + " · " + day.date.dayMonthShort) {
                            if day.entries.isEmpty {
                                Text("Brak lekcji").foregroundStyle(.secondary)
                            } else {
                                ForEach(day.entries) { LessonRow(entry: $0) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Plan lekcji")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weekKey) { await loadIfNeeded() }
        .refreshable { await load() }
    }

    private var weekSwitcher: some View {
        HStack {
            Button { shift(-7) } label: { Image(systemName: "chevron.left") }
            Spacer()
            VStack(spacing: 1) {
                Text("\(weekStart.dayMonthShort) – \(LibrusDate.addDays(6, to: weekStart).dayMonthShort)")
                    .font(.subheadline.bold())
                if LibrusDate.isSameDay(weekStart, LibrusDate.weekStart()) {
                    Text("bieżący tydzień").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button { shift(7) } label: { Image(systemName: "chevron.right") }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func shift(_ days: Int) {
        weekStart = LibrusDate.addDays(days, to: weekStart)
    }

    private func loadIfNeeded() async {
        if repo.timetableWeeks[weekKey] == nil { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        await repo.loadTimetable(weekStart: weekStart)
    }
}

struct LessonRow: View {
    let entry: TimetableEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("\(entry.lessonNo)").font(.headline)
                Text(entry.start).font(.caption2).foregroundStyle(.secondary)
                Text(entry.end).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subject)
                    .font(.callout.weight(.medium))
                    .strikethrough(entry.isCancelled)
                    .foregroundStyle(entry.isCancelled ? .secondary : .primary)
                HStack(spacing: 8) {
                    if let teacher = entry.teacher { Text(teacher) }
                    if let room = entry.classroom { Text("sala \(room)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let note = entry.note {
                    Text(note)
                        .font(.caption2.bold())
                        .foregroundStyle(entry.isCancelled ? .red : .orange)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}
