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
import WidgetKit

/// Reads/writes the widget feed through the App Group so the widget extension
/// (a separate process) can display it without making network calls of its own.
enum WidgetFeedStore {
    static let appGroupId = "group.ru.mskpush.app"
    private static let feedKey = "widget_inbox_feed"
    private static let connectedKey = "widget_is_connected"
    private static let widgetKind = "MKSPushWidget"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupId)
    }

    static func saveFeed(_ items: [InboxFeedItem]) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(items) {
            defaults.set(data, forKey: feedKey)
        }
        defaults.set(true, forKey: connectedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Clears the feed and flips the widget into its "not connected" empty state.
    static func markDisconnected() {
        guard let defaults else { return }
        defaults.set(false, forKey: connectedKey)
        defaults.removeObject(forKey: feedKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}

/// Fetches the recent-messages feed from the server and publishes it to the widget's
/// shared storage. Safe to call frequently — always no-ops quietly on failure.
enum WidgetFeedManager {
    private static let limit = 5

    @discardableResult
    static func refresh(userId: String?) async -> Bool {
        guard let userId, !userId.isEmpty else {
            WidgetFeedStore.markDisconnected()
            return false
        }
        do {
            let items = try await APIService.shared.fetchInbox(userId: userId, limit: limit)
            WidgetFeedStore.saveFeed(items)
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
    @EnvironmentObject private var appState: AppState

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
    func withWidgetFeedSync() -> some View {
        modifier(WidgetFeedSyncViewModifier())
    }
}
