import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch app.phase {
            case .loading:
                ProgressView("Wczytywanie…")
            case .loggedOut:
                LoginView()
            case .loggedIn:
                if let repo = app.repository {
                    MainTabView()
                        .environment(repo)
                } else {
                    ProgressView()
                }
            }
        }
        .animation(.default, value: app.phase)
        .task {
            if case .loading = app.phase {
                await app.bootstrap()
            }
        }
    }
}
