import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app

    @State private var login = ""
    @State private var password = ""
    @FocusState private var focus: Field?

    private enum Field { case login, password }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("Mój Librus")
                    .font(.largeTitle.bold())
                Text("Zaloguj się Kontem LIBRUS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("e-mail + hasło z konto.librus.pl (jak w oficjalnej apce), nie sam login szkolny")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                TextField("E-mail Konta LIBRUS", text: $login)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .login)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }

                SecureField("Hasło", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(attemptLogin)
            }
            .textFieldStyle(.roundedBorder)

            if let error = app.loginError {
                ErrorBanner(message: error)
            }

            Button(action: attemptLogin) {
                if app.isLoggingIn {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Zaloguj").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(login.isEmpty || password.isEmpty || app.isLoggingIn)

            Text("Logowanie przez portal.librus.pl (jak w oficjalnej apce). Dane logowania są przechowywane wyłącznie w Keychainie tego urządzenia.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(24)
        .onAppear { focus = .login }
    }

    private func attemptLogin() {
        guard !login.isEmpty, !password.isEmpty else { return }
        focus = nil
        Task { await app.logIn(login: login, password: password) }
    }
}
