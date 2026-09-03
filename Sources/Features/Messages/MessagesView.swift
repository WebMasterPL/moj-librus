import SwiftUI

struct MessagesView: View {
    @Environment(DataRepository.self) private var repo
    @State private var didLoad = false
    @State private var showCompose = false

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
                let unread = !repo.isMessageRead(message)
                NavigationLink {
                    MessageDetailView(message: message)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Space.md) {
                        Circle()
                            .fill(unread ? Color.accentColor : Color.clear)
                            .frame(width: 8, height: 8)
                            .padding(.top, 6)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(message.correspondent)
                                    .font(.callout.weight(unread ? .semibold : .regular))
                                    .lineLimit(1)
                                Spacer(minLength: Theme.Space.sm)
                                if message.hasAttachments {
                                    Image(systemName: "paperclip").font(.caption2).foregroundStyle(.secondary)
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
                    .padding(.vertical, 2)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        Haptics.soft()
                        repo.setMessageRead(message, read: unread)
                    } label: {
                        Label(unread ? "Przeczytane" : "Nieprzeczytane",
                              systemImage: unread ? "envelope.open" : "envelope.badge")
                    }
                    .tint(unread ? .accentColor : .gray)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Wiadomości")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showCompose = true
                } label: {
                    Label("Nowa wiadomość", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            MessageComposeView().environment(repo)
        }
        .refreshable { await repo.loadMessages() }
        .task {
            if !didLoad {
                didLoad = true
                await repo.loadMessages()
            }
        }
        .onDisappear { repo.markMessagesSeen() }
    }
}

struct MessageDetailView: View {
    @Environment(DataRepository.self) private var repo
    let message: MessageItem

    @State private var text: String?
    @State private var senderLoginId: String?
    @State private var loading = true
    @State private var showReply = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text(message.subject.isEmpty ? "(bez tematu)" : message.subject)
                    .font(.title2.weight(.bold))
                HStack(spacing: Theme.Space.md) {
                    Label(message.correspondent, systemImage: "person.fill")
                    if let date = message.sentDate { Label(date.dayMonthYear, systemImage: "calendar") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider().padding(.vertical, Theme.Space.xs)

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Theme.Space.xl)
                } else if let text, !text.isEmpty {
                    Text(text).font(.body).textSelection(.enabled)
                } else {
                    Text("Nie udało się wczytać treści wiadomości.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.lg)
        }
        .screenBackground()
        .navigationTitle("Wiadomość")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let senderLoginId, !senderLoginId.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showReply = true
                    } label: {
                        Label("Odpowiedz", systemImage: "arrowshape.turn.up.left")
                    }
                }
            }
        }
        .sheet(isPresented: $showReply) {
            if let senderLoginId {
                MessageReplyView(
                    recipientName: message.correspondent,
                    recipientLoginId: senderLoginId,
                    quotedSubject: message.subject
                )
                .environment(repo)
            }
        }
        .task {
            let content = await repo.loadMessageContent(message.id)
            text = content?.text
            senderLoginId = content?.senderLoginId
            loading = false
        }
    }
}

struct MessageReplyView: View {
    let recipientName: String
    let recipientLoginId: String
    let quotedSubject: String

    @Environment(DataRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var subject: String
    @State private var body_ = ""
    @State private var sending = false
    @State private var errorText: String?
    @State private var confirm = false

    init(recipientName: String, recipientLoginId: String, quotedSubject: String) {
        self.recipientName = recipientName
        self.recipientLoginId = recipientLoginId
        self.quotedSubject = quotedSubject
        let base = quotedSubject.hasPrefix("RE:") || quotedSubject.hasPrefix("Re:")
            ? quotedSubject : "RE: \(quotedSubject)"
        _subject = State(initialValue: base)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Do") { Text(recipientName) }
                Section("Temat") {
                    TextField("Temat", text: $subject)
                }
                Section("Treść") {
                    TextEditor(text: $body_)
                        .frame(minHeight: 180)
                }
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Odpowiedź")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Wyślij") { confirm = true }
                        .disabled(body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                }
            }
            .overlay {
                if sending { ProgressView("Wysyłanie…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .confirmationDialog(
                "Wysłać wiadomość do: \(recipientName)?",
                isPresented: $confirm, titleVisibility: .visible
            ) {
                Button("Wyślij") { send() }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Temat: \(subject)")
            }
        }
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            let error = await repo.sendReply(to: recipientLoginId, subject: subject, body: body_)
            sending = false
            if let error {
                errorText = error
            } else {
                dismiss()
            }
        }
    }
}
