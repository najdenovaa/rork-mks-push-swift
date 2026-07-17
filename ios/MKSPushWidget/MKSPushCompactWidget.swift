//
//  MKSPushCompactWidget.swift
//  MKSPushWidget
//
//  "Кратко" — a denser feed of just author + time, fitting more rows than the
//  full inbox widget. Tapping a row deep-links straight into Max.
//

import WidgetKit
import SwiftUI

nonisolated struct CompactProvider: TimelineProvider {
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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> InboxEntry {
        InboxEntry(date: .now, isConnected: SharedFeedStore.isConnected, items: SharedFeedStore.loadFeed())
    }

    private static let placeholderItems: [InboxFeedItem] = [
        InboxFeedItem(id: "1", chatId: "1", chatType: "dialog", title: "Анна", body: "", time: "12:04"),
        InboxFeedItem(id: "2", chatId: "2", chatType: "chat", title: "Рабочий чат", body: "", time: "11:47"),
        InboxFeedItem(id: "3", chatId: "3", chatType: "dialog", title: "Игорь", body: "", time: "09:30"),
        InboxFeedItem(id: "4", chatId: "4", chatType: "dialog", title: "Мама", body: "", time: "08:52"),
        InboxFeedItem(id: "5", chatId: "5", chatType: "chat", title: "Проект X", body: "", time: "08:10"),
    ]
}

struct MKSPushCompactWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: InboxEntry

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 5
        case .systemMedium: return 6
        default: return 8
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
            VStack(alignment: .leading, spacing: 5) {
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
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 4)
            if !item.time.isEmpty {
                Text(formatTime(item.time))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .contentShape(Rectangle())
    }
}

struct MKSPushCompactWidget: Widget {
    let kind: String = "MKSPushCompactWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CompactProvider()) { entry in
            MKSPushCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("Кратко")
        .description("Список чатов: автор и время, без текста сообщений.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
