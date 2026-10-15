import Foundation

/// «Мои друзья»: логины друзей и где они сейчас в кампусе. Только чтение Open API.
@MainActor
final class FriendsStore: ObservableObject {
    static let shared = FriendsStore()
    static let maxCount = 30

    private static let key = "friends"

    @Published private(set) var logins: [String]

    private init() {
        logins = UserDefaults.standard.stringArray(forKey: Self.key) ?? []
    }

    func contains(_ login: String) -> Bool { logins.contains(login.lowercased()) }

    func add(_ login: String) {
        let login = login.lowercased()
        guard !logins.contains(login), logins.count < Self.maxCount else { return }
        logins.append(login)
        save()
    }

    func remove(_ login: String) {
        logins.removeAll { $0 == login }
        save()
    }

    private func save() {
        UserDefaults.standard.set(logins, forKey: Self.key)
        // Новый состав — заново «первая проверка», чтобы не прислать лишнего.
        Friends.resetPlaces()
    }
}

enum Friends {
    private static let placesKey = "friendPlaces"

    static func normalize(_ input: String) -> String {
        String(input.trimmingCharacters(in: .whitespaces).split(separator: "@").first ?? "").lowercased()
    }

    /// Логины из UserDefaults — для фоновой синхронизации (не трогая MainActor).
    static var storedLogins: [String] {
        UserDefaults.standard.stringArray(forKey: "friends") ?? []
    }

    /// Где были друзья при прошлой проверке: логин → место («» — не в кампусе). nil — ещё не проверяли.
    static var lastPlaces: [String: String]? {
        get { UserDefaults.standard.dictionary(forKey: placesKey) as? [String: String] }
        set { UserDefaults.standard.set(newValue, forKey: placesKey) }
    }

    static func resetPlaces() {
        UserDefaults.standard.removeObject(forKey: placesKey)
    }

    /// Место каждого друга, по 3 запроса одновременно. В ответе только те, для кого запрос удался.
    static func places(_ logins: [String]) async -> [String: Workstation?] {
        var result: [String: Workstation?] = [:]
        for chunk in stride(from: 0, to: logins.count, by: 3).map({ Array(logins[$0..<min($0 + 3, logins.count)]) }) {
            await withTaskGroup(of: (String, Workstation??).self) { group in
                for login in chunk {
                    group.addTask {
                        // .some(nil) — не в кампусе, nil — запрос не удался.
                        do { return (login, .some(try await OpenAPI.workstation(login))) } catch { return (login, nil) }
                    }
                }
                for await (login, ws) in group {
                    if let ws { result.updateValue(ws, forKey: login) }
                }
            }
        }
        return result
    }

    /// Кто пришёл в кампус с прошлой проверки (был вне кампуса, теперь за компьютером).
    static func arrivals(before: [String: String], now: [String: Workstation?]) -> [(String, Workstation)] {
        now.compactMap { login, ws in
            guard let ws, before[login] == "" else { return nil }
            return (login, ws)
        }
        .sorted { $0.0 < $1.0 }
    }
}
