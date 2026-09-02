import SwiftUI

struct NotesView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        List {
            if repo.notes.isEmpty {
                EmptyStateView(systemImage: "note.text", title: "Brak uwag")
            }
            ForEach(repo.notes) { note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: note.kind))
                            .foregroundStyle(color(for: note.kind))
                        if let category = note.category {
                            Text(category).font(.caption.bold()).foregroundStyle(color(for: note.kind))
                        }
                        Spacer()
                        if let date = note.date {
                            Text(date.dayMonthYear).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(note.text).font(.callout)
                    if let teacher = note.teacher {
                        Text(teacher).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Uwagi")
        .refreshable { await repo.refreshCore() }
    }

    private func icon(for kind: NoteItem.Kind) -> String {
        switch kind {
        case .positive: return "hand.thumbsup.fill"
        case .negative: return "hand.thumbsdown.fill"
        case .neutral: return "info.circle.fill"
        }
    }

    private func color(for kind: NoteItem.Kind) -> Color {
        switch kind {
        case .positive: return .green
        case .negative: return .red
        case .neutral: return .secondary
        }
    }
}
