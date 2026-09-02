import SwiftUI

struct MainTabView: View {
    @Environment(DataRepository.self) private var repo

    var body: some View {
        TabView {
            // Each tab's NavigationStack lives in its own view so that badge-count
            // changes (which re-render MainTabView.body) don't reset navigation.
            DashboardTab()
                .tabItem { Label("Pulpit", systemImage: "house.fill") }

            GradesTab()
                .tabItem { Label("Oceny", systemImage: "checkmark.seal.fill") }
                .badge(repo.unseenGradeCount)

            TimetableTab()
                .tabItem { Label("Plan", systemImage: "calendar") }

            AttendanceTab()
                .tabItem { Label("Frekwencja", systemImage: "person.crop.circle.badge.checkmark") }

            MoreTab()
                .tabItem { Label("Więcej", systemImage: "ellipsis.circle.fill") }
                .badge(repo.unreadAnnouncementCount + repo.unreadMessageCount)
        }
    }
}

private struct DashboardTab: View { var body: some View { NavigationStack { DashboardView() } } }
private struct GradesTab: View { var body: some View { NavigationStack { GradesView() } } }
private struct TimetableTab: View { var body: some View { NavigationStack { TimetableView() } } }
private struct AttendanceTab: View { var body: some View { NavigationStack { AttendanceView() } } }
private struct MoreTab: View { var body: some View { NavigationStack { MoreView() } } }

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
