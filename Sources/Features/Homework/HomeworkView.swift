import SwiftUI

struct HomeworkView: View {
    @Environment(DataRepository.self) private var repo

    private var grouped: [(key: String, items: [HomeworkItem])] {
        let groups = Dictionary(grouping: repo.homework) { item -> String in
            guard let due = item.dueDate else { return "Bez terminu" }
            return due.dayMonthYear
        }
        return groups
            .sorted { lhs, rhs in
                (lhs.value.first?.dueDate ?? .distantFuture) < (rhs.value.first?.dueDate ?? .distantFuture)
            }
            .map { (key: $0.key, items: $0.value) }
    }

    var body: some View {
        List {
            if repo.homework.isEmpty {
                EmptyStateView(systemImage: "book.closed", title: "Brak zadań domowych")
            }
            ForEach(grouped, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.topic.isEmpty ? "(bez tematu)" : item.topic)
                                .font(.callout.weight(.medium))
                            if !item.text.isEmpty {
                                Text(item.text).font(.footnote).foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            HStack(spacing: 8) {
                                if let subject = item.subject { Text(subject) }
                                if let teacher = item.teacher { Text(teacher) }
                            }
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Zadania domowe")
        .refreshable { await repo.refreshCore() }
    }
}
