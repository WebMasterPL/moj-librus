import Foundation

/// Everything needed to talk to Librus on behalf of one Synergia account.
/// Persisted as a single JSON blob in the keychain.
struct Credentials: Codable, Equatable {
    var login: String
    var password: String
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry of `accessToken` (seconds since 1970).
    var accessTokenExpiry: Double

    var isAccessTokenValid: Bool {
        // 60 s safety margin.
        Date().timeIntervalSince1970 < accessTokenExpiry - 60
    }

    static let keychainKey = "credentials.v1"

    static func load() -> Credentials? {
        Keychain.json(Credentials.self, for: keychainKey)
    }

    func save() {
        Keychain.setJSON(self, for: Credentials.keychainKey)
    }

    static func clear() {
        Keychain.delete(keychainKey)
    }
}
