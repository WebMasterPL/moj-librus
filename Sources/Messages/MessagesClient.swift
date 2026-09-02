import Foundation

/// Read-only access to the Librus message inbox.
///
/// Librus messages are NOT part of the clean 2.0 API. They live on
/// `wiadomosci.librus.pl` behind the Synergia web session, so we:
///   1. POST `2.0/AutoLoginToken` (bearer) -> one-time token
///   2. GET `synergia.librus.pl/loguj/token/<T>/przenies/...` -> sets `DZIENNIKSID`
///   3. POST XML to `wiadomosci.librus.pl/module/<Module>` with that cookie
///
/// This bridge is the most fragile part of the app; failures here are reported
/// separately and never block grades/timetable/etc.
actor MessagesClient {
    private let session: LibrusSession
    private let http: URLSession
    private let cookieStorage: HTTPCookieStorage
    private var sessionEstablishedAt: Date?

    init(session: LibrusSession) {
        self.session = session
        let storage = HTTPCookieStorage()
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = storage
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": Librus.browserUserAgent]
        self.cookieStorage = storage
        self.http = URLSession(configuration: config)
    }

    func inbox() async throws -> [MessageItem] {
        try await ensureSession()
        let xml = try await postModule("Inbox/action/GetList", data: ["archive": "0"])
        guard let root = XMLTreeNode.parse(xml) else {
            throw APIError.messageBridgeFailed("nie udało się odczytać XML listy")
        }
        guard let dataNode = root.firstNode(path: ["GetList", "data"])
            ?? root.firstNode(path: ["response", "GetList", "data"])
            ?? findFirst(root, named: "data") else {
            throw APIError.messageBridgeFailed("brak węzła <data> w odpowiedzi")
        }

        return dataNode.children.compactMap { el in
            guard let idText = el.childText("messageId") ?? el.childText("id"),
                  let id = Int(idText.filter(\.isNumber)) else { return nil }
            let subject = el.childText("topic") ?? el.childText("subject") ?? "(bez tematu)"
            let sent = LibrusDate.fromISO(el.childText("sendDate"))
            let read = LibrusDate.fromISO(el.childText("readDate"))
            let first = el.childText("senderFirstName") ?? el.childText("firstname") ?? ""
            let last = el.childText("senderLastName") ?? el.childText("lastname") ?? ""
            let correspondent = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            let hasAttach = (el.childText("isAnyFileAttached") ?? "0") == "1"
            return MessageItem(
                id: id, subject: subject,
                correspondent: correspondent.isEmpty ? "Librus" : correspondent,
                sentDate: sent, readDateServer: read, hasAttachments: hasAttach, body: nil
            )
        }
    }

    func body(messageId: Int) async throws -> String {
        try await ensureSession()
        let xml = try await postModule("GetMessage", data: [
            "messageId": String(messageId), "archive": "0",
        ])
        guard let root = XMLTreeNode.parse(xml),
              let dataNode = root.firstNode(path: ["response", "GetMessage", "data"])
                ?? root.firstNode(path: ["GetMessage", "data"])
                ?? findFirst(root, named: "data") else {
            throw APIError.messageBridgeFailed("nie udało się odczytać treści wiadomości")
        }
        let rawMessage = dataNode.childText("Message") ?? dataNode.childText("message") ?? ""
        // Librus base64-encodes the body.
        if let decoded = Data(base64Encoded: rawMessage.filter { !$0.isWhitespace }),
           let text = String(data: decoded, encoding: .utf8) {
            return cleanup(text)
        }
        return cleanup(rawMessage)
    }

    // MARK: - Session bridge

    private func ensureSession() async throws {
        if let at = sessionEstablishedAt, Date().timeIntervalSince(at) < 30 * 60 { return }

        let token = try await autoLoginToken()

        let path = Librus.synergiaTokenLoginPath.replacingOccurrences(of: "TOKEN", with: token)
        let urlString = Librus.synergiaBase.absoluteString + path + "/uczen/widok/centrum_powiadomien"
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres logowania Synergii")
        }
        var request = URLRequest(url: url)
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")

        let response: URLResponse
        do {
            let (_, resp) = try await http.data(for: request)
            response = resp
        } catch {
            throw APIError.messageBridgeFailed(error.localizedDescription)
        }

        let finalURL = (response as? HTTPURLResponse)?.url?.absoluteString ?? ""
        let hasCookie = cookieStorage.cookies?.contains { $0.name == "DZIENNIKSID" } ?? false

        guard hasCookie || finalURL.contains("centrum_powiadomien") else {
            throw APIError.messageBridgeFailed("logowanie do Synergii nie powiodło się")
        }
        sessionEstablishedAt = Date()
    }

    private func autoLoginToken() async throws -> String {
        let data = try await session.authorizedData(path: Librus.Path.autoLoginToken, method: "POST")
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (obj["Token"] as? String) ?? (obj["token"] as? String) else {
            throw APIError.messageBridgeFailed("brak AutoLoginToken w odpowiedzi API")
        }
        return token
    }

    private func postModule(_ module: String, data: [String: String]) async throws -> Data {
        let url = Librus.messagesModuleBase.appendingPathComponent(module)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.buildRequestXML(data).utf8)
        do {
            let (body, response) = try await http.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: body, encoding: .utf8) ?? ""
            if status >= 500 || text.contains("OffLine") {
                throw APIError.maintenance
            }
            if text.contains("eAccessDeny") || text.contains("stop.png") {
                throw APIError.messageBridgeFailed("brak dostępu do modułu wiadomości")
            }
            return body
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.messageBridgeFailed(error.localizedDescription)
        }
    }

    private static func buildRequestXML(_ data: [String: String]) -> String {
        let inner = data.map { "<\($0.key)>\($0.value)</\($0.key)>" }.joined()
        return "<service><header></header><data>\(inner)</data></service>"
    }

    private func findFirst(_ node: XMLTreeNode, named name: String) -> XMLTreeNode? {
        if node.name.caseInsensitiveCompare(name) == .orderedSame { return node }
        for child in node.children {
            if let found = findFirst(child, named: name) { return found }
        }
        return nil
    }

    private func cleanup(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
