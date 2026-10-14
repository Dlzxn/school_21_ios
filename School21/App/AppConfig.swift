import Foundation

/// Все адреса и константы приложения в одном месте.
enum AppConfig {
    static let platformOrigin = "https://platform.21-school.ru"
    static let startURL = URL(string: "https://platform.21-school.ru/")!

    /// Домен платформы: всё на нём (и поддоменах) открывается в приложении, остальное — в Safari.
    static let internalDomain = "21-school.ru"
    static let authHost = "auth.21-school.ru"

    static let tokenURL = URL(string: "https://auth.21-school.ru/auth/realms/EduPowerKeycloak/protocol/openid-connect/token")!
    /// Клиент сайта — для внутреннего GraphQL и проверки пароля.
    static let clientPlatform = "school21"
    /// Клиент официального Open API.
    static let clientOpenAPI = "s21-open-api"
    static let openAPI = "https://platform.21-school.ru/services/21-school/api"
    /// Константа из фронтенда платформы (заголовок X-EDU-PRODUCT-ID).
    static let eduProductId = "96098f4b-5708-4c42-a62c-6893419169b3"

    static let githubRepo = "Dlzxn/school_21_ios"
    static let androidRepo = "https://github.com/Dlzxn/school_21_mobile"
    static let desktopRepo = "https://github.com/Dlzxn/school_21_desktop"
    static let authorURL = "https://github.com/Dlzxn"

    static let remindBeforeMinutes = 15
    static let backgroundTaskId = "ru.school21.ios.refresh"
    static let keychainService = "ru.school21.ios"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func isInternal(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == internalDomain || host.hasSuffix("." + internalDomain)
    }

    // Шлюз платформы пропускает только запросы, которые есть во фронтенде сайта (allowlist):
    // изменённый текст получает 400. Поэтому тексты — дословно с сайта.

    static let queryNotifications = "\n    query getUserNotifications($paging: PagingInput!) {\n  s21Notification {\n    getS21Notifications(paging: $paging) {\n      notifications {\n        id\n        relatedObjectType\n        relatedObjectId\n        message\n        time\n        wasRead\n        groupName\n      }\n      totalCount\n      groupNames\n    }\n  }\n}\n    "

    static let queryAgenda = "query getAgendaEvents($from: DateTime!, $to: DateTime!, $limit: Int!) {\n  calendarEventS21 {\n    getMyAgendaEvents(from: $from, to: $to, limit: $limit) {\n      agendaItemContext {\n        entityId\n        entityType\n        __typename\n      }\n      start\n      end\n      label\n      description\n      agendaEventType\n      additionalInfo {\n        key\n        value\n        __typename\n      }\n      __typename\n    }\n    __typename\n  }\n}\n"
}
