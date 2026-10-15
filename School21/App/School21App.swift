import SwiftUI

@main
struct School21App: App {
    @StateObject private var web = WebStore()

    init() {
        SettingsKey.registerDefaults()
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(web)
                .preferredColorScheme(.dark)
                .tint(Palette.teal)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var web: WebStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showMenu = false
    @State private var update: UpdateChecker.Update?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Palette.background.ignoresSafeArea()

            PlatformWebView(store: web)

            if web.isLoading {
                ProgressView(value: web.progress)
                    .progressViewStyle(.linear)
                    .tint(Palette.teal)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            if web.loadFailed {
                OfflineView { web.reload() }
            }

            // Кнопка «⋯» — как в Android- и десктоп-версиях.
            Button {
                showMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                    .opacity(0.9)
            }
            .padding(.trailing, 18)
            .padding(.bottom, 12)
            .accessibilityLabel("Меню")

            if let update {
                UpdateBanner(version: update.version, install: {
                    self.update = nil
                    Task { await UpdateChecker.install(update) }
                }, dismiss: { self.update = nil })
            }
        }
        .sheet(isPresented: $showMenu) {
            MenuSheet(close: { showMenu = false })
                .environmentObject(web)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await SyncService.run() }
        .task { update = await UpdateChecker.latestIfDue() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await SyncService.run() }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
    }
}

/// Карточка «Доступна новая версия» внизу экрана.
struct UpdateBanner: View {
    let version: String
    let install: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Доступна версия \(version)").font(.headline)
            Text("AltStore скачает и установит её — вход и настройки сохранятся.")
                .font(.callout).foregroundStyle(Palette.textSecondary)
            HStack {
                Spacer()
                Button("Не сейчас", action: dismiss).buttonStyle(.borderless)
                Button("Обновить", action: install)
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Palette.onAccent)
            }
        }
        .padding(16)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 72)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }
}

/// Экран «Нет подключения».
struct OfflineView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 42))
                .foregroundStyle(Palette.textSecondary)
            Text("Нет подключения").font(.title2.bold())
            Text("Не удалось загрузить страницу. Проверьте интернет и попробуйте ещё раз.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
            Button("Повторить", action: retry)
                .buttonStyle(.borderedProminent)
                .foregroundStyle(Palette.onAccent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }
}
