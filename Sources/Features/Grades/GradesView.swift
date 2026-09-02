import SwiftUI

struct GradesView: View {
    @Environment(DataRepository.self) private var repo
    @State private var filter: SemesterFilter = .current

    private var current: Int { repo.currentSemester }

    private var visibleSubjects: [SubjectGrades] {
        repo.subjectGrades
            .map { subject -> (SubjectGrades, [GradeItem]) in
                (subject, subject.filtered(filter, current: current))
            }
            .filter { !$0.1.isEmpty }
            .map { $0.0 }
    }

    private var overallAverage: Double? {
        let averages = visibleSubjects.compactMap { $0.average(filter, current: current) }
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }

    var body: some View {
        List {
            if let error = repo.lastError {
                Section { ErrorBanner(message: error) { Task { await repo.refreshCore() } } }
            }

            Section {
                Picker("Semestr", selection: $filter) {
                    ForEach(SemesterFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)

                if let avg = overallAverage {
                    HStack {
                        Text("Średnia ze średnich przedmiotów")
                        Spacer()
                        Text(GradeMath.format(avg))
                            .font(.headline)
                            .foregroundStyle(gradeColor(for: avg))
                    }
                }
            }

            if visibleSubjects.isEmpty {
                Section {
                    EmptyStateView(systemImage: "checkmark.seal", title: "Brak ocen",
                                   message: "Zmień semestr lub pociągnij w dół, aby odświeżyć.")
                }
            }

            ForEach(visibleSubjects) { subject in
                Section {
                    ForEach(subject.filtered(filter, current: current)) { grade in
                        NavigationLink(value: grade) { GradeRow(grade: grade) }
                    }
                } header: {
                    HStack {
                        Text(subject.subjectName)
                        Spacer()
                        if let avg = subject.average(filter, current: current) {
                            Text("śr. \(GradeMath.format(avg))")
                                .foregroundStyle(gradeColor(for: avg))
                        }
                    }
                }
            }
        }
        .navigationTitle("Oceny")
        .navigationDestination(for: GradeItem.self) { GradeDetailView(grade: $0) }
        .refreshable { await repo.refreshCore() }
    }
}

struct GradeRow: View {
    let grade: GradeItem

    var body: some View {
        HStack(spacing: 12) {
            Text(grade.raw)
                .font(.headline.monospacedDigit())
                .foregroundStyle(gradeColor(for: grade.value))
                .frame(minWidth: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.categoryName.isEmpty ? Self.label(for: grade.kind) : grade.categoryName)
                    .font(.callout)
                HStack(spacing: 8) {
                    if grade.weight > 0 {
                        Text("waga \(GradeMath.format(grade.weight))")
                    }
                    if let date = grade.date {
                        Text(date.dayMonthShort)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    static func label(for kind: GradeKind) -> String {
        switch kind {
        case .normal: return "Ocena"
        case .semesterProposed: return "Propozycja śródroczna"
        case .semesterFinal: return "Ocena śródroczna"
        case .yearProposed: return "Propozycja roczna"
        case .yearFinal: return "Ocena roczna"
        }
    }
}

struct GradeDetailView: View {
    let grade: GradeItem

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Ocena")
                    Spacer()
                    Text(grade.raw).font(.title2.bold())
                        .foregroundStyle(gradeColor(for: grade.value))
                }
                if let value = grade.value {
                    row("Wartość", GradeMath.format(value))
                }
                if grade.weight > 0 { row("Waga", GradeMath.format(grade.weight)) }
                row("Liczona do średniej", grade.countsToAverage ? "Tak" : "Nie")
                row("Rodzaj", GradeRow.label(for: grade.kind))
            }
            Section {
                row("Przedmiot", grade.subjectName)
                if !grade.categoryName.isEmpty { row("Kategoria", grade.categoryName) }
                if !grade.teacherName.isEmpty { row("Nauczyciel", grade.teacherName) }
                if let date = grade.date { row("Data", date.dayMonthYear) }
                row("Semestr", "\(grade.semester)")
            }
            if let comment = grade.comment {
                Section("Komentarz") { Text(comment) }
            }
        }
        .navigationTitle("Szczegóły oceny")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
