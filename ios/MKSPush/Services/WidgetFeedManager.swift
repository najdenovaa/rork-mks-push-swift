//
//  WidgetFeedManager.swift
//  MKSPush
//
//  Keeps the Home Screen widget's "recent Max messages" feed in sync via the shared
//  App Group container (group.ru.mskpush.app). The widget process only reads this
//  cache — all networking happens here, in the host app.
//

import Foundation
import SwiftUI
import UIKit
import WidgetKit

/// Builds deep links that open **Max** (never the MKS Push host app) directly to a chat.
/// Deliberately duplicated (minimal) on the widget extension side in SharedFeed.swift,
/// since the extension can't import this host-app target. Keep both in sync.
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

/// Reads/writes the widget feed through the App Group so the widget extension
/// (a separate process) can display it without making network calls of its own.
enum WidgetFeedStore {
    static let appGroupId = "group.ru.mskpush.app"
    private static let feedKey = "widget_inbox_feed"
    private static let connectedKey = "widget_is_connected"
    private static let unreadCountKey = "widget_unread_count"
    private static let lastOpenURLKey = "widget_last_open_url"

    /// All three Home Screen widget kinds share this feed; every save reloads all of them.
    private static let widgetKinds = ["MKSPushInboxWidget", "MKSPushCompactWidget", "MKSPushUnreadWidget"]

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func saveFeed(_ items: [InboxFeedItem], unreadCount: Int) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: feedKey)
        }
        defaults.set(unreadCount, forKey: unreadCountKey)
        if let first = items.first {
            defaults.set(WidgetOpenURL.forItem(first).absoluteString, forKey: lastOpenURLKey)
        } else {
            defaults.removeObject(forKey: lastOpenURLKey)
        }
        defaults.set(true, forKey: connectedKey)
        reloadAllTimelines()
    }

    /// Clears the feed and flips the widgets into their "not connected" empty state.
    static func markDisconnected() {
        guard let defaults else { return }
        defaults.set(false, forKey: connectedKey)
        defaults.removeObject(forKey: feedKey)
        defaults.removeObject(forKey: unreadCountKey)
        defaults.removeObject(forKey: lastOpenURLKey)
        reloadAllTimelines()
    }

    private static func reloadAllTimelines() {
        for kind in widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}

/// Fetches the recent-messages feed from the server and publishes it to the widgets'
/// shared storage. Safe to call frequently — always no-ops quietly on failure.
enum WidgetFeedManager {
    private static let limit = 5

    @discardableResult
    static func refresh(userId: String?) async -> Bool {
        guard let userId, !userId.isEmpty else {
            WidgetFeedStore.markDisconnected()
            return false
        }

        // Give the fetch a background-execution window so it can finish even if the app
        // is backgrounded mid-flight (e.g. triggered right as a push arrives).
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "widget-feed-refresh") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        defer {
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }

        do {
            let response = try await APIService.shared.fetchInboxResponse(userId: userId, limit: limit)
            WidgetFeedStore.saveFeed(response.items ?? [], unreadCount: response.unreadCount ?? 0)
            return true
        } catch {
            print("[WidgetFeedManager] refresh failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - SwiftUI scene-phase observer

/// Attach to root view to keep the widget feed fresh whenever the app becomes active.
struct WidgetFeedSyncViewModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var appState: AppState

    func body(content: Content) -> some View {
        content
            .onAppear {
                Task { await WidgetFeedManager.refresh(userId: appState.userId) }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    Task { await WidgetFeedManager.refresh(userId: appState.userId) }
                }
            }
    }
}

extension View {
    func withWidgetFeedSync(appState: AppState) -> some View {
        modifier(WidgetFeedSyncViewModifier(appState: appState))
    }
}
