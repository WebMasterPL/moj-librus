import Foundation

/// Owns the Librus OAuth token lifecycle and performs authorized `2.0/*` requests.
///
/// An `actor` so token refresh is serialized: many screens can call
/// `authorizedData(path:)` concurrently and at most one refresh happens.
actor LibrusSession {
    private(set) var credentials: Credentials?
    private var refreshTask: Task<Credentials, Error>?

    private let urlSession: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": Librus.userAgent]
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        self.urlSession = URLSession(configuration: config)
        self.credentials = Credentials.load()
    }

    var isLoggedIn: Bool { credentials != nil }

    // MARK: - Login

    /// Full password-grant login. Persists everything to the keychain on success.
    func logIn(login: String, password: String) async throws {
        let token = try await requestToken(body: [
            "grant_type": "password",
            "username": login,
            "password": password,
            "librus_long_term_token": "1",
            "librus_rules_accepted": "1",
        ])
        let creds = Credentials(
            login: login,
            password: password,
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            accessTokenExpiry: Date().timeIntervalSince1970 + token.expiresIn
        )
        creds.save()
        self.credentials = creds
    }

    func logOut() {
        credentials = nil
        refreshTask = nil
        Credentials.clear()
    }

    // MARK: - Authorized requests

    /// `2.0/<path>` with a valid bearer token, refreshing/re-authing as needed.
    /// Returns the raw body so callers decode their own shapes.
    func authorizedData(
        path: String, method: String = "GET", body: Data? = nil, contentType: String? = nil
    ) async throws -> Data {
        var creds = try await validCredentials()
        var (data, response) = try await send(
            path: path, token: creds.accessToken, method: method, body: body, contentType: contentType)

        if shouldRetryAfterAuth(data: data, response: response) {
            creds = try await forceRefresh()
            (data, response) = try await send(
                path: path, token: creds.accessToken, method: method, body: body, contentType: contentType)
        }
        try Self.throwIfAPIError(data: data, response: response)
        return data
    }

    /// Current access token, refreshed on demand. Used by the messages bridge.
    func validAccessToken() async throws -> String {
        try await validCredentials().accessToken
    }

    // MARK: - Internals

    private func validCredentials() async throws -> Credentials {
        guard let creds = credentials else { throw APIError.tokenExpired }
        if creds.isAccessTokenValid { return creds }
        return try await forceRefresh()
    }

    private func forceRefresh() async throws -> Credentials {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<Credentials, Error> { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> Credentials {
        guard let current = credentials else { throw APIError.tokenExpired }

        // Try a refresh_token grant first; fall back to a full re-login.
        do {
            let token = try await requestToken(body: [
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "librus_long_term_token": "1",
                "librus_rules_accepted": "1",
            ])
            var updated = current
            updated.accessToken = token.accessToken
            updated.refreshToken = token.refreshToken.isEmpty ? current.refreshToken : token.refreshToken
            updated.accessTokenExpiry = Date().timeIntervalSince1970 + token.expiresIn
            updated.save()
            credentials = updated
            return updated
        } catch {
            let token = try await requestToken(body: [
                "grant_type": "password",
                "username": current.login,
                "password": current.password,
                "librus_long_term_token": "1",
                "librus_rules_accepted": "1",
            ])
            var updated = current
            updated.accessToken = token.accessToken
            updated.refreshToken = token.refreshToken
            updated.accessTokenExpiry = Date().timeIntervalSince1970 + token.expiresIn
            updated.save()
            credentials = updated
            return updated
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try c.decode(String.self, forKey: .accessToken)
            refreshToken = (try? c.decode(String.self, forKey: .refreshToken)) ?? ""
            expiresIn = (try? c.decode(Double.self, forKey: .expiresIn)) ?? 86400
        }
    }

    private func requestToken(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Librus.tokenURL)
        request.httpMethod = "POST"
        request.setValue(Librus.basicAuth, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 503 { throw APIError.maintenance }

        if status != 200 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = obj["error"] as? String {
                throw APIError.fromTokenError(error)
            }
            throw APIError.server(code: status, body: String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw APIError.decoding("token: \(error)")
        }
    }

    private func send(
        path: String, token: String, method: String = "GET",
        body: Data? = nil, contentType: String? = nil
    ) async throws -> (Data, URLResponse) {
        guard let full = URL(string: "\(Librus.apiBase.absoluteString)/\(path)") else {
            throw APIError.network("zły adres: \(path)")
        }
        var request = URLRequest(url: full)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = body }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
    }

    /// True when the response says the token is dead and a re-auth might help.
    private func shouldRetryAfterAuth(data: Data, response: URLResponse) -> Bool {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { return true }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["Code"] as? String, code == "TokenIsExpired" {
            return true
        }
        return false
    }

    private static func throwIfAPIError(data: Data, response: URLResponse) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 503 { throw APIError.maintenance }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status >= 400 {
                throw APIError.server(code: status, body: String(data: data, encoding: .utf8))
            }
            return
        }
        if let code = obj["Code"] as? String {
            throw APIError.fromAPICode(code, message: obj["Message"] as? String)
        }
        if status >= 400, let status2 = obj["Status"] as? String, status2 == "Error" {
            throw APIError.server(code: status, body: obj["Message"] as? String)
        }
    }

    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let pairs = params.map { key, value -> String in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
