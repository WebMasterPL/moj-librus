import SwiftUI

struct AttendanceView: View {
    @Environment(DataRepository.self) private var repo

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: columns, spacing: 12) {
                    statTile("Frekwencja",
                             value: repo.attendanceSummary.attendancePercent.map { String(format: "%.0f%%", $0) } ?? "—",
                             color: .green)
                    statTile("Nieobecności", value: "\(repo.attendanceSummary.absent)", color: .red)
                    statTile("Usprawiedliwione", value: "\(repo.attendanceSummary.absentExcused)", color: .orange)
                    statTile("Spóźnienia", value: "\(repo.attendanceSummary.belated)", color: .yellow)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if repo.attendanceItems.isEmpty {
                Section {
                    EmptyStateView(systemImage: "person.crop.circle.badge.checkmark",
                                   title: "Brak wpisów frekwencji")
                }
            } else {
                Section("Wpisy") {
                    ForEach(repo.attendanceItems) { item in
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
