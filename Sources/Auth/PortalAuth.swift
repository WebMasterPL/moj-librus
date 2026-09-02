import Foundation

struct PortalTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiry: Double // seconds since 1970
}

struct SynergiaAccount: Decodable {
    let id: Int
    let login: String
    let accessToken: String
    let studentName: String?
    let group: String?
    let state: String?

    enum CodingKeys: String, CodingKey {
        case id, login, accessToken, studentName, group, state
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) { id = i }
        else { id = Int((try? c.decode(String.self, forKey: .id)) ?? "") ?? -1 }
        login = (try? c.decode(String.self, forKey: .login)) ?? ""
        accessToken = (try? c.decode(String.self, forKey: .accessToken)) ?? ""
        studentName = try? c.decode(String.self, forKey: .studentName)
        group = try? c.decode(String.self, forKey: .group)
        state = try? c.decode(String.self, forKey: .state)
    }
}

/// The Librus Portal OAuth flow: scrape + submit the login form, follow the
/// redirect chain to `app://librus?code=…`, exchange for portal tokens, then pull
/// per-Synergia-account bearer tokens.
actor PortalAuth {
    private let http: URLSession
    private let cookies = HTTPCookieStorage()

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookies
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        http = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil
        }
    }

    // MARK: - Public

    func logIn(login: String, password: String) async throws -> PortalTokens {
        let code = try await runLoginFlow(login: login, password: password)
        return try await exchange(body: [
            "client_id": Librus.portalClientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Librus.portalRedirectURI,
        ])
    }

    func refresh(refreshToken: String) async throws -> PortalTokens {
        try await exchange(body: [
            "client_id": Librus.portalClientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
    }

    func synergiaAccounts(portalToken: String) async throws -> [SynergiaAccount] {
        let data = try await portalGET(Librus.synergiaAccountsURL(), bearer: portalToken)
        struct Wrapper: Decodable { let accounts: [SynergiaAccount] }
        guard let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            throw APIError.decoding("SynergiaAccounts")
        }
        return wrapper.accounts
    }

    func freshSynergiaToken(login: String, portalToken: String) async throws -> String {
        let data = try await portalGET(Librus.synergiaAccountFreshURL(login: login), bearer: portalToken)
        guard let account = try? JSONDecoder().decode(SynergiaAccount.self, from: data),
              !account.accessToken.isEmpty else {
            throw APIError.tokenExpired
        }
        return account.accessToken
    }

    // MARK: - Login flow

    private func runLoginFlow(login: String, password: String) async throws -> String {
        cookies.removeCookies(since: .distantPast)

        // 1. Walk the redirect chain from the authorize URL to the login page.
        var url = Librus.portalAuthorizeURL
        var loginHTML: String?

        for _ in 0..<15 {
            let (data, response) = try await send(url, method: "GET",
                headers: ["X-Requested-With": Librus.portalRequestedWith])

            if let location = response.value(forHTTPHeaderField: "Location") {
                if let code = codeFromLocation(location) { return code }
                if location.contains("rejected_client") {
                    throw APIError.librus(code: "rejected_client", message: "Portal odrzucił klienta OAuth.")
                }
                url = absoluteURL(location, relativeTo: url)
                continue
            }

            let html = String(data: data, encoding: .utf8) ?? ""
            if html.contains("konto-librus/login/action") || html.contains("id=\"login\"") {
                loginHTML = html
                break
            }
            throw APIError.librus(code: "portal_flow", message: "Nieoczekiwana strona portalu przed logowaniem.")
        }

        guard let loginHTML else {
            throw APIError.librus(code: "portal_flow", message: "Nie znaleziono formularza logowania portalu.")
        }
        if loginHTML.range(of: "recaptcha|g-recaptcha|grecaptcha", options: .regularExpression) != nil {
            throw APIError.captchaNeeded
        }

        // 2. Submit the login form.
        let csrf = HTTP.firstMatch("name=\"csrf-token\"\\s+content=\"([^\"]+)\"", in: loginHTML)
            ?? HTTP.firstMatch("name=\"_token\"[^>]*value=\"([^\"]+)\"", in: loginHTML)
        var form = HTTP.hiddenInputs(in: loginHTML)
        form["email"] = login
        form["password"] = password
        if let csrf { form["_token"] = form["_token"] ?? csrf }

        var headers = [
            "X-Requested-With": Librus.portalRequestedWith,
            "Referer": "https://portal.librus.pl/konto-librus/login",
            "Origin": Librus.portalOrigin,
        ]
        if let csrf { headers["X-CSRF-TOKEN"] = csrf }

        let (postData, postResponse) = try await send(
            Librus.portalLoginActionURL, method: "POST", headers: headers, form: form)

        try assertLoginOK(data: postData, response: postResponse)

        // 3. Follow redirects from the login response to the code.
        var next = postResponse.value(forHTTPHeaderField: "Location")
        for _ in 0..<15 {
            guard let location = next else {
                throw APIError.invalidCredentials
            }
            if let code = codeFromLocation(location) { return code }

            let target = absoluteURL(location, relativeTo: Librus.portalOrigin)
            if target.contains("/konto-librus/login") && !target.contains("/action") {
                throw APIError.invalidCredentials
            }

            let (data, response) = try await send(target, method: "GET",
                headers: ["X-Requested-With": Librus.portalRequestedWith])

            if let loc = response.value(forHTTPHeaderField: "Location") {
                next = loc
                continue
            }
            // Landed on a page instead of redirecting — inspect it.
            let html = String(data: data, encoding: .utf8) ?? ""
            if html.range(of: "recaptcha|g-recaptcha|captcha", options: [.regularExpression, .caseInsensitive]) != nil {
                throw APIError.captchaNeeded
            }
            throw APIError.librus(code: "portal_flow", message: "Logowanie utknęło na stronie portalu.")
        }
        throw APIError.librus(code: "portal_flow", message: "Za dużo przekierowań przy logowaniu.")
    }

    private func assertLoginOK(data: Data, response: HTTPURLResponse) throws {
        let text = String(data: data, encoding: .utf8) ?? ""
        let failMarkers = [
            "Upewnij się, że nie", "Podany adres e-mail jest nieprawidłowy",
            "Nieprawidłowy login lub hasło", "Sesja logowania wygasła",
        ]
        if failMarkers.contains(where: text.contains) {
            throw APIError.invalidCredentials
        }
        if text.range(of: "recaptcha|g-recaptcha", options: .regularExpression) != nil {
            throw APIError.captchaNeeded
        }
        // A login with no redirect and no known error is treated as a failure by the caller.
    }

    // MARK: - Token exchange

    private func exchange(body: [String: String]) async throws -> PortalTokens {
        var request = URLRequest(url: URL(string: Librus.portalTokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Librus.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = HTTP.formBody(body)

        let (data, response) = try await dataOrThrow(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.server(code: status, body: String(data: data, encoding: .utf8))
        }
        if status != 200 || obj["access_token"] == nil {
            let hint = (obj["hint"] as? String) ?? (obj["error"] as? String) ?? (obj["message"] as? String)
            if hint == "unsupported_grant_type" || hint == "invalid_grant" {
                throw APIError.tokenExpired
            }
            throw APIError.librus(code: hint ?? "portal_token", message: hint)
        }
        let expiresIn = (obj["expires_in"] as? Double) ?? Double(obj["expires_in"] as? Int ?? 3600)
        return PortalTokens(
            accessToken: obj["access_token"] as? String ?? "",
            refreshToken: (obj["refresh_token"] as? String) ?? "",
            expiry: Date().timeIntervalSince1970 + expiresIn
        )
    }

    // MARK: - Low level

    private func portalGET(_ urlString: String, bearer: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.network("zły adres portalu") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Librus.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await dataOrThrow(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw APIError.tokenExpired }
        if status != 200 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let reason = (obj["reason"] as? String) ?? (obj["message"] as? String) ?? (obj["hint"] as? String)
                if reason == "Access token is invalid" { throw APIError.tokenExpired }
                throw APIError.librus(code: reason ?? "portal_api", message: reason)
            }
            throw APIError.server(code: status, body: String(data: data, encoding: .utf8))
        }
        return data
    }

    private func send(
        _ urlString: String, method: String,
        headers: [String: String] = [:], form: [String: String]? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else { throw APIError.network("zły adres: \(urlString)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Librus.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTP.formBody(form)
        }
        let (data, response) = try await dataOrThrow(request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.network("brak odpowiedzi HTTP")
        }
        return (data, http)
    }

    private func dataOrThrow(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await http.data(for: request) }
        catch { throw APIError.network(error.localizedDescription) }
    }

    private func codeFromLocation(_ location: String) -> String? {
        guard location.hasPrefix(Librus.portalRedirectURI) else { return nil }
        guard let comps = URLComponents(string: location) else {
            return HTTP.firstMatch("[?&]code=([^&]+)", in: location)
        }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func absoluteURL(_ location: String, relativeTo base: String) -> String {
        if location.hasPrefix("http://") || location.hasPrefix("https://") { return location }
        if let baseURL = URL(string: base), let resolved = URL(string: location, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return Librus.portalOrigin + (location.hasPrefix("/") ? location : "/" + location)
    }
}
