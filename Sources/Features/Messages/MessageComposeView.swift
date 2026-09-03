import SwiftUI

/// Compose a new Synergia message. Librus picks recipients in two steps —
/// first a category (Nauczyciele, Pedagog…), then the people inside it — so the
/// picker mirrors that. Sending is confirmed explicitly before it leaves the device.
struct MessageComposeView: View {
    @Environment(DataRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    @State private var categories: MessagesClient.RecipientList?
    @State private var chosenCategory: MessagesClient.Recipient?
    @State private var people: [MessagesClient.Recipient] = []
    @State private var peopleField: String?
    @State private var peopleAllowMultiple = true
    @State private var selected: Set<String> = []

    @State private var subject = ""
    @State private var text = ""
    @State private var loading = true
    @State private var sending = false
    @State private var errorText: String?
    @State private var confirm = false

    private var selectedNames: String {
        people.filter { selected.contains($0.id) }.map(\.name).joined(separator: ", ")
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
                    } else if let categories, !categories.people.isEmpty {
                        NavigationLink {
                            CategoryPicker(
                                categories: categories.people,
                                chosenCategory: $chosenCategory,
                                people: $people,
                                peopleField: $peopleField,
                                peopleAllowMultiple: $peopleAllowMultiple,
                                selected: $selected
                            )
                            .environment(repo)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.isEmpty ? "Wybierz odbiorcę" : selectedNames)
                                    .foregroundStyle(selected.isEmpty ? Color.secondary : Color.primary)
                                    .lineLimit(2)
                                if let chosenCategory, !selected.isEmpty {
                                    Text(chosenCategory.name)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text(errorText ?? "Nie udało się wczytać odbiorców.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                Section("Temat") {
                    TextField("Temat", text: $subject)
                }

                Section("Treść") {
                    TextEditor(text: $text).frame(minHeight: 180)
                }

                if let errorText, categories != nil {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Color.negative)
                            .textSelection(.enabled)
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
            .task { await loadCategories() }
        }
    }

    private func loadCategories() async {
        loading = true
        let result = await repo.loadRecipientCategories()
        categories = result.list
        errorText = result.error
        loading = false
    }

    private func send() {
        sending = true
        errorText = nil
        Task {
            let category = chosenCategory.map {
                (field: categories?.field ?? "adresat", id: $0.id)
            }
            let failure = await repo.sendMessage(
                to: Array(selected), subject: subject, body: text,
                field: peopleField, category: category)
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

// MARK: - Step 1: category

private struct CategoryPicker: View {
    @Environment(DataRepository.self) private var repo
    let categories: [MessagesClient.Recipient]
    @Binding var chosenCategory: MessagesClient.Recipient?
    @Binding var people: [MessagesClient.Recipient]
    @Binding var peopleField: String?
    @Binding var peopleAllowMultiple: Bool
    @Binding var selected: Set<String>

    var body: some View {
        List(categories) { category in
            NavigationLink {
                PeoplePicker(
                    category: category,
                    chosenCategory: $chosenCategory,
                    people: $people,
                    peopleField: $peopleField,
                    allowsMultiple: $peopleAllowMultiple,
                    selected: $selected
                )
                .environment(repo)
            } label: {
                Text(category.name).lineLimit(2)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Kategoria odbiorcy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Step 2: people in that category

private struct PeoplePicker: View {
    @Environment(DataRepository.self) private var repo
    @Environment(\.dismiss) private var dismiss

    let category: MessagesClient.Recipient
    @Binding var chosenCategory: MessagesClient.Recipient?
    @Binding var people: [MessagesClient.Recipient]
    @Binding var peopleField: String?
    @Binding var allowsMultiple: Bool
    @Binding var selected: Set<String>

    @State private var loading = true
    @State private var errorText: String?
    @State private var search = ""

    private var filtered: [MessagesClient.Recipient] {
        guard !search.isEmpty else { return people }
        return people.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("Wczytywanie osób…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if people.isEmpty {
                ScrollView {
                    Text(errorText ?? "Brak osób w tej kategorii.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Space.lg)
                }
            } else {
                List(filtered) { person in
                    Button {
                        Haptics.selection()
                        if allowsMultiple {
                            if selected.contains(person.id) {
                                selected.remove(person.id)
                            } else {
                                selected.insert(person.id)
                            }
                        } else {
                            selected = [person.id]
                            dismiss()
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
                .searchable(text: $search, prompt: "Szukaj osoby")
            }
        }
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        chosenCategory = category
        selected = []
        loading = true
        let result = await repo.loadRecipients(inCategory: category.id)
        people = result.list?.people ?? []
        peopleField = result.list?.field
        allowsMultiple = result.list?.allowsMultiple ?? true
        errorText = result.error
        loading = false
    }
}
