import Foundation

/// Официальный Open API Школы 21. Авторизация — токен клиента s21-open-api.
enum OpenAPI {
    /// GET с одним повтором на 401 (токен мог истечь на сервере раньше срока).
    private static func get(_ path: String) async throws -> Data {
        for attempt in 0..<2 {
            let token = try await TokenProvider.shared.token(client: AppConfig.clientOpenAPI)
            var req = URLRequest(url: URL(string: AppConfig.openAPI + path)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 {
                await TokenProvider.shared.invalidate(client: AppConfig.clientOpenAPI)
                continue
            }
            guard (200..<300).contains(status) else { throw APIError.http(status) }
            return data
        }
        throw APIError.http(401)
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.parse }
        return json
    }

    static func participant(_ login: String) async throws -> Participant {
        let v = try object(try await get("/v1/participants/\(HTTP.encodePath(login))"))
        return Participant(
            login: HTTP.string(v["login"]) ?? login,
            className: HTTP.string(v["className"]),
            parallelName: HTTP.string(v["parallelName"]),
            level: v["level"] as? Int ?? 0,
            expValue: v["expValue"] as? Int ?? 0,
            expToNextLevel: v["expToNextLevel"] as? Int ?? 0,
            campus: HTTP.string((v["campus"] as? [String: Any])?["shortName"]),
            status: HTTP.string(v["status"])
        )
    }

    /// nil — пир не в кампусе. Вопреки документации (404) API отвечает 200 с пустым телом.
    static func workstation(_ login: String) async throws -> Workstation? {
        do {
            let data = try await get("/v1/participants/\(HTTP.encodePath(login))/workstation")
            guard !data.isEmpty, let v = try? object(data) else { return nil }
            return Workstation(
                clusterName: HTTP.string(v["clusterName"]) ?? "",
                row: HTTP.string(v["row"]) ?? "",
                number: v["number"] as? Int ?? 0
            )
        } catch APIError.http(404) {
            return nil
        }
    }

    static func points(_ login: String) async throws -> Points {
        let v = try object(try await get("/v1/participants/\(HTTP.encodePath(login))/points"))
        return Points(
            peerReviewPoints: v["peerReviewPoints"] as? Int ?? 0,
            codeReviewPoints: v["codeReviewPoints"] as? Int ?? 0,
            coins: v["coins"] as? Int ?? 0
        )
    }

    /// Средний логтайм за неделю, часов.
    static func logtime(_ login: String) async throws -> Double {
        let data = try await get("/v1/participants/\(HTTP.encodePath(login))/logtime")
        guard let text = String(data: data, encoding: .utf8), let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw APIError.parse
        }
        return value
    }

    static func coalition(_ login: String) async throws -> Coalition? {
        do {
            let data = try await get("/v1/participants/\(HTTP.encodePath(login))/coalition")
            guard !data.isEmpty, let v = try? object(data), let name = HTTP.string(v["name"]) else { return nil }
            return Coalition(name: name, rank: v["rank"] as? Int)
        } catch APIError.http(404) {
            return nil
        }
    }

    /// События кампуса пользователя в интервале.
    static func events(from: Date, to: Date) async throws -> [CampusEvent] {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let f = HTTP.isoPlain.string(from: from).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let t = HTTP.isoPlain.string(from: to).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let v = try object(try await get("/v1/events?from=\(f)&to=\(t)&limit=100"))
        let items = v["events"] as? [[String: Any]] ?? []
        return items.compactMap { e in
            guard let id = e["id"] as? Int, let start = HTTP.date(e["startDateTime"]) else { return nil }
            return CampusEvent(id: id, name: HTTP.string(e["name"]) ?? "", location: HTTP.string(e["location"]), start: start)
        }
    }
}
