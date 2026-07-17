//
//  MKSPushUnreadWidget.swift
//  MKSPushWidget
//
//  "Непрочитанные" — a big unread-count glance widget. Tapping opens Max,
//  either to the most recent chat (if known) or the app root as a fallback.
//

import WidgetKit
import SwiftUI

nonisolated struct UnreadEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let unreadCount: Int
    let openURL: URL
}

nonisolated struct UnreadProvider: TimelineProvider {
    func placeholder(in context: Context) -> UnreadEntry {
        UnreadEntry(date: .now, isConnected: true, unreadCount: 3, openURL: WidgetOpenURL.fallback())
    }

    func getSnapshot(in context: Context, completion: @escaping (UnreadEntry) -> Void) {
        if context.isPreview {
            completion(UnreadEntry(date: .now, isConnected: true, unreadCount: 3, openURL: WidgetOpenURL.fallback()))
        } else {
            completion(currentEntry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UnreadEntry>) -> Void) {
        let entry = currentEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 5, to: .now) ?? .now.addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func currentEntry() -> UnreadEntry {
        UnreadEntry(
            date: .now,
            isConnected: SharedFeedStore.isConnected,
            unreadCount: SharedFeedStore.unreadCount(),
            openURL: SharedFeedStore.lastOpenURL() ?? WidgetOpenURL.fallback()
        )
    }
}

struct MKSPushUnreadWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UnreadEntry

    private var isAllRead: Bool { entry.unreadCount <= 0 }

    var body: some View {
        VStack(spacing: family == .systemSmall ? 2 : 6) {
            if family != .systemSmall {
                WidgetHeader()
                Spacer(minLength: 0)
            }
            if !entry.isConnected {
                WidgetEmptyState(text: "Не подключено")
            } else if isAllRead {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: family == .systemSmall ? 30 : 38))
                        .foregroundStyle(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                    Text("Всё прочитано")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255))
                }
            } else {
                VStack(spacing: 2) {
                    Text("\(entry.unreadCount)")
                        .font(.system(size: family == .systemSmall ? 44 : 56, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unreadLabel(entry.unreadCount))
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if family != .systemSmall {
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .containerBackground(for: .widget) { WidgetBackground() }
        .widgetURL(entry.isConnected ? entry.openURL : nil)
    }

    private func unreadLabel(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if (11...14).contains(mod100) {
            return "новых сообщений"
        }
        switch mod10 {
        case 1: return "непрочитанное"
        case 2, 3, 4: return "непрочитанных"
        default: return "непрочитанных"
        }
    }
}

struct MKSPushUnreadWidget: Widget {
    let kind: String = "MKSPushUnreadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UnreadProvider()) { entry in
            MKSPushUnreadWidgetView(entry: entry)
        }
        .configurationDisplayName("Непрочитанные")
        .description("Количество непрочитанных сообщений в Max.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
