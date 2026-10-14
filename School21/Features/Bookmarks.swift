import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    var title: String
    var url: URL
    var id: URL { url }
}

/// Закреплённые страницы платформы и стартовая страница приложения.
@MainActor
final class Bookmarks: ObservableObject {
    static let shared = Bookmarks()
    static let limit = 12

    @Published private(set) var items: [Bookmark] = []
    @Published private(set) var startURL: URL?

    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: "bookmarks"), let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            items = saved
        }
        startURL = defaults.url(forKey: "startURL").flatMap { AppConfig.isInternal($0) ? $0 : nil }
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return items.contains { $0.url == url }
    }

    func add(title: String, url: URL) {
        guard AppConfig.isInternal(url), !contains(url), items.count < Self.limit else { return }
        items.append(Bookmark(title: String(title.prefix(80)), url: url))
        save()
    }

    func remove(_ bookmark: Bookmark) {
        items.removeAll { $0.url == bookmark.url }
        if startURL == bookmark.url { setStart(nil) }
        save()
    }

    /// nil — снова открывать главную.
    func setStart(_ url: URL?) {
        startURL = url
        defaults.set(url, forKey: "startURL")
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(items), forKey: "bookmarks")
    }
}
