import SwiftUI

/// Меню «⋯»: закладки и стартовая страница, «Где сидит пир», «Мои друзья», поделиться, Safari, настройки.
struct MenuSheet: View {
    let close: () -> Void
    @EnvironmentObject private var web: WebStore
    @ObservedObject private var bookmarks = Bookmarks.shared
    @State private var pinning = false

    var body: some View {
        NavigationStack {
            List {
                if !bookmarks.items.isEmpty {
                    Section {
                        ForEach(bookmarks.items) { bookmark in
                            bookmarkRow(bookmark)
                        }
                    } header: {
                        Text("Закладки")
                    } footer: {
                        Text("Смахните закладку влево: ⌂ — открывать её при запуске, корзина — удалить.")
                    }
                }

                Section {
                    Button {
                        pin()
                    } label: {
                        Label(bookmarks.contains(web.currentURL) ? "Страница уже в закладках" : "Закрепить эту страницу",
                              systemImage: "bookmark")
                    }
                    .disabled(pinning || bookmarks.contains(web.currentURL) || !(web.currentURL.map(AppConfig.isInternal) ?? false))
                }

                Section {
                    NavigationLink {
                        PeerView(openProfile: { login in
                            close()
                            if let url = URL(string: "\(AppConfig.platformOrigin)/profile/\(login)") { web.open(url) }
                        })
                    } label: {
                        Label("Где сидит пир", systemImage: "mappin.and.ellipse")
                    }
                    NavigationLink {
                        FriendsView(openProfile: { login in
                            close()
                            if let url = URL(string: "\(AppConfig.platformOrigin)/profile/\(login)") { web.open(url) }
                        })
                    } label: {
                        Label("Мои друзья", systemImage: "person.2")
                    }
                    Button {
                        close()
                        web.reload()
                    } label: {
                        Label("Обновить страницу", systemImage: "arrow.clockwise")
                    }
                    if let url = web.currentURL {
                        ShareLink(item: url) {
                            Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIApplication.shared.open(url)
                        } label: {
                            Label("Открыть в Safari", systemImage: "safari")
                        }
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Настройки", systemImage: "gearshape")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("School 21")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        let isStart = bookmarks.startURL == bookmark.url
        return Button {
            close()
            web.open(bookmark.url)
        } label: {
            HStack {
                Image(systemName: "bookmark.fill").foregroundStyle(Palette.cyan)
                Text(bookmark.title).foregroundStyle(.primary).lineLimit(1)
                Spacer()
                if isStart {
                    Image(systemName: "house.fill").foregroundStyle(Palette.green)
                }
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                bookmarks.remove(bookmark)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
            Button {
                bookmarks.setStart(isStart ? nil : bookmark.url)
            } label: {
                Label(isStart ? "Не стартовая" : "Стартовая", systemImage: isStart ? "house.slash" : "house")
            }
            .tint(Palette.teal)
        }
        .contextMenu {
            Button {
                bookmarks.setStart(isStart ? nil : bookmark.url)
            } label: {
                Label(isStart ? "Не открывать при запуске" : "Открывать при запуске", systemImage: "house")
            }
            Button(role: .destructive) {
                bookmarks.remove(bookmark)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    private func pin() {
        guard let url = web.currentURL else { return }
        pinning = true
        Task {
            let title = await web.pageTitle()
            bookmarks.add(title: title, url: url)
            pinning = false
        }
    }
}
