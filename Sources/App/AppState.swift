import Foundation
import Observation

/// Top-level app state: whether we have a session, and the shared repository.
@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case loading
        case loggedOut
        case loggedIn
    }

    private(set) var phase: Phase = .loading
    let session = LibrusSession()
    private(set) var repository: DataRepository?

    var loginError: String?
    var isLoggingIn = false

    func bootstrap() async {
        if await session.isLoggedIn {
            let repo = DataRepository(session: session)
            repository = repo
            phase = .loggedIn
            await repo.refreshCore()
        } else {
            phase = .loggedOut
        }
    }

    func logIn(login: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            try await session.logIn(
                login: login.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            let repo = DataRepository(session: session)
            repository = repo
            phase = .loggedIn
            await repo.refreshCore()
        } catch {
            loginError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logOut() async {
        repository?.clearLocal()
        await session.logOut()
        repository = nil
        phase = .loggedOut
    }
}
