import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(DataRepository.self) private var repo

    @State private var showLogoutConfirm = false

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            Section("Konto") {
                LabeledContent("Uczeń", value: repo.studentName.isEmpty ? "—" : repo.studentName)
                if let className = repo.schoolYear.className {
                    LabeledContent("Klasa", value: className)
                }
                if let tutor = repo.schoolYear.tutor {
                    LabeledContent("Wychowawca", value: tutor)
                }
                if let login = currentLogin {
                    LabeledContent("Login", value: login)
                }
                LabeledContent("Bieżący semestr", value: "\(repo.currentSemester)")
                if let sync = repo.lastSync {
                    LabeledContent("Ostatnia synchronizacja", value: sync.formattedPL("d MMM yyyy, HH:mm"))
                }
            }

            Section {
                Button {
                    Task {
                        await repo.refreshCore()
                        await repo.loadTimetable(weekStart: LibrusDate.weekStart())
                    }
                } label: {
                    Label("Odśwież wszystko", systemImage: "arrow.clockwise")
                }
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Diagnostyka połączenia", systemImage: "stethoscope")
                }
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Label("Wyloguj się", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Wylogowanie usuwa dane logowania z Keychaina oraz lokalną pamięć podręczną.")
            }

            Section("O aplikacji") {
                LabeledContent("Wersja", value: version)
                Text("Nieoficjalny klient Librus Synergia. Do użytku własnego. Łączy się bezpośrednio z api.librus.pl.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Ustawienia")
        .confirmationDialog("Wylogować się?", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("Wyloguj", role: .destructive) {
                Task { await app.logOut() }
            }
            Button("Anuluj", role: .cancel) {}
        }
    }

    private var currentLogin: String? {
        Credentials.load()?.login
    }
}
