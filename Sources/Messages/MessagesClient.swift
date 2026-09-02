import Foundation

/// Read-only + reply access to the Librus message inbox.
///
/// Messages are NOT part of the clean 2.0 API. They live on `wiadomosci.librus.pl`
/// behind a Synergia web session:
///   1. POST `2.0/AutoLoginToken` (bearer)                       -> one-time token
///   2. GET `synergia.librus.pl/loguj/token/<T>/przenies/...`    -> sets `DZIENNIKSID`
///   3. POST XML to `wiadomosci.librus.pl/module/<Module>` sending that cookie
///      **explicitly** (it's a host-only cookie for synergia, not wiadomosci).
actor MessagesClient {
    private let session: LibrusSession
    private let http: URLSession
    private var dzienniksid: String?
    private var sessionEstablishedAt: Date?

    init(session: LibrusSession) {
        self.session = session
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["User-Agent": Librus.browserUserAgent]
        self.http = URLSession(configuration: config)
    }

    // MARK: - Public API

    func inbox() async throws -> [MessageItem] {
        try await ensureSession()
        let xml = try await postModule("Inbox/action/GetList", data: ["archive": "0"])
        guard let root = XMLTreeNode.parse(xml) else {
            throw APIError.messageBridgeFailed("nieczytelny XML listy: " + snippet(xml))
        }
        guard let listNode = firstNode(root, named: "GetList") ?? firstNode(root, named: "data"),
              let dataNode = (listNode.name.caseInsensitiveCompare("data") == .orderedSame
                              ? listNode : firstNode(listNode, named: "data")) else {
            throw APIError.messageBridgeFailed("brak <data> w liście: " + snippet(xml))
        }

        let rows = dataNode.children.isEmpty ? [dataNode] : dataNode.children
        let items: [MessageItem] = rows.compactMap { el in
            guard let idText = el.childText("messageId") ?? el.childText("id"),
                  let id = Int(idText.filter(\.isNumber)) else { return nil }
            let first = (el.childText("senderFirstName") ?? el.childText("firstName") ?? "")
            let last = (el.childText("senderLastName") ?? el.childText("lastName") ?? "")
            let correspondent = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            return MessageItem(
                id: id,
                subject: el.childText("topic") ?? el.childText("subject") ?? "(bez tematu)",
                correspondent: correspondent.isEmpty ? "Librus" : correspondent,
                sentDate: LibrusDate.fromISO(el.childText("sendDate") ?? el.childText("senddate")),
                readDateServer: LibrusDate.fromISO(el.childText("readDate") ?? el.childText("readdate")),
                hasAttachments: (el.childText("isAnyFileAttached") ?? "0") == "1",
                body: nil
            )
        }
        if items.isEmpty && !dataNode.children.isEmpty {
            throw APIError.messageBridgeFailed("nie rozpoznałem pól wiadomości: " + snippet(xml))
        }
        return items
    }

    struct MessageContent: Sendable {
        var text: String
        var senderLoginId: String?
    }

    func content(messageId: Int) async throws -> MessageContent {
        try await ensureSession()
        let xml = try await postModule("GetMessage", data: [
            "messageId": String(messageId), "archive": "0",
        ])
        guard let root = XMLTreeNode.parse(xml),
              let dataNode = firstNode(root, named: "data")
                ?? firstNode(root, named: "GetMessage") else {
            throw APIError.messageBridgeFailed("nieczytelna treść: " + snippet(xml))
        }
        let rawMessage = dataNode.childText("Message") ?? dataNode.childText("message") ?? ""
        let senderLoginId = dataNode.childText("senderId") ?? dataNode.childText("senderid")

        let text: String
        if let decoded = Data(base64Encoded: rawMessage.filter { !$0.isWhitespace }),
           let decodedText = String(data: decoded, encoding: .utf8), !decodedText.isEmpty {
            text = cleanup(decodedText)
        } else {
            text = cleanup(rawMessage)
        }
        return MessageContent(text: text, senderLoginId: senderLoginId)
    }

    @discardableResult
    func send(recipientLoginIds: [String], subject: String, body: String) async throws -> Int {
        guard !recipientLoginIds.isEmpty else {
            throw APIError.messageBridgeFailed("brak odbiorcy")
        }
        try await ensureSession()
        let xml = try await postModule("SendMessage", data: [
            "topic": Data(subject.utf8).base64EncodedString(),
            "message": Data(body.utf8).base64EncodedString(),
            "receivers": recipientLoginIds.joined(separator: ","),
            "actions": Data("<Actions/>".utf8).base64EncodedString(),
        ])
        guard let root = XMLTreeNode.parse(xml),
              let node = firstNode(root, named: "SendMessage") ?? firstNode(root, named: "data") else {
            throw APIError.messageBridgeFailed("nieczytelna odpowiedź wysyłki: " + snippet(xml))
        }
        let status = (node.childText("status") ?? "").lowercased()
        guard status == "ok" || status.isEmpty else {
            throw APIError.messageBridgeFailed(node.childText("message") ?? "wysyłka odrzucona")
        }
        let newId = firstNode(node, named: "data")?.text.filter(\.isNumber)
        return Int(newId ?? "") ?? 0
    }

    // MARK: - Session bridge

    func invalidateSession() { sessionEstablishedAt = nil; dzienniksid = nil }

    private func ensureSession() async throws {
        if let at = sessionEstablishedAt, dzienniksid != nil,
           Date().timeIntervalSince(at) < 20 * 60 { return }

        var trail = "AutoLoginToken"
        let token = try await autoLoginToken()

        // 1. Establish the Synergia web session from the API token.
        let path = Librus.synergiaTokenLoginPath.replacingOccurrences(of: "TOKEN", with: token)
        let synergiaLogin = Librus.synergiaBase.absoluteString + path + "/uczen/widok/centrum_powiadomien"
        _ = try? await get(synergiaLogin)
        trail += " → synergia"

        // 2. Bridge into the messages domain via /wiadomosci2. URLSession follows
        //    synergia → wiadomosci.librus.pl (MultiDomainLogon → AutoLogon), and
        //    wiadomosci.librus.pl sets its OWN DZIENNIKSID along the way.
        let (bridgeData, bridgeResp) = try await get("https://synergia.librus.pl/wiadomosci2")
        let bridgeBody = String(data: bridgeData, encoding: .utf8) ?? ""
        let finalURL = bridgeResp?.url?.absoluteString ?? ""
        trail += " → wiadomosci2 [\(bridgeResp?.statusCode ?? 0)] \(shortPath(finalURL))"

        if bridgeBody.contains("grecaptcha") || bridgeBody.contains("g-recaptcha") {
            throw APIError.captchaNeeded
        }
        if bridgeBody.contains("przerwa_techniczna") || bridgeBody.contains("OffLine") {
            throw APIError.maintenance
        }

        let jar = http.configuration.httpCookieStorage
        let all = jar?.cookies ?? []
        let sid = all.first(where: { $0.name == "DZIENNIKSID" && $0.domain.contains("wiadomosci") })?.value
            ?? all.first(where: { $0.name == "DZIENNIKSID" })?.value

        guard var sid, !sid.isEmpty else {
            throw APIError.messageBridgeFailed("\(trail): brak DZIENNIKSID wiadomości (\(bridgeBody.count) B) "
                + snippet(bridgeBody))
        }
        sid = sid.replacingOccurrences(of: "-MAINT", with: "").replacingOccurrences(of: "MAINT", with: "")
        dzienniksid = sid
        sessionEstablishedAt = Date()
    }

    private func get(_ urlString: String) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        do {
            let (data, resp) = try await http.data(for: request)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.messageBridgeFailed("GET \(shortPath(urlString)): \(error.localizedDescription)")
        }
    }

    private func autoLoginToken() async throws -> String {
        let data: Data
        do {
            data = try await session.authorizedData(path: Librus.Path.autoLoginToken, method: "POST")
        } catch {
            throw APIError.messageBridgeFailed("AutoLoginToken: "
                + ((error as? LocalizedError)?.errorDescription ?? "\(error)"))
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (obj["Token"] as? String) ?? (obj["token"] as? String), !token.isEmpty else {
            throw APIError.messageBridgeFailed("brak Token w odpowiedzi AutoLoginToken: " + snippet(data))
        }
        return token
    }

    /// POST a module request, re-establishing the session once if it turns out stale.
    private func postModule(_ module: String, data: [String: String]) async throws -> Data {
        do {
            return try await rawPostModule(module, data: data)
        } catch let e as APIError {
            if case .messageBridgeFailed(let m) = e, m.contains("sesja") || m.contains("loginUrl") {
                invalidateSession()
                try await ensureSession()
                return try await rawPostModule(module, data: data)
            }
            throw e
        }
    }

    private func rawPostModule(_ module: String, data: [String: String]) async throws -> Data {
        guard let url = URL(string: Librus.messagesModuleBase.absoluteString + "/" + module) else {
            throw APIError.messageBridgeFailed("zły adres modułu")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        if let sid = dzienniksid {
            request.setValue("DZIENNIKSID=\(sid)", forHTTPHeaderField: "Cookie")
        }
        request.httpBody = Data(Self.buildRequestXML(data).utf8)

        do {
            let (body, response) = try await http.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let text = String(data: body, encoding: .utf8) ?? ""

            if status >= 500 || text.contains("OffLine") || text.contains("przerwa_techniczna") {
                throw APIError.maintenance
            }
            // Session lost — the module hands back an <error><loginUrl>…</error> page.
            if text.contains("<loginUrl>") || text.contains("eAccessDeny")
                || text.contains("stop.png") || text.contains("Niepoprawny login") {
                throw APIError.messageBridgeFailed("sesja wygasła (loginUrl): " + snippet(body))
            }
            let looksLikeXML = text.contains("<response") || text.contains("<service")
                || text.contains("<data") || text.contains("<ArrayItem") || text.contains("<GetList")
                || text.contains("<GetMessage") || text.contains("<SendMessage")
            if !looksLikeXML {
                throw APIError.messageBridgeFailed("moduł \(module) nie zwrócił XML [\(status)]: " + snippet(body))
            }
            return body
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.messageBridgeFailed("\(module): \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func buildRequestXML(_ data: [String: String]) -> String {
        let inner = data.map { "<\($0.key)>\($0.value)</\($0.key)>" }.joined()
        return "<service><header></header><data>\(inner)</data></service>"
    }

    private func firstNode(_ node: XMLTreeNode, named name: String) -> XMLTreeNode? {
        if node.name.caseInsensitiveCompare(name) == .orderedSame { return node }
        for child in node.children {
            if let found = firstNode(child, named: name) { return found }
        }
        return nil
    }

    private func snippet(_ data: Data) -> String { snippet(String(data: data, encoding: .utf8) ?? "") }
    private func snippet(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return String(flat.prefix(180))
    }

    private func shortPath(_ url: String) -> String {
        URLComponents(string: url)?.path ?? url
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
