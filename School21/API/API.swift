import Foundation

enum APIError: Error, LocalizedError {
    /// Автовход не настроен — нечем авторизоваться.
    case notConfigured
    /// Сохранённый пароль не подошёл.
    case invalidCredentials
    case http(Int)
    case parse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Сначала включите автовход в настройках"
        case .invalidCredentials: return "Неверный логин или пароль"
        case .http(404): return "Не найдено"
        case .http(429): return "Слишком много запросов, попробуйте через минуту"
        case .http: return "Не удалось получить данные"
        case .parse: return "Неожиданный ответ сервера"
        }
    }
}

// MARK: - Модели

struct Participant {
    let login: String
    let className: String?
    let parallelName: String?
    let level: Int
    let expValue: Int
    let expToNextLevel: Int
    let campus: String?
    let status: String?
}

struct Workstation {
    let clusterName: String
    let row: String
    let number: Int

    var label: String { "\(clusterName) · \(row.uppercased())\(number)" }
}

struct Points {
    let peerReviewPoints: Int
    let codeReviewPoints: Int
    let coins: Int
}

struct Coalition {
    let name: String
    let rank: Int?
}

struct CampusEvent {
    let id: Int
    let name: String
    let location: String?
    let start: Date
}

struct AgendaItem {
    let id: String
    let label: String
    let description: String?
    let start: Date
}

struct PlatformNotification {
    let id: String
    let message: String
    let wasRead: Bool
}

// MARK: - Токены Keycloak

/// Access-токены для запросов приложения. Сначала просим offline_access — такой refresh-токен
/// живёт неделями, и пароль нужен редко (меньше новых сессий на сервере).
actor TokenProvider {
    static let shared = TokenProvider()

    private var cache: [String: (token: String, expires: Date)] = [:]

    func token(client: String) async throws -> String {
        if let cached = cache[client], cached.expires > Date().addingTimeInterval(30) {
            return cached.token
        }
        var response: [String: Any]?
        if let refresh = Keychain.get("refresh_\(client)") {
            response = try? await Self.request(["client_id": client, "grant_type": "refresh_token", "refresh_token": refresh])
        }
        if response == nil {
            guard let creds = Keychain.loadCredentials() else { throw APIError.notConfigured }
            response = try await Self.passwordGrant(client: client, creds: creds)
        }
        guard let response, let access = response["access_token"] as? String else { throw APIError.parse }
        let expiresIn = response["expires_in"] as? Double ?? 60
        if let refresh = response["refresh_token"] as? String {
            Keychain.set("refresh_\(client)", refresh)
        }
        cache[client] = (access, Date().addingTimeInterval(expiresIn))
        return access
    }

    func invalidate(client: String) {
        cache[client] = nil
    }

    func reset() {
        cache.removeAll()
    }

    /// Проверка логина и пароля до сохранения.
    static func check(login: String, password: String) async throws {
        _ = try await request(["client_id": AppConfig.clientPlatform, "grant_type": "password", "username": login, "password": password])
    }

    private static func passwordGrant(client: String, creds: Credentials) async throws -> [String: Any] {
        var params = ["client_id": client, "grant_type": "password", "username": creds.login, "password": creds.password]
        params["scope"] = "openid offline_access"
        do {
            return try await request(params)
        } catch TokenError.invalidScope {
            params["scope"] = nil
            return try await request(params)
        }
    }

    private enum TokenError: Error { case invalidScope }

    private static func request(_ params: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: AppConfig.tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(status) else {
            if body.contains("invalid_scope") { throw TokenError.invalidScope }
            if body.contains("invalid_grant") && params["grant_type"] == "password" { throw APIError.invalidCredentials }
            throw APIError.http(status)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.parse }
        return json
    }
}

// MARK: - Общие помощники

enum HTTP {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoPlain = ISO8601DateFormatter()

    static func date(_ value: Any?) -> Date? {
        guard let s = value as? String else { return nil }
        return iso.date(from: s) ?? isoPlain.date(from: s)
    }

    static func string(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    static func encodePath(_ segment: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return segment.trimmingCharacters(in: .whitespaces).lowercased().addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
    }
}
