import SwiftUI
import UIKit
import WebKit

/// Владелец WKWebView: навигация, прогресс, автовход. Логика сайта — здесь, UI — в ContentView.
@MainActor
final class WebStore: NSObject, ObservableObject {
    let webView: WKWebView
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var loadFailed = false

    private var observations: [NSKeyValueObservation] = []
    private let autoLogin = AutoLogin()

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // куки и localStorage сохраняются между запусками
        config.applicationNameForUserAgent = "School21iOS/\(AppConfig.version)"
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Palette.background)
        webView.scrollView.backgroundColor = UIColor(Palette.background)

        let refresh = UIRefreshControl()
        refresh.tintColor = UIColor(Palette.teal)
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refresh

        observations = [
            webView.observe(\.estimatedProgress, options: .new) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.url, options: .new) { [weak self] view, _ in
                Task { @MainActor in self?.currentURL = view.url }
            },
        ]

        webView.load(URLRequest(url: Bookmarks.shared.startURL ?? AppConfig.startURL))
    }

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        webView.reload()
    }

    func open(_ url: URL) {
        loadFailed = false
        webView.load(URLRequest(url: url))
    }

    func reload() {
        loadFailed = false
        if webView.url == nil {
            webView.load(URLRequest(url: AppConfig.startURL))
        } else {
            webView.reload()
        }
    }

    /// После сохранения пароля: если открыта форма входа — перезагрузить, чтобы автовход сработал.
    func credentialsChanged() {
        autoLogin.reset()
        if webView.url?.host == AppConfig.authHost {
            webView.reload()
        }
    }

    /// Имя страницы для закладки: раздел платформы + заголовок страницы.
    func pageTitle() async -> String {
        let path = (webView.url?.path ?? "/").split(separator: "/").map(String.init)
        let sections = ["": "Главная", "projects": "Проекты", "calendar": "Календарь", "profile": "Профиль",
                        "campus": "Кампус", "competition": "Соревнования", "events": "События",
                        "notifications": "Уведомления", "progress": "Прогресс", "activities": "Активности"]
        let base = sections[path.first ?? ""] ?? (path.first?.removingPercentEncoding ?? "Страница")
        guard path.count > 1 else { return base }
        let script = "(document.querySelector('main h1, main h2, h1, h2') || {}).textContent || ''"
        if let heading = try? await webView.evaluateJavaScript(script) as? String {
            let text = heading.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty && text.count <= 60 { return "\(base): \(text)" }
        }
        return "\(base) · \(path.dropFirst().joined(separator: "/"))"
    }
}

extension WebStore: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // Встроенные фреймы (видео и т.п.) не трогаем.
        if navigationAction.targetFrame?.isMainFrame == false { return .allow }
        // http-ссылки на платформу повышаем до https.
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        let secure = components?.url

        switch url.scheme?.lowercased() {
        case "https" where AppConfig.isInternal(url):
            return .allow
        case "about", "data", "blob":
            return .allow
        case "http" where secure.map(AppConfig.isInternal) == true:
            if let secure { webView.load(URLRequest(url: secure)) }
            return .cancel
        default:
            // Чужие сайты — в Safari; tel:, mailto: и прочие — в системные приложения.
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        loadFailed = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        webView.scrollView.refreshControl?.endRefreshing()
        if let url = webView.url {
            autoLogin.pageFinished(webView, url: url)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        webView.scrollView.refreshControl?.endRefreshing()
        // Отмена перехода (например, ссылка ушла в Safari) — не ошибка сети.
        if (error as NSError).code != NSURLErrorCancelled {
            loadFailed = true
        }
    }
}

extension WebStore: WKUIDelegate {
    /// target=_blank / window.open: свои ссылки — в этом же окне, чужие — в Safari.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if AppConfig.isInternal(url) {
                webView.load(URLRequest(url: url))
            } else {
                UIApplication.shared.open(url)
            }
        }
        return nil
    }
}

/// WKWebView для SwiftUI.
struct PlatformWebView: UIViewRepresentable {
    let store: WebStore

    func makeUIView(context: Context) -> WKWebView { store.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
