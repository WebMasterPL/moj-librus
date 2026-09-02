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
                row("Ogłoszenia", "megaphone.fill", .orange, badge: repo.unreadAnnouncementCount) {
                    AnnouncementsView()
                }
                row("Terminarz", "calendar.badge.clock", .red, badge: repo.upcomingEventCount) {
                    EventsView()
                }
                row("Uwagi", "exclamationmark.bubble.fill", .purple, badge: repo.notes.count) {
                    NotesView()
                }
                row("Wiadomości", "envelope.fill", .blue, badge: repo.unreadMessageCount) {
                    MessagesView()
                }
            }
            Section {
                row("Rozkład dzwonków", "bell.fill", .teal) { BellScheduleView() }
                row("Ustawienia", "gearshape.fill", .gray) { SettingsView() }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appGroupedBackground.ignoresSafeArea())
        .navigationTitle("Więcej")
    }

    @ViewBuilder
    private func row<Destination: View>(
        _ title: String, _ icon: String, _ tint: Color, badge: Int = 0,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: Theme.Space.md) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(title)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
