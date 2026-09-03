import Foundation

/// Read + reply access to the Librus message inbox.
///
/// This school's Synergia serves the **legacy** message UI inline at
/// `synergia.librus.pl/wiadomosci` (HTML 4.01 + jQuery 1.8, `rowCollection.js`) —
/// not the standalone `wiadomosci.librus.pl` domain and not a JSON API. So we
/// establish the Synergia web session and scrape the HTML directly:
///   1. POST `2.0/AutoLoginToken` (bearer)                    -> one-time token
///   2. GET  `synergia.librus.pl/loguj/token/<T>/przenies/…`  -> sets `DZIENNIKSID`
///   3. GET  `synergia.librus.pl/wiadomosci` (+ `/1/5/<id>/f0`) and parse the table.
actor MessagesClient {
    private let session: LibrusSession
    private let http: URLSession
    private var sessionEstablishedAt: Date?

    /// Human-readable trace of the last session attempt — surfaced in errors so a
    /// remote Diagnostics report shows where it broke.
    private(set) var lastTrail = ""

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

    func invalidateSession() { sessionEstablishedAt = nil }

    // MARK: - Public API

    func inbox() async throws -> [MessageItem] {
        try await ensureSynergiaSession()
        let (data, resp) = try await get("https://synergia.librus.pl/wiadomosci")
        let html = String(data: data, encoding: .utf8) ?? ""
        let finalURL = resp?.url?.absoluteString ?? ""

        if finalURL.contains("/loguj") || html.contains(">Brak dostępu<") || html.contains("stop.png") {
            throw APIError.messageBridgeFailed("Synergia odmówiła dostępu do skrzynki wiadomości · "
                + lastTrail + " · " + snippet(html))
        }

        let items = Self.parseMessageList(html)
        if items.isEmpty {
            if html.range(of: #"[Bb]rak wiadomości|nie posiadasz żadnych|Wiadomości: 0"#,
                          options: .regularExpression) != nil { return [] }
            throw APIError.messageBridgeFailed("nie rozpoznałem listy wiadomości · "
                + Self.tableRegion(html))
        }
        return items
    }

    struct MessageContent: Sendable {
        var text: String
        var senderLoginId: String?
    }

    func content(messageId: Int) async throws -> MessageContent {
        try await ensureSynergiaSession()
        let (data, _) = try await get("https://synergia.librus.pl/wiadomosci/1/5/\(messageId)/f0")
        let html = String(data: data, encoding: .utf8) ?? ""

        let bodyHTML = Self.firstGroup(#"(?s)container-message-content[^>]*>(.*?)</div>"#, html)
            ?? Self.firstGroup(#"(?s)<div[^>]*class=["'][^"']*message[^"']*content[^"']*["'][^>]*>(.*?)</div>\s*</div>"#, html)
            ?? Self.firstGroup(#"(?s)<td[^>]*class=["'][^"']*message[^"']*["'][^>]*>(.*?)</td>"#, html)
            ?? Self.tableRegion(html)

        let senderId = HTTP.firstMatch(#"/wiadomosci/2/6/(\d+)"#, in: html)
        return MessageContent(text: cleanup(bodyHTML), senderLoginId: senderId)
    }

    @discardableResult
    func send(recipientLoginIds: [String], subject: String, body: String) async throws -> Int {
        try await ensureSynergiaSession()
        guard let rid = recipientLoginIds.first, !rid.isEmpty else {
            throw APIError.messageBridgeFailed("brak odbiorcy")
        }

        let (formData, _) = try await get("https://synergia.librus.pl/wiadomosci/2/6/\(rid)")
        let formHTML = String(data: formData, encoding: .utf8) ?? ""

        var fields = HTTP.hiddenInputs(in: formHTML)
        for m in HTTP.allMatches(#"name=["'](DoKogo\[[^"']*\])["'][^>]*value=["']([^"']+)["']"#, in: formHTML)
        where m.count > 2 {
            fields[m[1]] = m[2]
        }
        if !fields.keys.contains(where: { $0.hasPrefix("DoKogo") }) {
            fields["DoKogo[\(rid)]"] = rid
        }
        fields["temat"] = subject
        fields["tresc"] = body
        fields["poprzednia"] = "5"
        fields["Wyslij"] = "Wyślij"

        let (respData, resp) = try await post("https://synergia.librus.pl/wiadomosci/2/6", form: fields)
        let respHTML = String(data: respData, encoding: .utf8) ?? ""
        let finalURL = resp?.url?.absoluteString ?? ""

        if finalURL.contains("/wiadomosci/5") || finalURL.hasSuffix("/wiadomosci")
            || respHTML.range(of: #"została wysłana|wiadomość wysłana"#, options: .regularExpression) != nil {
            return 0
        }
        let err = Self.firstGroup(#"(?s)class=["'][^"']*(?:error|red|blad|komunikat)[^"']*["'][^>]*>(.*?)<"#, respHTML)
        throw APIError.messageBridgeFailed(
            err.map(Self.stripHTML)?.nonEmpty ?? ("wysyłka nie powiodła się · " + snippet(respHTML)))
    }

    // MARK: - Deep diagnostic

    func probe() async -> String {
        do {
            invalidateSession()
            try await ensureSynergiaSession()
        } catch {
            return "sesja BŁĄD · \(lastTrail) · "
                + ((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        var lines: [String] = ["sesja OK · \(lastTrail)", "cookies: " + cookieInventory()]
        for url in ["https://synergia.librus.pl/wiadomosci",
                    "https://synergia.librus.pl/wiadomosci/5",
                    "https://synergia.librus.pl/wiadomosci/1/5"] {
            guard let (d, r) = try? await get(url) else { lines.append("\(shortPath(url)): wyjątek"); continue }
            let h = String(data: d, encoding: .utf8) ?? ""
            let parsed = Self.parseMessageList(h)
            lines.append("\(shortPath(url)) [\(r?.statusCode ?? 0)] \(shortPath(r?.url?.absoluteString ?? "")) \(h.count)B · wierszy=\(parsed.count)")
            lines.append("  " + Self.tableRegion(h))
            if let first = parsed.first {
                lines.append("  1.: id=\(first.id) od='\(first.correspondent)' temat='\(first.subject.prefix(40))' data=\(first.sentDate.map { "\($0)" } ?? "?") nieprzeczyt=\(first.isUnread)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Session

    private func ensureSynergiaSession() async throws {
        if let at = sessionEstablishedAt, Date().timeIntervalSince(at) < 20 * 60,
           cookie("DZIENNIKSID", domainContains: "synergia") != nil { return }

        var steps: [String] = []
        func note(_ s: String) { steps.append(s); lastTrail = steps.joined(separator: " | ") }

        let token = try await autoLoginToken()
        note("token")

        let path = Librus.synergiaTokenLoginPath.replacingOccurrences(of: "TOKEN", with: token)
        let url = Librus.synergiaBase.absoluteString + path + "/uczen/widok/centrum_powiadomien"
        let (data, resp) = try await get(url)
        let body = String(data: data, encoding: .utf8) ?? ""
        note("synergia [\(resp?.statusCode ?? 0)] \(shortPath(resp?.url?.absoluteString ?? ""))")
        try checkBlockers(body)

        let final = resp?.url?.absoluteString ?? ""
        if cookie("DZIENNIKSID", domainContains: "librus") == nil || final.contains("/loguj") {
            throw APIError.messageBridgeFailed("nie zalogowano do Synergii · \(lastTrail) · " + snippet(body))
        }
        note("synergia-sid")
        sessionEstablishedAt = Date()
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

    private func checkBlockers(_ body: String) throws {
        if body.contains("grecaptcha") || body.contains("g-recaptcha") { throw APIError.captchaNeeded }
        if body.contains("przerwa_techniczna") || body.contains("OffLine") { throw APIError.maintenance }
    }

    private func cookie(_ name: String, domainContains: String) -> String? {
        let all = http.configuration.httpCookieStorage?.cookies ?? []
        if domainContains.isEmpty { return all.first { $0.name == name }?.value }
        return all.first { $0.name == name && $0.domain.contains(domainContains) }?.value
    }

    private func cookieInventory() -> String {
        let all = http.configuration.httpCookieStorage?.cookies ?? []
        guard !all.isEmpty else { return "(brak)" }
        return all.map { "\($0.name)@\($0.domain)=\($0.value.prefix(6))…" }.joined(separator: " ")
    }

    // MARK: - HTTP

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

    private func post(_ urlString: String, form: [String: String]) async throws -> (Data, HTTPURLResponse?) {
        guard let url = URL(string: urlString) else {
            throw APIError.messageBridgeFailed("zły adres: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Librus.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://synergia.librus.pl/wiadomosci", forHTTPHeaderField: "Referer")
        request.httpBody = HTTP.formBody(form)
        do {
            let (data, resp) = try await http.data(for: request)
            return (data, resp as? HTTPURLResponse)
        } catch {
            throw APIError.messageBridgeFailed("POST \(shortPath(urlString)): \(error.localizedDescription)")
        }
    }

    // MARK: - HTML parsing

    private static func parseMessageList(_ html: String) -> [MessageItem] {
        var out: [MessageItem] = []
        var seen = Set<Int>()

        for m in HTTP.allMatches(#"(?s)<tr[^>]*>(.*?)</tr>"#, in: html) {
            guard m.count > 1 else { continue }
            let row = m[1]
            guard let idStr = HTTP.firstMatch(#"/wiadomosci/1/5/(\d+)"#, in: row),
                  let id = Int(idStr), seen.insert(id).inserted else { continue }

            let cells = HTTP.allMatches(#"(?s)<td[^>]*>(.*?)</td>"#, in: row)
                .compactMap { $0.count > 1 ? stripHTML($0[1]) : nil }

            let subject = HTTP.firstMatch(#"(?s)<a[^>]+/wiadomosci/1/5/\d+[^>]*>(.*?)</a>"#, in: row)
                .map(stripHTML)?.nonEmpty ?? "(bez tematu)"

            let dateIdx = cells.firstIndex {
                $0.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil
            }
            let dateStr = dateIdx.map { cells[$0] }

            var sender = "Librus"
            if let di = dateIdx, di > 0 {
                for i in stride(from: di - 1, through: 0, by: -1) where cells[i].count > 1 && cells[i] != subject {
                    sender = cells[i]; break
                }
            } else if let s = cells.first(where: { $0.count > 1 && $0 != subject }) {
                sender = s
            }

            let unread = row.range(of: #"(?i)font-weight:\s*bold|class=["'][^"']*bold|nieczytan|<strong|<b>"#,
                                   options: .regularExpression) != nil
            let attach = row.range(of: #"(?i)zalacznik|attachment|spinacz|clip\.|paperclip"#,
                                   options: .regularExpression) != nil

            let date = LibrusDate.fromISO(dateStr)
            out.append(MessageItem(
                id: id,
                subject: subject,
                correspondent: sender,
                sentDate: date,
                readDateServer: unread ? nil : date,
                hasAttachments: attach,
                body: nil
            ))
        }
        return out
    }

    /// ~900 chars of the HTML around the first message link (or the first table),
    /// whitespace-collapsed — enough to see the row structure remotely.
    private static func tableRegion(_ html: String) -> String {
        let anchor = html.range(of: "/wiadomosci/1/5/")?.lowerBound
            ?? html.range(of: "table")?.lowerBound
            ?? html.startIndex
        let start = html.index(anchor, offsetBy: -450, limitedBy: html.startIndex) ?? html.startIndex
        let end = html.index(anchor, offsetBy: 450, limitedBy: html.endIndex) ?? html.endIndex
        return String(html[start..<end])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func firstGroup(_ pattern: String, _ text: String) -> String? {
        HTTP.firstMatch(pattern, in: text)
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: #"(?s)<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanup(_ html: String) -> String {
        html
            .replacingOccurrences(of: "<![CDATA[", with: "")
            .replacingOccurrences(of: "]]>", with: "")
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?s)<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func snippet(_ data: Data, _ max: Int = 200) -> String {
        snippet(String(data: data, encoding: .utf8) ?? "", max)
    }
    private func snippet(_ text: String, _ max: Int = 200) -> String {
        String(text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(max))
    }

    private func shortPath(_ url: String) -> String {
        URLComponents(string: url)?.path ?? url
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
