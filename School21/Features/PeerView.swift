import SwiftUI

/// «Где сидит пир»: место в кампусе и данные по логину (официальный Open API).
struct PeerView: View {
    let openProfile: (String) -> Void

    @State private var query = ""
    @State private var loading = false
    @State private var error: String?
    @State private var result: PeerResult?
    @FocusState private var focused: Bool
    @ObservedObject private var friends = FriendsStore.shared

    private struct PeerResult {
        let participant: Participant
        let workstation: Workstation?
        let points: Points?
        let logtime: Double?
        let coalition: Coalition?
    }

    private var ownLogin: String? { Keychain.loadCredentials()?.apiLogin }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if ownLogin == nil {
                    Text("Данные берутся из официального API Школы 21, для него нужен ваш логин и пароль. Включите автовход: Настройки → Автовход.")
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.textSecondary)
                        TextField("Логин пира", text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .submitLabel(.search)
                            .onSubmit { search(query) }
                    }
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))

                    HStack {
                        Button("Найти") { search(query) }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Palette.onAccent)
                            .disabled(loading || query.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button {
                            if let ownLogin { search(ownLogin) }
                        } label: {
                            Label("Я", systemImage: "person.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(loading)
                    }
                }

                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let error {
                    Text(error).foregroundStyle(.red)
                } else if let result {
                    card(result)
                }
            }
            .padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Где сидит пир")
    }

    private func search(_ login: String) {
        let login = String(login.trimmingCharacters(in: .whitespaces).split(separator: "@").first ?? "").lowercased()
        guard !login.isEmpty else { return }
        query = login
        focused = false
        loading = true
        error = nil
        result = nil
        Task {
            do {
                async let participant = OpenAPI.participant(login)
                async let workstation = OpenAPI.workstation(login)
                let points = try? await OpenAPI.points(login)
                let logtime = try? await OpenAPI.logtime(login)
                let coalition = (try? await OpenAPI.coalition(login)) ?? nil
                result = PeerResult(participant: try await participant, workstation: try await workstation,
                                    points: points, logtime: logtime, coalition: coalition)
            } catch APIError.http(404) {
                error = "Пир с таким логином не найден"
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }

    private func card(_ r: PeerResult) -> some View {
        let p = r.participant
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(String(p.login.prefix(1)).uppercased())
                    .font(.title2.weight(.black))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 52, height: 52)
                    .background(Palette.accent, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.login).font(.title3.bold())
                    let subtitle = [p.parallelName, p.className, p.campus].compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }

            HStack(spacing: 8) {
                StatusPill(text: r.workstation?.label ?? "Сейчас не в кампусе", active: r.workstation != nil)
                if let c = r.coalition {
                    Text("🛡 \(c.name)" + (c.rank.map { "  #\($0)" } ?? ""))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
            }

            HStack(alignment: .bottom) {
                Text("\(p.level)").font(.system(size: 44, weight: .black)).foregroundStyle(Palette.teal)
                VStack(alignment: .leading) {
                    Text("уровень").font(.caption).foregroundStyle(Palette.textSecondary)
                    Text("\(p.expValue.grouped) XP").font(.subheadline.bold())
                }
                Spacer()
                if p.expToNextLevel > 0 {
                    VStack(alignment: .trailing) {
                        Text("до \(p.level + 1) уровня").font(.caption).foregroundStyle(Palette.textSecondary)
                        Text("\(p.expToNextLevel.grouped) XP").font(.subheadline.bold())
                    }
                }
            }

            if let pts = r.points {
                HStack(spacing: 10) {
                    StatTile(value: pts.coins.grouped, label: "коины", accent: true)
                    StatTile(value: "\(pts.peerReviewPoints)", label: "PRP")
                    StatTile(value: "\(pts.codeReviewPoints)", label: "CRP")
                }
            }
            if let logtime = r.logtime {
                Text("Логтайм: \(logtime, specifier: "%.1f") ч (в среднем за неделю)")
                    .font(.callout).foregroundStyle(Palette.textSecondary)
            }
            Button("Открыть профиль на платформе") { openProfile(p.login) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            if p.login.lowercased() != ownLogin {
                let isFriend = friends.contains(p.login)
                Button(isFriend ? "В друзьях" : "Добавить в друзья") { friends.add(p.login) }
                    .buttonStyle(.bordered)
                    .tint(Palette.green)
                    .frame(maxWidth: .infinity)
                    .disabled(isFriend || friends.logins.count >= FriendsStore.maxCount)
            }
        }
        .padding(20)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(accent ? Palette.onAccent.opacity(0.75) : Palette.textSecondary)
        }
        .foregroundStyle(accent ? Palette.onAccent : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background {
            if accent {
                RoundedRectangle(cornerRadius: 16).fill(Palette.accent)
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Palette.cardRaised)
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(active ? Palette.green : Palette.textSecondary).frame(width: 8, height: 8)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(active ? Palette.green : Palette.textSecondary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((active ? Palette.green.opacity(0.14) : Palette.cardRaised), in: Capsule())
    }
}
