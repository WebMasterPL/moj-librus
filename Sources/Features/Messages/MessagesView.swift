import SwiftUI

struct MessagesView: View {
    @Environment(DataRepository.self) private var repo
    @State private var didLoad = false

    var body: some View {
        List {
            if let error = repo.messagesError {
                Section {
                    ErrorBanner(message: error) { Task { await repo.loadMessages() } }
                    Text("Skrzynka wiadomości korzysta z osobnego, mniej stabilnego kanału Librusa. Reszta aplikacji działa niezależnie.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if repo.messagesInbox.isEmpty && repo.messagesError == nil {
                EmptyStateView(systemImage: "envelope", title: "Brak wiadomości",
                               message: didLoad ? nil : "Wczytywanie…")
            }

            ForEach(repo.messagesInbox) { message in
                NavigationLink(value: message) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if message.isUnread {
                                Circle().fill(.tint).frame(width: 8, height: 8)
                            }
                            Text(message.correspondent)
                                .font(.callout.weight(message.isUnread ? .semibold : .regular))
                            Spacer()
                            if message.hasAttachments {
                                Image(systemName: "paperclip").font(.caption).foregroundStyle(.secondary)
                            }
                            if let date = message.sentDate {
                                Text(date.dayMonthShort).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(message.subject.isEmpty ? "(bez tematu)" : message.subject)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
        .navigationTitle("Wiadomości")
        .navigationDestination(for: MessageItem.self) { MessageDetailView(message: $0) }
        .refreshable { await repo.loadMessages() }
        .task {
            if !didLoad {
                didLoad = true
                await repo.loadMessages()
            }
        }
    }
}

struct MessageDetailView: View {
    @Environment(DataRepository.self) private var repo
    let message: MessageItem

    @State private var body_: String?
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(message.subject.isEmpty ? "(bez tematu)" : message.subject)
                    .font(.title3.bold())
                HStack(spacing: 8) {
                    Label(message.correspondent, systemImage: "person")
                    if let date = message.sentDate { Label(date.dayMonthYear, systemImage: "calendar") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()

                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let text = body_, !text.isEmpty {
                    Text(text).font(.body).textSelection(.enabled)
                } else {
                    Text("Nie udało się wczytać treści wiadomości.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .navigationTitle("Wiadomość")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            body_ = await repo.loadMessageBody(message.id)
            loading = false
        }
    }
}
