import SwiftUI

struct AnnouncementsView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        List {
            if repo.announcements.isEmpty {
                EmptyStateView(systemImage: "megaphone", title: "Brak ogłoszeń")
            }
            ForEach(repo.announcements) { item in
                NavigationLink(value: item) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if !repo.isAnnouncementRead(item) {
                                Circle().fill(.tint).frame(width: 8, height: 8)
                            }
                            Text(item.subject.isEmpty ? "(bez tematu)" : item.subject)
                                .font(.callout.weight(repo.isAnnouncementRead(item) ? .regular : .semibold))
                                .lineLimit(2)
                        }
                        HStack(spacing: 8) {
                            if let author = item.author { Text(author) }
                            if let date = item.date { Text(date.dayMonthYear) }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Ogłoszenia")
        .navigationDestination(for: AnnouncementItem.self) { item in
            AnnouncementDetailView(item: item)
                .onAppear { repo.markAnnouncementRead(item) }
        }
        .refreshable { await repo.refreshCore() }
    }
}

struct AnnouncementDetailView: View {
    let item: AnnouncementItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(item.subject).font(.title3.bold())
                HStack(spacing: 8) {
                    if let author = item.author { Label(author, systemImage: "person") }
                    if let date = item.date { Label(date.dayMonthYear, systemImage: "calendar") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                Text(item.content)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Ogłoszenie")
        .navigationBarTitleDisplayMode(.inline)
    }
}
