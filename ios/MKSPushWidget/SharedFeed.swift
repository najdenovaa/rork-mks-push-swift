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
}
