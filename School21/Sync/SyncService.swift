import BackgroundTasks
import Foundation
import WidgetKit

/// Ключи пользовательских настроек.
enum SettingsKey {
    static let notifyAgenda = "notifyAgenda"
    static let notifyPlatform = "notifyPlatform"
    static let notifyEvents = "notifyEvents"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [notifyAgenda: true, notifyPlatform: true, notifyEvents: false])
    }
}

/// Синхронизация: данные для виджета, напоминания о личном календаре, «колокольчик», новые события.
/// Запускается при открытии приложения и в фоне (когда iOS сочтёт нужным).
enum SyncService {
    private static let defaults = UserDefaults.standard

    static func run() async {
        guard let creds = Keychain.loadCredentials() else {
            SharedStore.saveSnapshot(nil)
            SharedStore.saveStatus(error: nil)
            WidgetCenter.shared.reloadAllTimelines()
            return
        }
        let now = Date()
        let agenda = (try? await PlatformAPI.agenda(from: now, to: now.addingTimeInterval(14 * 86_400))) ?? []

        do {
            SharedStore.saveSnapshot(try await buildSnapshot(login: creds.apiLogin, agenda: agenda, now: now))
            SharedStore.saveStatus(error: nil)
        } catch where Task.isCancelled {
            // Фоновую задачу прервала iOS — это не ошибка данных.
        } catch {
            SharedStore.saveStatus(error: (error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
        WidgetCenter.shared.reloadAllTimelines()
        if defaults.bool(forKey: SettingsKey.notifyAgenda) {
            scheduleReminders(agenda, now: now)
        }
        if defaults.bool(forKey: SettingsKey.notifyPlatform) {
            await checkPlatform()
        }
        if defaults.bool(forKey: SettingsKey.notifyEvents) {
            await checkEvents(now: now)
        }
    }

    private static func buildSnapshot(login: String, agenda: [AgendaItem], now: Date) async throws -> Snapshot {
        let participant = try await OpenAPI.participant(login)
        let points = (try? await OpenAPI.points(login)) ?? Points(peerReviewPoints: 0, codeReviewPoints: 0, coins: 0)
        let workstation = (try? await OpenAPI.workstation(login)) ?? nil
        let logtime = try? await OpenAPI.logtime(login)
        let coalition = (try? await OpenAPI.coalition(login)) ?? nil
        let campus = (try? await OpenAPI.events(from: now, to: now.addingTimeInterval(14 * 86_400))) ?? []

        let events = (agenda.map { SnapshotEvent(name: $0.label, start: $0.start, location: $0.description, mine: true) }
            + campus.map { SnapshotEvent(name: $0.name, start: $0.start, location: $0.location, mine: false) })
            .sorted { $0.start < $1.start }
        let subtitle = [participant.parallelName, participant.className].compactMap { $0 }.joined(separator: " · ")
        return Snapshot(
            login: participant.login,
            subtitle: subtitle.isEmpty ? nil : subtitle,
            level: participant.level,
            exp: participant.expValue,
            expToNextLevel: participant.expToNextLevel,
            coins: points.coins,
            peerReviewPoints: points.peerReviewPoints,
            codeReviewPoints: points.codeReviewPoints,
            logtime: logtime,
            place: workstation?.label,
            coalition: coalition?.name,
            coalitionRank: coalition?.rank,
            events: Array(events.prefix(10)),
            updatedAt: now
        )
    }

    /// Напоминание за N минут до начала. Тот же id заменяет запланированное — повторы не дублируются.
    private static func scheduleReminders(_ agenda: [AgendaItem], now: Date) {
        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        for item in agenda where item.start < now.addingTimeInterval(86_400) {
            let remindAt = item.start.addingTimeInterval(TimeInterval(-AppConfig.remindBeforeMinutes * 60))
            guard remindAt > now else { continue }
            let body = (["Начало в \(time.string(from: item.start))"] + [item.description].compactMap { $0 }).joined(separator: " · ")
            Notifier.show(id: "agenda-\(item.id)-\(Int(item.start.timeIntervalSince1970))", title: item.label, body: body, at: remindAt)
        }
    }

    private static func checkPlatform() async {
        guard let list = try? await PlatformAPI.notifications() else { return }
        let seen = defaults.stringArray(forKey: "seenPlatform")
        // Первая синхронизация: старые уведомления не показываем, только запоминаем.
        if let seen {
            for n in list.filter({ !$0.wasRead && !seen.contains($0.id) }).prefix(5) {
                Notifier.show(id: "platform-\(n.id)", title: "School 21", body: stripHTML(n.message))
            }
        }
        defaults.set(merge(seen, list.map(\.id)), forKey: "seenPlatform")
    }

    private static func checkEvents(now: Date) async {
        guard let events = try? await OpenAPI.events(from: now, to: now.addingTimeInterval(14 * 86_400)) else { return }
        let seen = defaults.stringArray(forKey: "seenEvents")
        if let seen {
            let format = DateFormatter()
            format.locale = Locale(identifier: "ru_RU")
            format.dateFormat = "d MMMM, HH:mm"
            for e in events.filter({ !seen.contains(String($0.id)) }).prefix(5) {
                let body = ([format.string(from: e.start)] + [e.location].compactMap { $0 }).joined(separator: " · ")
                Notifier.show(id: "event-\(e.id)", title: "Новое событие: \(e.name)", body: body)
            }
        }
        defaults.set(merge(seen, events.map { String($0.id) }), forKey: "seenEvents")
    }

    private static func merge(_ old: [String]?, _ new: [String]) -> [String] {
        var all = old ?? []
        for id in new where !all.contains(id) { all.append(id) }
        return Array(all.suffix(300))
    }

    /// Сообщения «колокольчика» приходят с HTML-разметкой.
    private static func stripHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// После смены аккаунта — заново «первая синхронизация».
    static func resetAccountData() {
        defaults.removeObject(forKey: "seenPlatform")
        defaults.removeObject(forKey: "seenEvents")
        SharedStore.saveSnapshot(nil)
        SharedStore.saveStatus(error: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Фоновое обновление: iOS сама решает, когда запускать (обычно раз в несколько часов, чаще — если
/// приложением часто пользуются). Точные напоминания при этом планируются заранее и приходят вовремя.
enum BackgroundRefresh {
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: AppConfig.backgroundTaskId, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            schedule()
            let work = Task {
                await SyncService.run()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
