import SwiftUI
import WidgetKit

@main
struct School21WidgetBundle: WidgetBundle {
    var body: some Widget {
        ProfileWidget()
    }
}

struct ProfileEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

/// Данные приносит приложение (при открытии и в фоне) через App Group; виджет только рисует.
struct ProfileProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProfileEntry {
        ProfileEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProfileEntry) -> Void) {
        completion(ProfileEntry(date: Date(), snapshot: SharedStore.loadSnapshot() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProfileEntry>) -> Void) {
        let entry = ProfileEntry(date: Date(), snapshot: SharedStore.loadSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

struct ProfileWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Profile", provider: ProfileProvider()) { entry in
            ProfileWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color(red: 0x27 / 255, green: 0x33 / 255, blue: 0x4A / 255), Palette.background],
                        startPoint: .topTrailing, endPoint: .bottomLeading
                    )
                }
                .widgetURL(URL(string: "https://platform.21-school.ru/"))
        }
        .configurationDisplayName("School 21")
        .description("Уровень, коины, место в кампусе и ближайшие события.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct ProfileWidgetView: View {
    let entry: ProfileEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .accessoryInline:
                Text("21 · ур. \(s.level) · \(s.coins) ₵")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("School 21 · \(s.login)").font(.caption2.bold())
                    Text("Уровень \(s.level) · \(s.exp.grouped) XP").font(.caption)
                    Text("\(s.coins) ₵ · PRP \(s.peerReviewPoints) · CRP \(s.codeReviewPoints)").font(.caption2)
                }
            case .systemMedium:
                medium(s)
            default:
                small(s)
            }
        } else {
            VStack(spacing: 6) {
                Badge(size: 28)
                Text("Откройте приложение и включите автовход")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    private func small(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Badge(size: 20)
                Text(s.login).font(.caption.bold()).lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(s.level)").font(.system(size: 36, weight: .black)).foregroundStyle(Palette.teal)
                Text("ур.").font(.caption).foregroundStyle(Palette.textSecondary)
            }
            Text("\(s.exp.grouped) XP").font(.caption.bold())
            Text("\(s.coins.grouped) ₵ · PRP \(s.peerReviewPoints)").font(.caption2).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ s: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Badge(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.login).font(.subheadline.bold()).lineLimit(1)
                    if let subtitle = s.subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(Palette.textSecondary).lineLimit(1)
                    }
                }
                Spacer()
                StatusPill(text: s.place ?? "Вне кампуса", active: s.place != nil)
            }
            HStack(alignment: .bottom) {
                Text("\(s.level)").font(.system(size: 34, weight: .black)).foregroundStyle(Palette.teal)
                VStack(alignment: .leading, spacing: 0) {
                    Text("уровень").font(.caption2).foregroundStyle(Palette.textSecondary)
                    Text("\(s.exp.grouped) XP").font(.caption.bold())
                }
                Spacer()
                if let coalition = s.coalition {
                    Text("🛡 \(coalition)" + (s.coalitionRank.map { " #\($0)" } ?? ""))
                        .font(.caption2.bold())
                        .lineLimit(1)
                }
            }
            HStack(spacing: 6) {
                StatTile(value: s.coins.grouped, label: "коины", accent: true)
                StatTile(value: "\(s.peerReviewPoints)", label: "PRP")
                StatTile(value: "\(s.codeReviewPoints)", label: "CRP")
            }
        }
    }
}

/// Плашка «21» на фирменном градиенте.
struct Badge: View {
    let size: CGFloat

    var body: some View {
        Text("21")
            .font(.system(size: size * 0.44, weight: .black))
            .foregroundStyle(Palette.onAccent)
            .frame(width: size, height: size)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: size / 3.5))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var accent = false

    var body: some View {
        VStack(spacing: 0) {
            Text(value).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.system(size: 9)).opacity(0.75)
        }
        .foregroundStyle(accent ? Palette.onAccent : .white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background {
            if accent {
                RoundedRectangle(cornerRadius: 12).fill(Palette.accent)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08))
            }
        }
    }
}

struct StatusPill: View {
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(active ? Palette.green : Palette.textSecondary).frame(width: 6, height: 6)
            Text(text).font(.caption2.bold()).lineLimit(1)
        }
        .foregroundStyle(active ? Palette.green : Palette.textSecondary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background((active ? Palette.green.opacity(0.14) : Color.white.opacity(0.08)), in: Capsule())
    }
}

extension Snapshot {
    /// Пример для превью в галерее виджетов.
    static let sample = Snapshot(
        login: "student", subtitle: "Core program", level: 5, exp: 2480, expToNextLevel: 320,
        coins: 240, peerReviewPoints: 4, codeReviewPoints: 6, logtime: 6.5, place: "Ocean · A5",
        coalition: "Capybaras", coalitionRank: 12, events: [], updatedAt: Date()
    )
}
