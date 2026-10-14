import Foundation
import UserNotifications
import WebKit

/// Автовход: когда сайт выкидывает на форму Keycloak, заполняет логин/пароль и отправляет форму.
/// Защита от петли: если сразу после нашей отправки снова показана форма (неверный пароль),
/// повторно не пробуем — показываем уведомление, дальше пользователь входит сам.
@MainActor
final class AutoLogin {
    private var lastAttempt: Date?
    private var lastURL: String?
    private var failureNotified = false

    func reset() {
        lastAttempt = nil
        failureNotified = false
    }

    func pageFinished(_ webView: WKWebView, url: URL) {
        guard url.host == AppConfig.authHost else {
            // Ушли со страницы входа — вход удался (или пользователь ушёл сам).
            lastAttempt = nil
            failureNotified = false
            return
        }
        let path = url.path
        guard path.hasSuffix("/protocol/openid-connect/auth") || path.hasSuffix("/login-actions/authenticate") else { return }
        guard let creds = Keychain.loadCredentials() else { return }

        let now = Date()
        if let last = lastAttempt {
            // Повторное событие загрузки той же страницы — не повторный показ формы.
            if lastURL == url.absoluteString && now.timeIntervalSince(last) < 3 { return }
            if now.timeIntervalSince(last) < 60 {
                lastAttempt = nil
                if !failureNotified {
                    failureNotified = true
                    Notifier.show(id: "autologin-failed", title: "Автовход не удался",
                                  body: "Возможно, сменился пароль. Обновите его: ⋯ → Настройки → Автовход.")
                }
                return
            }
        }
        lastAttempt = now
        lastURL = url.absoluteString
        webView.evaluateJavaScript(Self.fillScript(creds), completionHandler: nil)
    }

    /// Форма рендерится React'ом после загрузки — ждём полей до ~8 с. Значения ставим через нативный
    /// setter + input (иначе React их затрёт), отправляем form.submit(). Проверка hostname внутри скрипта:
    /// если страница сменилась, данные никуда не уйдут.
    private static func fillScript(_ creds: Credentials) -> String {
        func quote(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
            return String(array.dropFirst().dropLast())
        }
        return """
        (function (host, login, password) {
          if (location.hostname !== host || window.__s21AutoLogin) return;
          window.__s21AutoLogin = true;
          var tries = 0;
          var timer = setInterval(function () {
            var u = document.querySelector('input[name="username"]');
            var p = document.querySelector('input[name="password"]');
            if (!u || !p || !p.form) { if (++tries > 40) clearInterval(timer); return; }
            clearInterval(timer);
            var setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            [[u, login], [p, password]].forEach(function (pair) {
              setValue.call(pair[0], pair[1]);
              pair[0].dispatchEvent(new Event('input', { bubbles: true }));
            });
            setTimeout(function () { HTMLFormElement.prototype.submit.call(p.form); }, 300);
          }, 200);
        })(\(quote(AppConfig.authHost)), \(quote(creds.login)), \(quote(creds.password)));
        """
    }
}

/// Локальные уведомления.
enum Notifier {
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func show(id: String, title: String, body: String, at date: Date? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        var trigger: UNNotificationTrigger?
        if let date, date.timeIntervalSinceNow > 1 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: date.timeIntervalSinceNow, repeats: false)
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
