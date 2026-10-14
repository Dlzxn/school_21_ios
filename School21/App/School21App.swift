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
        }
        .sheet(isPresented: $showMenu) {
            MenuSheet(close: { showMenu = false })
                .environmentObject(web)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await SyncService.run() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await SyncService.run() }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
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
