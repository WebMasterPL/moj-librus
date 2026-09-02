import SwiftUI

struct MainTabView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        TabView {
            NavigationStack { DashboardView() }
                .tabItem { Label("Pulpit", systemImage: "house.fill") }

            NavigationStack { GradesView() }
                .tabItem { Label("Oceny", systemImage: "checkmark.seal.fill") }
                .badge(repo.unseenGradeCount)

            NavigationStack { TimetableView() }
                .tabItem { Label("Plan", systemImage: "calendar") }

            NavigationStack { AttendanceView() }
                .tabItem { Label("Frekwencja", systemImage: "person.crop.circle.badge.checkmark") }

            NavigationStack { MoreView() }
                .tabItem { Label("Więcej", systemImage: "ellipsis.circle.fill") }
                .badge(repo.unreadAnnouncementCount + repo.unreadMessageCount)
        }
    }
}

struct MoreView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AnnouncementsView()
                } label: {
                    Label("Ogłoszenia", systemImage: "megaphone.fill")
                        .badge(repo.unreadAnnouncementCount)
                }
                NavigationLink {
                    EventsView()
                } label: {
                    Label("Terminarz", systemImage: "calendar.badge.clock")
                        .badge(repo.upcomingEventCount)
                }
                NavigationLink {
                    NotesView()
                } label: {
                    Label("Uwagi", systemImage: "note.text")
                        .badge(repo.notes.count)
                }
                NavigationLink {
                    MessagesView()
                } label: {
                    Label("Wiadomości", systemImage: "envelope.fill")
                        .badge(repo.unreadMessageCount)
                }
            }
            Section {
                NavigationLink {
                    BellScheduleView()
                } label: {
                    Label("Rozkład dzwonków", systemImage: "bell.fill")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Ustawienia", systemImage: "gearshape.fill")
                }
            }
        }
        .navigationTitle("Więcej")
    }
}
