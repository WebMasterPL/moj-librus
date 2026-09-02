import SwiftUI

@main
struct MojLibrusApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(.accentColor)
        }
    }
}
