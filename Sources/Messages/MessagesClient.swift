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

    /// Human-readable trace of the last `ensureSession()` run — attached to
    /// downstream errors so the Diagnostics report shows where the bridge broke.
    private(set) var lastTrail = ""

    func invalidateSession() { sessionEstablishedAt = nil; dzienniksid = nil }

    private func ensureSession() async throws {
        if let at = sessionEstablishedAt, dzienniksid != nil,
           Date().timeIntervalSince(at) < 20 * 60 { return }

        var steps: [String] = []
        func note(_ s: String) { steps.append(s); lastTrail = steps.joined(separator: " | ") }

        let token = try await autoLoginToken()
        note("token")

        // 1. Establish the Synergia web session from the one-time API token.
        let path = Librus.synergiaTokenLoginPath.replacingOccurrences(of: "TOKEN", with: token)
        let synergiaLogin = Librus.synergiaBase.absoluteString + path + "/uczen/widok/centrum_powiadomien"
        let (loginData, loginResp) = try await get(synergiaLogin)
        let loginBody = String(data: loginData, encoding: .utf8) ?? ""
        note("synergia [\(loginResp?.statusCode ?? 0)] \(shortPath(loginResp?.url?.absoluteString ?? ""))")
        try checkBlockers(loginBody)
        try await followHTMLHops(from: loginResp?.url, body: loginBody, note: note)

        // A DZIENNIKSID here means the token transfer worked. Librus may scope it to
        // `.librus.pl` or host-only `synergia.librus.pl` — accept either. Landing back
        // on a login page means the one-time token was rejected.
        let finalLogin = loginResp?.url?.absoluteString ?? ""
        let landedOnLogin = finalLogin.contains("/loguj") || finalLogin.contains("/przeloguj")
            || loginBody.range(of: #"(?:name|id)=["'](?:pass|passwd|Login)["']"#,
                               options: [.regularExpression, .caseInsensitive]) != nil
        if cookie("DZIENNIKSID", domainContains: "librus") == nil || landedOnLogin {
            throw APIError.messageBridgeFailed("nie zalogowano do Synergii · \(lastTrail) · " + snippet(loginBody))
        }
        note("synergia-sid")

        // 2. Cross into wiadomosci.librus.pl. Librus does this with a MultiDomainLogon
        //    dance that can be a plain 302 chain OR a meta-refresh / auto-submit form,
        //    so we follow HTML hops too. Try the current path, then the legacy one.
        for bridge in ["https://synergia.librus.pl/wiadomosci", "https://synergia.librus.pl/wiadomosci2"] {
            let (data, resp) = try await get(bridge)
            let body = String(data: data, encoding: .utf8) ?? ""
            note("\(shortPath(bridge)) [\(resp?.statusCode ?? 0)] \(shortPath(resp?.url?.absoluteString ?? ""))")
            try checkBlockers(body)
            try await followHTMLHops(from: resp?.url, body: body, note: note)
            if cookie("DZIENNIKSID", domainContains: "wiadomosci") != nil { break }
        }

        // 3. One more plain GET so wiadomosci.librus.pl finalises the session cookie.
        _ = try? await get("https://wiadomosci.librus.pl/")

        let raw = cookie("DZIENNIKSID", domainContains: "wiadomosci")
            ?? cookie("DZIENNIKSID", domainContains: "")
        guard var sid = raw, !sid.isEmpty else {
            throw APIError.messageBridgeFailed("brak DZIENNIKSID wiadomości · \(lastTrail)")
        }
        sid = sid.replacingOccurrences(of: "-MAINT", with: "").replacingOccurrences(of: "MAINT", with: "")
        dzienniksid = sid
        sessionEstablishedAt = Date()
        note("wiadomosci-sid")
    }

    private func cookie(_ name: String, domainContains: String) -> String? {
        let all = http.configuration.httpCookieStorage?.cookies ?? []
        if domainContains.isEmpty { return all.first { $0.name == name }?.value }
        return all.first { $0.name == name && $0.domain.contains(domainContains) }?.value
    }

    private func checkBlockers(_ body: String) throws {
        if body.contains("grecaptcha") || body.contains("g-recaptcha") { throw APIError.captchaNeeded }
        if body.contains("przerwa_techniczna") || body.contains("OffLine") { throw APIError.maintenance }
    }

    /// Follow meta-refresh / `window.location` / auto-submitted-form redirects that
    /// URLSession (no JS engine) would otherwise stop at.
    private func followHTMLHops(from url: URL?, body: String, maxHops: Int = 4,
                                note: (String) -> Void) async throws {
        var currentURL = url
        var currentBody = body
        for _ in 0..<maxHops {
            guard let hop = Self.htmlRedirect(in: currentBody, base: currentURL) else { return }
            note("hop→\(shortPath(hop.url.absoluteString))")
            let data: Data, resp: HTTPURLResponse?
            if hop.isPost {
                (data, resp) = try await post(hop.url.absoluteString, form: hop.fields)
            } else {
                (data, resp) = try await get(hop.url.absoluteString)
            }
            currentBody = String(data: data, encoding: .utf8) ?? ""
            currentURL = resp?.url
            try checkBlockers(currentBody)
        }
    }

    private struct HTMLHop { let url: URL; let isPost: Bool; let fields: [String: String] }

    private static func htmlRedirect(in html: String, base: URL?) -> HTMLHop? {
        // Only redirect *stub* pages qualify — real Librus pages are tens of KB and
        // would false-positive on tracking scripts / markup.
        guard html.count < 4000 else { return nil }

        if let m = HTTP.firstMatch(#"http-equiv=["']refresh["'][^>]*content=["'][^"']*?url=([^"'\s]+)"#, in: html),
           let u = URL(string: m, relativeTo: base) {
            return HTMLHop(url: u, isPost: false, fields: [:])
        }
        if let m = HTTP.firstMatch(#"(?:window\.)?location(?:\.href|\.replace)?\s*(?:=|\()\s*["']([^"']+)["']"#, in: html),
           let u = URL(string: m, relativeTo: base) {
            return HTMLHop(url: u, isPost: false, fields: [:])
        }
        // <form ... action="..."> that JS submits on load
        if html.range(of: #"\.submit\(\)"#, options: .regularExpression) != nil,
           let action = HTTP.firstMatch(#"<form[^>]+action=["']([^"']+)["']"#, in: html),
           let u = URL(string: action, relativeTo: base) {
            let isPost = html.range(of: #"<form[^>]+method=["']post["']"#,
                                    options: [.regularExpression, .caseInsensitive]) != nil
            return HTMLHop(url: u, isPost: isPost, fields: HTTP.hiddenInputs(in: html))
        }
        return nil
    }

    private func post(_ urlString: String, form: [String: String]) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = HTTP.formBody(form)
        do {
            let (data, resp) = try await http.data(for: request)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.messageBridgeFailed("POST \(shortPath(urlString)): \(error.localizedDescription)")
        }
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
                throw APIError.messageBridgeFailed("sesja odrzucona przez wiadomosci.librus.pl · mostek: ["
                    + lastTrail + "] · " + snippet(body))
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
