import UIKit
import Foundation

/// Внутренний GraphQL сайта (только query). Особенности шлюза: авторизация cookie tokenId,
/// маршрут ?operation=<имя>, пропускаются только запросы из фронтенда сайта — тексты дословные.
enum PlatformAPI {
    private static var schoolId: String?

    private static func fetchSchoolId(token: String) async throws -> String {
        if let schoolId { return schoolId }
        var req = URLRequest(url: URL(string: AppConfig.platformOrigin + "/services/rest/v1/users/getCurrentUserSchoolRoles")!)
        req.setValue("tokenId=\(token)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw APIError.http((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let json = try JSONSerialization.jsonObject(with: data)
        func find(_ node: Any) -> String? {
            if let dict = node as? [String: Any] {
                if let id = dict["schoolId"] as? String { return id }
                return dict.values.lazy.compactMap(find).first
            }
            if let list = node as? [Any] { return list.lazy.compactMap(find).first }
            return nil
        }
        guard let id = find(json) else { throw APIError.parse }
        schoolId = id
        return id
    }

    private static func query(_ operation: String, _ text: String, _ variables: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["operationName": operation, "variables": variables, "query": text])
        for attempt in 0..<2 {
            let token = try await TokenProvider.shared.token(client: AppConfig.clientPlatform)
            let school = try await fetchSchoolId(token: token)
            var req = URLRequest(url: URL(string: AppConfig.platformOrigin + "/services/graphql?operation=\(operation)")!)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("tokenId=\(token)", forHTTPHeaderField: "Cookie")
            req.setValue(school, forHTTPHeaderField: "schoolid")
            req.setValue("STUDENT", forHTTPHeaderField: "userrole")
            req.setValue(school, forHTTPHeaderField: "X-EDU-ORG-UNIT-ID")
            req.setValue(AppConfig.eduProductId, forHTTPHeaderField: "X-EDU-PRODUCT-ID")
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 && attempt == 0 {
                await TokenProvider.shared.invalidate(client: AppConfig.clientPlatform)
                continue
            }
            guard (200..<300).contains(status) else { throw APIError.http(status) }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["errors"] == nil,
                  let payload = json["data"] as? [String: Any] else { throw APIError.parse }
            return payload
        }
        throw APIError.http(401)
    }

    static func notifications(limit: Int = 20) async throws -> [PlatformNotification] {
        let data = try await query("getUserNotifications", AppConfig.queryNotifications, ["paging": ["offset": 0, "limit": limit]])
        let list = ((data["s21Notification"] as? [String: Any])?["getS21Notifications"] as? [String: Any])?["notifications"] as? [[String: Any]] ?? []
        return list.compactMap { n in
            guard let id = n["id"].map({ "\($0)" }) else { return nil }
            return PlatformNotification(id: id, message: HTTP.string(n["message"]) ?? "", wasRead: n["wasRead"] as? Bool ?? false)
        }
    }

    static func agenda(from: Date, to: Date, limit: Int = 30) async throws -> [AgendaItem] {
        let variables: [String: Any] = ["from": HTTP.isoPlain.string(from: from), "to": HTTP.isoPlain.string(from: to), "limit": limit]
        let data = try await query("getAgendaEvents", AppConfig.queryAgenda, variables)
        let list = (data["calendarEventS21"] as? [String: Any])?["getMyAgendaEvents"] as? [[String: Any]] ?? []
        return list.compactMap { e in
            guard let start = HTTP.date(e["start"]) else { return nil }
            let label = HTTP.string(e["label"]) ?? ""
            let context = e["agendaItemContext"] as? [String: Any]
            let id = context?["entityId"].map { "\($0)" } ?? "\(label)@\(start.timeIntervalSince1970)"
            return AgendaItem(id: id, label: label, description: HTTP.string(e["description"]), start: start)
        }
    }

    static func reset() {
        schoolId = nil
    }
}

/// Последний релиз iOS-версии на GitHub.
enum UpdateChecker {
    struct Update {
        let version: String
        let page: URL
        /// Прямая ссылка на School21.ipa из релиза.
        let ipa: URL?
    }

    private static let lastCheckKey = "lastUpdateCheck"

    static func latest() async throws -> Update? {
        let url = URL(string: "https://api.github.com/repos/\(AppConfig.githubRepo)/releases/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let ipa = (json["assets"] as? [[String: Any]] ?? [])
            .first { ($0["name"] as? String)?.hasSuffix(".ipa") == true }
            .flatMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        return isNewer(version, than: AppConfig.version) ? Update(version: version, page: page, ipa: ipa) : nil
    }

    /// Проверка при запуске — не чаще раза в 6 часов.
    static func latestIfDue() async -> Update? {
        let last = UserDefaults.standard.double(forKey: lastCheckKey)
        guard Date().timeIntervalSince1970 - last > 6 * 3600 else { return nil }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastCheckKey)
        return try? await latest()
    }

    /// Поставить новую версию: AltStore или SideStore скачают IPA и переподпишут его сами.
    /// Если ни того ни другого нет — страница релиза в Safari.
    @MainActor
    static func install(_ update: Update) async {
        if let ipa = update.ipa?.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            for scheme in ["altstore", "sidestore"] {
                if let url = URL(string: "\(scheme)://install?url=\(ipa)"), await UIApplication.shared.open(url) {
                    return
                }
            }
        }
        await UIApplication.shared.open(update.page)
    }

    /// Добавить источник School 21 Apps в AltStore — тогда обновления видны прямо в нём.
    @MainActor
    static func addAltStoreSource() async {
        let source = AppConfig.altStoreSource.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        for scheme in ["altstore", "sidestore"] {
            if let url = URL(string: "\(scheme)://source?url=\(source)"), await UIApplication.shared.open(url) {
                return
            }
        }
        if let site = URL(string: AppConfig.siteURL) { await UIApplication.shared.open(site) }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let (p, q) = (i < x.count ? x[i] : 0, i < y.count ? y[i] : 0)
            if p != q { return p > q }
        }
        return false
    }
}
