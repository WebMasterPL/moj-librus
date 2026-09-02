import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(DataRepository.self) private var repo

    @State private var showLogoutConfirm = false
    @AppStorage(BackgroundRefresh.enabledKey) private var notifyNewGrades = false

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
                    Haptics.tap()
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
                Toggle(isOn: $notifyNewGrades) {
                    Label("Powiadomienia o nowych ocenach", systemImage: "bell.badge")
                }
                if notifyNewGrades {
                    Button {
                        Task { await NotificationManager.sendTestNotification() }
                    } label: {
                        Label("Wyślij powiadomienie testowe", systemImage: "paperplane")
                    }
                }
            } header: {
                Text("Powiadomienia")
            } footer: {
                Text("Eksperymentalne. iOS sam decyduje, kiedy odświeżyć aplikację w tle — dla apek sideloadowanych bywa to rzadko. Plakietka „nowe” przy ocenach działa zawsze.")
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
                LabeledContent("Widżet (App Group)", value: SharedStore.status)
                    .font(.caption)
                Text("Nieoficjalny klient Librus Synergia. Do użytku własnego. Łączy się bezpośrednio z api.librus.pl.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Ustawienia")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.accentColor)
        .onChange(of: notifyNewGrades) { _, on in
            Task {
                if on {
                    let granted = await NotificationManager.requestAuthorization()
                    if granted {
                        BackgroundRefresh.scheduleIfEnabled()
                    } else {
                        notifyNewGrades = false
                    }
                } else {
                    BackgroundRefresh.cancel()
                }
            }
        }
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
