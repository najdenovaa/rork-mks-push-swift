//
//  MKSPushInboxWidget.swift
//  MKSPushWidget
//
//  "Сообщения" — shows the most recent incoming Max messages (author, time, and a
//  1-2 line preview). Tapping a row deep-links straight into Max, never MKS Push.
//  Data is pushed here by the host app via the shared App Group
//  (group.ru.mskpush.app) — this extension never makes network calls of its own.
//

import WidgetKit
import SwiftUI

nonisolated struct InboxEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let items: [InboxFeedItem]
}

nonisolated struct InboxProvider: TimelineProvider {
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
        InboxFeedItem(id: "1", chatId: "1", chatType: "dialog", title: "Анна", body: "Привет! Как дела?", time: "12:04"),
        InboxFeedItem(id: "2", chatId: "2", chatType: "chat", title: "Рабочий чат", body: "Встреча перенесена на 15:00", time: "11:47"),
        InboxFeedItem(id: "3", chatId: "3", chatType: "dialog", title: "Игорь", body: "Скинь, пожалуйста, файл", time: "09:30"),
    ]
}

struct MKSPushInboxWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: InboxEntry

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 3
        default: return 5
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader()
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { WidgetBackground() }
    }

    @ViewBuilder
    private var content: some View {
        if !entry.isConnected {
            WidgetEmptyState(text: "Не подключено")
        } else if entry.items.isEmpty {
            WidgetEmptyState(text: "Новых сообщений нет")
        } else {
            let rows = Array(entry.items.prefix(maxRows))
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { item in
                    Link(destination: WidgetOpenURL.forItem(item)) {
                        row(for: item)
                    }
                    if item.id != rows.last?.id {
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
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !item.time.isEmpty {
                    Text(formatTime(item.time))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(item.body)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(2)
        }
        .contentShape(Rectangle())
    }
}

struct MKSPushInboxWidget: Widget {
    let kind: String = "MKSPushInboxWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InboxProvider()) { entry in
            MKSPushInboxWidgetView(entry: entry)
        }
        .configurationDisplayName("Сообщения")
        .description("Последние сообщения из Max с текстом и временем.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
