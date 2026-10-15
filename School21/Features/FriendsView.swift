import SwiftUI

/// «Мои друзья»: кто из друзей в кампусе и где сидит, уведомление о приходе.
struct FriendsView: View {
    let openProfile: (String) -> Void

    @ObservedObject private var store = FriendsStore.shared
    @AppStorage(SettingsKey.notifyFriends) private var notify = false
    @State private var input = ""
    @State private var adding = false
    @State private var addError: String?
    @State private var states: [String: FriendState] = [:]
    @FocusState private var focused: Bool

    private struct FriendState {
        var loaded = false
        var failed = false
        var workstation: Workstation?
        var level: Int?
    }

    private var hasCredentials: Bool { Keychain.loadCredentials() != nil }

    /// В кампусе — наверху; дальше в порядке добавления.
    private var sorted: [String] {
        store.logins.enumerated()
            .sorted { a, b in
                let (x, y) = (states[a.element]?.workstation != nil, states[b.element]?.workstation != nil)
                return x != y ? x : a.offset < b.offset
            }
            .map(\.element)
    }

    var body: some View {
        List {
            if !hasCredentials {
                Text("Данные берутся из официального API Школы 21, для него нужен ваш логин и пароль. Включите автовход: Настройки → Автовход.")
                    .foregroundStyle(Palette.textSecondary)
            } else {
                Section {
                    HStack {
                        TextField("Логин друга", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.done)
                            .onSubmit(add)
                        if adding {
                            ProgressView()
                        } else {
                            Button("Добавить", action: add)
                                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let addError {
                        Text(addError).foregroundStyle(.red).font(.callout)
                    }
                }

                Section {
                    Toggle("Сообщать, когда друг в кампусе", isOn: $notify)
                        .onChange(of: notify) { _, on in
                            if on { Task { _ = await Notifier.requestPermission() } }
                        }
                } footer: {
                    Text("iOS проверяет в фоне сама — обычно раз в несколько часов, а также при открытии приложения.")
                }

                if store.logins.isEmpty {
                    Text("Добавьте логины друзей — здесь будет видно, кто сейчас в кампусе и за каким компьютером.")
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Section {
                        ForEach(sorted, id: \.self) { login in
                            Button { openProfile(login) } label: { row(login) }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        store.remove(login)
                                        states[login] = nil
                                    } label: {
                                        Label("Убрать", systemImage: "person.badge.minus")
                                    }
                                }
                        }
                    } header: {
                        Text("В кампусе: \(store.logins.filter { states[$0]?.workstation != nil }.count) из \(store.logins.count)")
                    } footer: {
                        Text("Смахните влево, чтобы убрать из друзей. Потяните вниз, чтобы обновить.")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Мои друзья")
        .refreshable { await refreshAll() }
        .task { if hasCredentials { await refreshAll() } }
    }

    private func row(_ login: String) -> some View {
        let state = states[login]
        let ws = state?.workstation
        return HStack(spacing: 14) {
            Text(String(login.prefix(1)).uppercased())
                .font(.headline.weight(.black))
                .foregroundStyle(Palette.onAccent)
                .frame(width: 40, height: 40)
                .background(Palette.accent, in: Circle())
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(ws != nil ? Palette.green : Palette.textSecondary)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Palette.card, lineWidth: 2))
                }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(login).font(.body.weight(.semibold)).foregroundStyle(.white)
                    if let level = state?.level {
                        Text("уровень \(level)").font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                Group {
                    if state == nil || state?.loaded == false {
                        Text("…").foregroundStyle(Palette.textSecondary)
                    } else if state?.failed == true {
                        Text("Не удалось загрузить").foregroundStyle(Palette.textSecondary)
                    } else if let ws {
                        Text(ws.label).foregroundStyle(Palette.green).fontWeight(.semibold)
                    } else {
                        Text("Сейчас не в кампусе").foregroundStyle(Palette.textSecondary)
                    }
                }
                .font(.caption)
            }
        }
    }

    private func load(_ login: String) async {
        do {
            async let ws = OpenAPI.workstation(login)
            let level = try? await OpenAPI.participant(login).level
            states[login] = FriendState(loaded: true, failed: false, workstation: try await ws, level: level)
        } catch {
            states[login] = FriendState(loaded: true, failed: true)
        }
    }

    private func refreshAll() async {
        let logins = store.logins
        for start in stride(from: 0, to: logins.count, by: 3) {
            await withTaskGroup(of: Void.self) { group in
                for login in logins[start..<min(start + 3, logins.count)] {
                    group.addTask { await load(login) }
                }
            }
        }
    }

    private func add() {
        let login = Friends.normalize(input)
        guard !login.isEmpty else { return }
        if store.contains(login) { addError = "Уже в списке"; return }
        if store.logins.count >= FriendsStore.maxCount { addError = "Не больше \(FriendsStore.maxCount) друзей"; return }
        focused = false
        adding = true
        addError = nil
        Task {
            do {
                let participant = try await OpenAPI.participant(login)
                let canonical = participant.login.lowercased()
                store.add(canonical)
                input = ""
                states[canonical] = FriendState(level: participant.level)
                await load(canonical)
            } catch APIError.http(404) {
                addError = "Пир с таким логином не найден"
            } catch {
                addError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            adding = false
        }
    }
}
