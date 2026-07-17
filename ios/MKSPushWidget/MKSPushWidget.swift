//
//  MKSPushWidget.swift
//  MKSPushWidget
//
//  Home Screen widget showing the 3-5 most recent incoming Max messages
//  (direct chats + groups). Data is pushed here by the host app via the
//  shared App Group (group.ru.mskpush.app) — this extension never makes
//  network calls of its own.
//

import WidgetKit
import SwiftUI

nonisolated struct InboxEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let items: [InboxFeedItem]
}

nonisolated struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> InboxEntry {
        InboxEntry(date: .now, isConnected: true, items: Self.placeholderItems)
    }

    func getSnapshot(in context: Context, completion: @escaping (InboxEntry) -> Void) {
        if context.isPreview {
            completion(InboxEntry(date: .now, isConnected: true, items: Self.placeholderItems))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InboxEntry>) -> Void) {
        let entry = currentEntry()
        // The host app pushes fresh data via WidgetCenter.reloadTimelines() whenever the
        // feed changes; this periodic refresh is just a conservative fallback.
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> InboxEntry {
        InboxEntry(date: .now, isConnected: SharedFeedStore.isConnected, items: SharedFeedStore.loadFeed())
    }

    private static let placeholderItems: [InboxFeedItem] = [
        InboxFeedItem(id: "1", chatId: "1", chatType: "dialog", title: "Анна", body: "Привет! Как дела?", time: ""),
        InboxFeedItem(id: "2", chatId: "2", chatType: "chat", title: "Рабочий чат", body: "Встреча перенесена на 15:00", time: ""),
        InboxFeedItem(id: "3", chatId: "3", chatType: "dialog", title: "Игорь", body: "Скинь, пожалуйста, файл", time: ""),
    ]
}

struct MKSPushWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: Provider.Entry

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 7 / 255, green: 26 / 255, blue: 16 / 255),
                    Color(red: 12 / 255, green: 40 / 255, blue: 24 / 255),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                .frame(width: 7, height: 7)
            Text("MKS Push")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isConnected {
            emptyState("Не подключено")
        } else if entry.items.isEmpty {
            emptyState("Новых сообщений нет")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(entry.items.prefix(maxRows))) { item in
                    row(for: item)
                    if item.id != entry.items.prefix(maxRows).last?.id {
                        Divider().overlay(Color.white.opacity(0.08))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(for item: InboxFeedItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.displayTitle(for: item))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !item.time.isEmpty {
                    Text(Self.shortTime(item.time))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(item.body)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
        }
    }

    /// Strips a leading "(Max) " tag some server payloads include in the title.
    private static func displayTitle(for item: InboxFeedItem) -> String {
        let prefix = "(Max) "
        if item.title.hasPrefix(prefix) {
            return String(item.title.dropFirst(prefix.count))
        }
        return item.title
    }

    /// Renders a server-provided time string as a short "HH:mm" label. Accepts either an
    /// ISO-8601 timestamp or an already-short time string (returned as-is if unparsable).
    private static func shortTime(_ raw: String) -> String {
        if raw.count <= 5, raw.contains(":") {
            return raw
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: raw)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: raw)
        }
        guard let date else { return raw }
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "HH:mm"
        return displayFormatter.string(from: date)
    }

    private func emptyState(_ text: String) -> some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 4)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
    }
}

struct MKSPushWidget: Widget {
    let kind: String = "MKSPushWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MKSPushWidgetView(entry: entry)
        }
        .configurationDisplayName("MKS Push")
        .description("Последние сообщения Max.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
