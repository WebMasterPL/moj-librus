import SwiftUI

/// Compose a new Synergia message: pick recipients off the Librus compose form,
/// then POST it back. Sending is confirmed explicitly before it leaves the device.
struct MessageComposeView: View {
    @Environment(DataRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var recipients: [MessagesClient.Recipient] = []
    @State private var selected: Set<String> = []
    @State private var subject = ""
    @State private var text = ""
    @State private var loading = true
    @State private var sending = false
    @State private var errorText: String?
    @State private var confirm = false

    private var selectedNames: String {
        recipients.filter { selected.contains($0.id) }
            .map(\.name)
            .joined(separator: ", ")
    }

    private var canSend: Bool {
        !selected.isEmpty
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !sending
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Do") {
                    if loading {
                        HStack(spacing: Theme.Space.sm) {
                            ProgressView()
                            Text("Wczytywanie odbiorców…").foregroundStyle(.secondary)
                        }
                    } else if recipients.isEmpty {
                        Text(errorText ?? "Nie udało się wczytać listy odbiorców.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        NavigationLink {
                            RecipientPicker(recipients: recipients, selected: $selected)
                        } label: {
                            Text(selected.isEmpty ? "Wybierz odbiorców" : selectedNames)
                                .foregroundStyle(selected.isEmpty ? Color.secondary : Color.primary)
                                .lineLimit(2)
                        }
                    }
                }

                Section("Temat") {
                    TextField("Temat", text: $subject)
                }

                Section("Treść") {
                    TextEditor(text: $text).frame(minHeight: 180)
                }

                if let errorText, !recipients.isEmpty {
                    Section {
                        Text(errorText).font(.footnote).foregroundStyle(Color.negative)
                    }
                }
            }
            .navigationTitle("Nowa wiadomość")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Wyślij") { confirm = true }.disabled(!canSend)
                }
            }
            .overlay {
                if sending {
                    ProgressView("Wysyłanie…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
            .confirmationDialog("Wysłać wiadomość?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Wyślij") { send() }
                Button("Anuluj", role: .cancel) {}
            } message: {
                Text("Do: \(selectedNames)\nTemat: \(subject.isEmpty ? "(bez tematu)" : subject)")
            }
            .task { await loadRecipients() }
        }
    }

    private func loadRecipients() async {
        loading = true
        let result = await repo.loadRecipients()
        recipients = result.people
        errorText = result.error
        loading = false
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            let failure = await repo.sendMessage(
                to: Array(selected), subject: subject, body: text)
            sending = false
            if let failure {
                errorText = failure
                Haptics.warning()
            } else {
                Haptics.success()
                dismiss()
            }
        }
    }
}

private struct RecipientPicker: View {
    let recipients: [MessagesClient.Recipient]
    @Binding var selected: Set<String>
    @State private var search = ""

    private var filtered: [MessagesClient.Recipient] {
        guard !search.isEmpty else { return recipients }
        return recipients.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(filtered) { person in
            Button {
                Haptics.selection()
                if selected.contains(person.id) {
                    selected.remove(person.id)
                } else {
                    selected.insert(person.id)
                }
            } label: {
                HStack(spacing: Theme.Space.md) {
                    Text(person.name)
                        .foregroundStyle(Color.primary)
                        .lineLimit(2)
                    Spacer(minLength: Theme.Space.sm)
                    if selected.contains(person.id) {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .searchable(text: $search, prompt: "Szukaj odbiorcy")
        .navigationTitle("Odbiorcy (\(selected.count))")
        .navigationBarTitleDisplayMode(.inline)
    }
}
