import SwiftUI

struct AttendanceView: View {
    @Environment(DataRepository.self) private var repo
    @State private var filter: SemesterFilter = .current

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private var items: [AttendanceItem] {
        repo.attendanceItems.filter { filter.matches($0.semester ?? repo.currentSemester, current: repo.currentSemester) }
    }

    private var summary: AttendanceSummary {
        var s = AttendanceSummary()
        for item in items { s.counts[item.kind, default: 0] += 1 }
        return s
    }

    var body: some View {
        List {
            Section {
                Picker("Semestr", selection: $filter) {
                    ForEach(SemesterFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }

            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    statTile("Frekwencja",
                             value: summary.attendancePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                             color: .green)
                    statTile("Nieobecności", value: "\(summary.absent)", color: .red)
                    statTile("Usprawiedliwione", value: "\(summary.absentExcused)", color: .orange)
                    statTile("Spóźnienia", value: "\(summary.belated)", color: .yellow)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if items.isEmpty {
                Section {
                    EmptyStateView(systemImage: "person.crop.circle.badge.checkmark",
                                   title: "Brak wpisów frekwencji")
                }
            } else {
                Section("Wpisy") {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Text(item.typeShort)
                                .font(.caption.bold())
                                .frame(width: 34, height: 34)
                                .background((Color(librusHex: item.colorHex) ?? attendanceColor(item.kind)).opacity(0.2),
                                            in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.subjectName ?? item.typeName).font(.callout)
                                Text(item.typeName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let date = item.date {
                                    Text(date.dayMonthShort).font(.caption)
                                }
                                if let no = item.lessonNo {
                                    Text("lekcja \(no)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Frekwencja")
        .refreshable { await repo.refreshCore() }
    }

    private func statTile(_ label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }
}
