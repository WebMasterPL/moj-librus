import SwiftUI

struct EventsView: View {
    @Environment(DataRepository.self) private var repo
    @State private var showPast = false

    private var visible: [CalendarEvent] {
        showPast ? repo.events : repo.events.filter { !$0.isPast }
    }

    private var grouped: [(key: String, items: [CalendarEvent])] {
        let groups = Dictionary(grouping: visible) { ev -> String in
            ev.date?.dayMonthYear ?? "Bez daty"
        }
        return groups
            .sorted { ($0.value.first?.date ?? .distantFuture) < ($1.value.first?.date ?? .distantFuture) }
            .map { (key: $0.key, items: $0.value) }
    }

    var body: some View {
        List {
            if repo.events.isEmpty {
                EmptyStateView(systemImage: "calendar.badge.clock", title: "Brak wpisów w terminarzu")
            }

            if !repo.events.isEmpty {
                Toggle("Pokaż minione", isOn: $showPast)
            }

            ForEach(grouped, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.items) { ev in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                if let category = ev.category {
                                    Text(category)
                                        .font(.caption.bold())
                                        .foregroundStyle(.tint)
                                }
                                if let subject = ev.subject {
                                    Text(subject).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let time = ev.time {
                                    Text(time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                } else if let no = ev.lessonNo {
                                    Text("lekcja \(no)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Text(ev.content.isEmpty ? "(bez opisu)" : ev.content)
                                .font(.callout)
                            if let teacher = ev.teacher {
                                Text(teacher).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Terminarz")
        .refreshable { await repo.refreshCore() }
    }
}
