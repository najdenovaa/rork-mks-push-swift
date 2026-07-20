//
//  TypingActivityManager.swift
//  MKSPush
//
//  Drives the "собеседник печатает…" Live Activity in the Dynamic Island.
//  One typing activity at a time, keyed by chat_id:
//  - start   → reuse a live remote-started activity if one already exists,
//              otherwise request a new one (ending any stray activity first)
//  - refresh → extend the stale date / update the sender name
//  - end     → dismiss immediately
//  Also reports the ActivityKit push-to-start token (iOS 17.2+) and each
//  activity's own push token to the server, so the server can update/end the
//  activity remotely without relying on the app staying alive.
//

import ActivityKit
import Foundation

@available(iOS 16.2, *)
@MainActor
enum TypingActivityManager {
    private static var currentActivity: Activity<TypingActivityAttributes>?
    private static var currentChatId: String?
    private static var lastStartAt: Date = .distantPast
    private static var pushToStartTask: Task<Void, Never>?
    private static var activityUpdatesTask: Task<Void, Never>?
    private static var activityTokenTasks: [String: Task<Void, Never>] = [:]

    /// How long the activity stays fresh without a refresh push.
    private static let staleInterval: TimeInterval = 30

    /// Routes a typing push payload to start/refresh/end.
    static func handle(payload: [AnyHashable: Any]) async {
        // A remote push-to-start may have created an activity while the app was
        // dead — make sure its live token is (re)reported before we act on it.
        syncExistingActivityPushTokens()
        guard let event = TypingPush.parse(payload) else { return }
        switch event.kind {
        case .start:
            await start(senderName: event.senderName ?? "Собеседник", chatId: event.chatId, senderId: event.senderId)
        case .refresh:
            await refresh(chatId: event.chatId, senderId: event.senderId, senderName: event.senderName)
        case .end:
            await end(chatId: event.chatId)
        }
    }

    static func start(senderName: String, chatId: String, senderId: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[TypingActivityManager] Live Activities disabled by user")
            return
        }

        // Dedupe duplicate start pushes for the same chat within 1 second.
        if currentActivity != nil, currentChatId == chatId, Date().timeIntervalSince(lastStartAt) < 1 {
            return
        }

        // Same chat already live — just refresh content and staleness.
        if let activity = currentActivity, currentChatId == chatId {
            await activity.update(makeContent(senderName: senderName))
            lastStartAt = Date()
            return
        }

        // A remote push-to-start (or another launch path) may have already created
        // this chat's activity — reuse it instead of ending/recreating.
        if let existing = Activity<TypingActivityAttributes>.activities.first(where: { $0.attributes.chatId == chatId }) {
            await existing.update(makeContent(senderName: senderName))
            currentActivity = existing
            currentChatId = chatId
            lastStartAt = Date()
            observeActivityPushToken(for: existing)
            await sendCurrentPushTokenIfAvailable(for: existing)
            return
        }

        // Different chat (or stray activities) — end everything first.
        await endAllActivities()

