//
//  SharedFeed.swift
//  MKSPushWidget
//
//  The widget runs in its own process and cannot import the host app's target,
//  so this is a deliberately duplicated, minimal mirror of
//  MKSPush/Services/WidgetFeedManager.swift's write format. Keep both in sync.
//

import Foundation

/// One row of the "recent Max messages" Home Screen widget feed.
nonisolated struct InboxFeedItem: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let chatId: String
    let chatType: String?
    let title: String
    let body: String
    let time: String

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case chatType = "chat_type"
        case title
        case body
        case time
    }
}

/// Read-only access to the feed the host app publishes via the shared App Group.
enum SharedFeedStore {
    static let appGroupId = "group.ru.mskpush.app"
    private static let feedKey = "widget_inbox_feed"
    private static let connectedKey = "widget_is_connected"
    private static let unreadCountKey = "widget_unread_count"
    private static let lastOpenURLKey = "widget_last_open_url"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func loadFeed() -> [InboxFeedItem] {
        guard let defaults, let data = defaults.data(forKey: feedKey) else { return [] }
        return (try? JSONDecoder().decode([InboxFeedItem].self, from: data)) ?? []
    }

    static var isConnected: Bool {
        defaults?.bool(forKey: connectedKey) ?? false
    }

    static func unreadCount() -> Int {
        defaults?.integer(forKey: unreadCountKey) ?? 0
    }

    /// The URL of the most recent chat, published by the host app whenever it refreshes
    /// the feed. Used as the tap target for the "Unread" widget.
    static func lastOpenURL() -> URL? {
        guard let raw = defaults?.string(forKey: lastOpenURLKey) else { return nil }
        return URL(string: raw)
    }
}

/// Builds deep links that open **Max** (never the MKS Push host app) directly to a chat.
enum WidgetOpenURL {
    static func forItem(_ item: InboxFeedItem) -> URL {
        if !item.chatId.isEmpty,
           let u = URL(string: "max://chat?chatId=\(item.chatId)") {
            return u
        }
        if !item.chatId.isEmpty,
           let u = URL(string: "https://web.max.ru/?chatId=\(item.chatId)") {
            return u
        }
        return fallback()
    }

    static func fallback() -> URL {
        URL(string: "max://")!
    }
}

/// Renders a server-provided time string (e.g. "2026-07-17 07:00:43") as a short, local
/// "HH:mm" label. Falls back to the raw string if it can't be parsed.
func formatTime(_ raw: String) -> String {
    if raw.isEmpty { return raw }
    if raw.count <= 5, raw.contains(":") {
        return raw
    }

    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = isoFormatter.date(from: raw)
    if date == nil {
        isoFormatter.formatOptions = [.withInternetDateTime]
        date = isoFormatter.date(from: raw)
    }
    if date == nil {
        let sqlFormatter = DateFormatter()
        sqlFormatter.locale = Locale(identifier: "en_US_POSIX")
        sqlFormatter.timeZone = TimeZone(identifier: "UTC")
        sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        date = sqlFormatter.date(from: raw)
    }
    guard let date else { return raw }

    let displayFormatter = DateFormatter()
    displayFormatter.dateFormat = "HH:mm"
    return displayFormatter.string(from: date)
}
