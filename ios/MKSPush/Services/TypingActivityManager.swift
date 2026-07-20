//
//  TypingActivityManager.swift
//  MKSPush
//
//  Drives the "собеседник печатает…" Live Activity in the Dynamic Island.
//  One typing activity at a time, keyed by chat_id:
//  - start   → request a new activity (ends any previous one first)
//  - refresh → extend the stale date / update the sender name
//  - end     → dismiss immediately
//  Also reports the ActivityKit push-to-start token (iOS 17.2+) to the server.
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

    /// How long the activity stays fresh without a refresh push.
    private static let staleInterval: TimeInterval = 30

    /// Routes a typing push payload to start/refresh/end.
    static func handle(payload: [AnyHashable: Any]) async {
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

        // Different chat (or stray activities) — end everything first.
        await endAllActivities()

        let attributes = TypingActivityAttributes(chatId: chatId, senderId: senderId)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: makeContent(senderName: senderName),
                pushType: nil
            )
            currentActivity = activity
            currentChatId = chatId
            lastStartAt = Date()
        } catch {
            print("[TypingActivityManager] start failed: \(error.localizedDescription)")
        }
    }

    static func refresh(chatId: String, senderId: String, senderName: String? = nil) async {
        if let activity = currentActivity, currentChatId == chatId {
            let name = senderName ?? activity.content.state.senderName
            await activity.update(makeContent(senderName: name))
        } else if let senderName, !senderName.isEmpty {
            // Missed the start push — treat this refresh as a start.
            await start(senderName: senderName, chatId: chatId, senderId: senderId)
        }
    }

    static func end(chatId: String) async {
        for activity in Activity<TypingActivityAttributes>.activities where activity.attributes.chatId == chatId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if currentChatId == chatId {
            currentActivity = nil
            currentChatId = nil
        }
    }

    private static func endAllActivities() async {
        for activity in Activity<TypingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
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
                    print("[TypingActivityManager] token send failed: \(error.localizedDescription)")
                }
            }
        }
    }
}