        let attributes = TypingActivityAttributes(chatId: chatId, senderId: senderId)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: makeContent(senderName: senderName),
                pushType: .token
            )
            currentActivity = activity
            currentChatId = chatId
            lastStartAt = Date()
            observeActivityPushToken(for: activity)
            await sendCurrentPushTokenIfAvailable(for: activity)
        } catch {
            print("[TypingActivityManager] start failed: \(error.localizedDescription)")
        }
    }

    static func refresh(chatId: String, senderId: String, senderName: String? = nil) async {
        if let activity = currentActivity, currentChatId == chatId {
            let name = senderName ?? activity.content.state.senderName
            await activity.update(makeContent(senderName: name))
            lastStartAt = Date()
            return
        }
        if let existing = Activity<TypingActivityAttributes>.activities.first(where: { $0.attributes.chatId == chatId }) {
            let name = senderName ?? existing.content.state.senderName
            await existing.update(makeContent(senderName: name))
            currentActivity = existing
            currentChatId = chatId
            lastStartAt = Date()
            observeActivityPushToken(for: existing)
            return
        }
        if let senderName, !senderName.isEmpty {
            // Missed the start push — treat this refresh as a start.
            await start(senderName: senderName, chatId: chatId, senderId: senderId)
        }
    }

    /// Ends ALL typing activities — a message arriving means typing stopped, and
    /// stray activities from other chats should never linger on the island.
    static func end(chatId: String) async {
        for activity in Activity<TypingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for task in activityTokenTasks.values { task.cancel() }
        activityTokenTasks.removeAll()
        currentActivity = nil
        currentChatId = nil
    }

    private static func endAllActivities() async {
        for activity in Activity<TypingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        for task in activityTokenTasks.values { task.cancel() }
        activityTokenTasks.removeAll()
        currentActivity = nil
        currentChatId = nil
    }

    private static func makeContent(senderName: String) -> ActivityContent<TypingActivityAttributes.ContentState> {
        ActivityContent(
            state: TypingActivityAttributes.ContentState(senderName: senderName),
            staleDate: Date().addingTimeInterval(staleInterval)
        )
    }

    // MARK: - Push-to-start token (iOS 17.2+)

    /// Observes the ActivityKit push-to-start token and reports it to the server,
    /// so the server can start the typing activity even when the app isn't running.
    static func observePushToStartToken() {
        guard #available(iOS 17.2, *) else { return }
        pushToStartTask?.cancel()
        pushToStartTask = Task {
            for await tokenData in Activity<TypingActivityAttributes>.pushToStartTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                guard let userId = UserStore.userId, !userId.isEmpty else { continue }
                do {
                    try await APIService.shared.sendTypingActivityToken(userId: userId, token: token)
                    print("[TypingActivityManager] push-to-start token sent")
                } catch {
                    print("[TypingActivityManager] push-to-start token send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Observes activities created outside our own `start()` path (remote
    /// push-to-start while the app was killed) and reports their live push
    /// tokens, so the server can end them — otherwise the island flashes and
    /// never dismisses.
    static func observeActivityUpdates() {
        activityUpdatesTask?.cancel()
        activityUpdatesTask = Task {
            for await activity in Activity<TypingActivityAttributes>.activityUpdates {
                observeActivityPushToken(for: activity)
            }
        }
    }

    /// Observes a single activity's own push token so the server can update/end it
    /// remotely (e.g. when the typing stops but the app never receives another push).
    private static func observeActivityPushToken(for activity: Activity<TypingActivityAttributes>) {
        let chatId = activity.attributes.chatId
        activityTokenTasks[chatId]?.cancel()
        activityTokenTasks[chatId] = Task {
            for await tokenData in activity.pushTokenUpdates {
                let token = tokenData.map { String(format: "%02x", $0) }.joined()
                guard let userId = UserStore.userId, !userId.isEmpty else { continue }
                do {
                    try await APIService.shared.sendTypingLiveToken(userId: userId, chatId: chatId, token: token)
                    print("[TypingActivityManager] activity push token sent for chat \(chatId)")
                } catch {
                    print("[TypingActivityManager] activity push token send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Re-reports push tokens for any activities that are already running when the
    /// app (re)launches, so the server always has a fresh token to end/update them.
    static func syncExistingActivityPushTokens() {
        for activity in Activity<TypingActivityAttributes>.activities {
            if currentChatId == nil {
                currentActivity = activity
                currentChatId = activity.attributes.chatId
            }
            observeActivityPushToken(for: activity)
            Task { await sendCurrentPushTokenIfAvailable(for: activity) }
        }
    }

    /// If the activity already has a push token (available synchronously), sends it
    /// to the server right away — awaited, so background-task callers can keep the
    /// process alive until the HTTP request actually finishes. The async
    /// `pushTokenUpdates` observer still covers tokens that arrive later.
    private static func sendCurrentPushTokenIfAvailable(for activity: Activity<TypingActivityAttributes>) async {
        guard let tokenData = activity.pushToken else { return }
        guard let userId = UserStore.userId, !userId.isEmpty else { return }
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        do {
            try await APIService.shared.sendTypingLiveToken(userId: userId, chatId: activity.attributes.chatId, token: token)
            print("[TypingActivityManager] current activity push token sent for chat \(activity.attributes.chatId)")
        } catch {
            print("[TypingActivityManager] current activity push token send failed: \(error.localizedDescription)")
        }
    }
}
