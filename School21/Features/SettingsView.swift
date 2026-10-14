import SwiftUI

/// Настройки: автовход, уведомления, виджет, о приложении, экосистема, обратная связь.
struct SettingsView: View {
    @EnvironmentObject private var web: WebStore
    @AppStorage(SettingsKey.notifyAgenda) private var notifyAgenda = true
    @AppStorage(SettingsKey.notifyPlatform) private var notifyPlatform = true
    @AppStorage(SettingsKey.notifyEvents) private var notifyEvents = false

    @State private var savedLogin = Keychain.loadCredentials()?.login
    @State private var editing = Keychain.loadCredentials() == nil
    @State private var login = ""
    @State private var password = ""
    @State private var checking = false
    @State private var loginError: String?
    @State private var updateStatus: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Text("21")
                        .font(.title2.weight(.black))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 56, height: 56)
                        .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading) {
                        Text("School 21").font(.title3.bold())
                        Text("Версия \(AppConfig.version) · неофициальный клиент платформы")
                            .font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section {
                if editing {
                    TextField("Логин", text: $login)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                    if let loginError {
                        Text(loginError).foregroundStyle(.red).font(.callout)
                    }
                    Button {
                        saveCredentials()
                    } label: {
                        if checking { ProgressView() } else { Text("Проверить и сохранить") }
                    }
                    .disabled(checking || login.isEmpty || password.isEmpty)
                    if savedLogin != nil {
                        Button("Отмена") { editing = false }
                    }
                } else if let savedLogin {
                    Label("Включён для \(savedLogin)", systemImage: "lock.fill")
                    Button("Изменить") {
                        login = savedLogin
                        password = ""
                        editing = true
                    }
                    Button("Отключить и удалить данные", role: .destructive) {
                        Keychain.clearCredentials()
                        Task { await TokenProvider.shared.reset() }
                        PlatformAPI.reset()
                        SyncService.resetAccountData()
                        self.savedLogin = nil
                        editing = true
                    }
                }
            } header: {
                Text("Автовход")
            } footer: {
                Text("Платформа завершает сессию пару раз в день — приложение само введёт логин и пароль. Они хранятся в Keychain iPhone и отправляются только на auth.21-school.ru.")
            }

            Section {
                Toggle("Напоминания о моих событиях", isOn: $notifyAgenda)
                Toggle("Уведомления платформы", isOn: $notifyPlatform)
                Toggle("Новые события кампуса", isOn: $notifyEvents)
            } header: {
                Text("Уведомления")
            } footer: {
                Text("Напоминания за 15 минут до событий и проверок, на которые вы записаны, планируются заранее и приходят вовремя. «Колокольчик» и новые события iOS проверяет в фоне сама — обычно раз в несколько часов, а также при открытии приложения.")
            }
            .onChange(of: notifyAgenda) { _, on in if on { enableNotifications() } }
            .onChange(of: notifyPlatform) { _, on in if on { enableNotifications() } }
            .onChange(of: notifyEvents) { _, on in if on { enableNotifications() } }

            Section {
                Text("Удерживайте палец на экране «Домой» → «+» в углу → School 21. Есть маленький и средний виджеты и виджеты для экрана блокировки.")
                    .font(.callout)
            } header: {
                Text("Виджет")
            }

            Section("О приложении") {
                Button {
                    checkUpdates()
                } label: {
                    VStack(alignment: .leading) {
                        Text("Проверить обновления")
                        Text(updateStatus ?? "Версия \(AppConfig.version)").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                Link("Исходный код и релизы", destination: URL(string: "https://github.com/\(AppConfig.githubRepo)")!)
            }

            Section("Экосистема School 21") {
                Link(destination: URL(string: AppConfig.androidRepo)!) { Label("Версия для Android", systemImage: "iphone") }
                Link(destination: URL(string: AppConfig.desktopRepo)!) { Label("Windows · macOS · Linux", systemImage: "desktopcomputer") }
            }

            Section {
                Link(destination: URL(string: "https://github.com/\(AppConfig.githubRepo)/issues")!) {
                    Label("Сообщить об ошибке", systemImage: "exclamationmark.triangle")
                }
                Link(destination: URL(string: AppConfig.authorURL)!) {
                    Label("Автор: Dlzxn · School 21: combinef", systemImage: "person")
                }
            } header: {
                Text("Обратная связь")
            } footer: {
                Text("Приложение не связано со Школой 21 официально: показывает сайт платформы и данные её API, только читая их.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Настройки")
    }

    private func saveCredentials() {
        let login = login.trimmingCharacters(in: .whitespaces)
        checking = true
        loginError = nil
        Task {
            do {
                try await TokenProvider.check(login: login, password: password)
                Keychain.saveCredentials(Credentials(login: login, password: password))
                await TokenProvider.shared.reset()
                PlatformAPI.reset()
                SyncService.resetAccountData()
                savedLogin = login
                password = ""
                editing = false
                web.credentialsChanged()
                await SyncService.run()
            } catch {
                loginError = (error as? APIError)?.errorDescription ?? "Нет связи с сервером входа"
            }
            checking = false
        }
    }

    private func enableNotifications() {
        Task {
            _ = await Notifier.requestPermission()
            await SyncService.run()
        }
    }

    private func checkUpdates() {
        updateStatus = "Проверяю…"
        Task {
            do {
                if let update = try await UpdateChecker.latest() {
                    updateStatus = "Доступна версия \(update.version)"
                    _ = await UIApplication.shared.open(update.url)
                } else {
                    updateStatus = "У вас последняя версия"
                }
            } catch {
                updateStatus = "Не удалось проверить обновления"
            }
        }
    }
}
