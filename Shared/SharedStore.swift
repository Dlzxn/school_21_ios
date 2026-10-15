import Foundation
import SwiftUI

/// Общие для приложения и виджета данные: лежат в App Group, виджет только читает.
enum SharedStore {
    static let appGroup = resolveAppGroup()
    private static let snapshotKey = "snapshot"
    private static let statusKey = "syncStatus"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// AltStore/SideStore при переподписи дописывают к App Group ID команды (group.ru.school21.ios.ABCDE12345),
    /// поэтому берём реальный идентификатор из профиля, вшитого в приложение (и отдельно — в виджет).
    private static func resolveAppGroup() -> String {
        let base = "group.ru.school21.ios"
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let groups = entitlements["com.apple.security.application-groups"] as? [String]
        else { return base }
        return groups.first { $0.hasPrefix(base) } ?? groups.first ?? base
    }

    /// Итог последней синхронизации: виджет показывает ошибку вместо «пустого» состояния.
    static var lastError: String? {
        defaults.string(forKey: statusKey)
    }

    static func saveStatus(error: String?) {
        defaults.set(error, forKey: statusKey)
    }

    static func loadSnapshot() -> Snapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func saveSnapshot(_ snapshot: Snapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeObject(forKey: snapshotKey)
        }
    }
}

/// Снимок данных пользователя для виджета.
struct Snapshot: Codable {
    var login: String
    var subtitle: String?
    var level: Int
    var exp: Int
    var expToNextLevel: Int
    var coins: Int
    var peerReviewPoints: Int
    var codeReviewPoints: Int
    var logtime: Double?
    var place: String?
    var coalition: String?
    var coalitionRank: Int?
    var events: [SnapshotEvent]
    var updatedAt: Date
}

struct SnapshotEvent: Codable, Hashable {
    var name: String
    var start: Date
    var location: String?
    /// Пункт личного календаря (вы записаны), иначе событие кампуса.
    var mine: Bool
}

/// Палитра платформы School 21 (как в Android- и десктоп-версиях).
enum Palette {
    static let background = Color(red: 0x1D / 255, green: 0x26 / 255, blue: 0x33 / 255)
    static let card = Color(red: 0x2C / 255, green: 0x38 / 255, blue: 0x4A / 255)
    static let cardRaised = Color(red: 0x34 / 255, green: 0x42 / 255, blue: 0x5A / 255)
    static let cyan = Color(red: 0x36 / 255, green: 0xC5 / 255, blue: 0xF0 / 255)
    static let teal = Color(red: 0x3D / 255, green: 0xDA / 255, blue: 0xBF / 255)
    static let green = Color(red: 0x44 / 255, green: 0xEB / 255, blue: 0x99 / 255)
    static let textSecondary = Color(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xB8 / 255)
    static let onAccent = Color(red: 0x14 / 255, green: 0x20 / 255, blue: 0x2C / 255)
    static let accent = LinearGradient(colors: [cyan, teal, green], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension Int {
    /// 12345 → «12 345».
    var grouped: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: NSNumber(value: self)) ?? String(self)
    }
}
