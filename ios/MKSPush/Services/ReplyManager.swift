//
//  ReplyManager.swift
//  MKSPush
//
//  Handles the inline "Ответить" action on Max push notifications
//  (long press on lock screen / Notification Center / banner → reply
//  without opening the app). Sends the typed text straight to our server.
//

import Foundation
import UserNotifications

/// Eligibility + sending logic for the "max_reply" notification category.
/// Never used for channels, calls, reactions, VK pushes, or review/demo pushes.
enum ReplyManager {
    static let categoryIdentifier = "max_reply"
    static let replyActionIdentifier = "reply"

    // MARK: - Registration

    /// Registers the "max_reply" category with an inline text-input "Ответить" action.
    /// Must be called once at launch, before any notification is presented/acted on.
    static func registerCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: replyActionIdentifier,
            title: "Ответить",
            options: [],
            textInputButtonTitle: "Отправить",
            textInputPlaceholder: "Сообщение…"
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [replyAction],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Eligibility

    /// Whether a push payload supports inline reply: not a channel, not a call/reaction/VK
    /// push, not a review/demo push, and carries a chat_id to reply to.
    static func isReplyable(userInfo: [AnyHashable: Any]) -> Bool {
        let data = payloadData(userInfo)

        let pushType = string(data, "push_type") ?? "message"
        if pushType == "call" || pushType == "reaction" || pushType == "vk" {
            return false
        }

        if isReviewOrDemo(data) {
            return false
        }

        let chatType = string(data, "chat_type")
        if chatType == "channel" {
            return false
        }

        guard let chatId = string(data, "chat_id"), !chatId.isEmpty else {
            return false
        }

        let isDialog = string(data, "is_dialog")
        guard chatType == "dialog" || chatType == "chat" || isDialog == "1" else {
            return false
        }

        return true
    }

    /// Extracts chat_id from a push payload (top-level or nested under "data").
    static func chatId(from userInfo: [AnyHashable: Any]) -> String? {
        string(payloadData(userInfo), "chat_id")
    }

    private static func isReviewOrDemo(_ data: [AnyHashable: Any]) -> Bool {
        if let flag = data["review_mode"] as? String, flag == "1" { return true }
        if let flag = data["review_mode"] as? Bool, flag { return true }
        if let flag = data["demo"] as? String, flag == "1" { return true }
        if let flag = data["demo"] as? Bool, flag { return true }
        return false
    }

    // MARK: - Sending

    /// Sends the typed reply text to the server on behalf of the given userId.
    /// Returns true on success (200 { ok: true }); false on empty text or any failure.
    @discardableResult
    static func sendReply(userId: String, chatId: String, text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        do {
            try await APIService.shared.sendReply(userId: userId, chatId: chatId, text: trimmed)
            return true
        } catch {
            print("[ReplyManager] sendReply failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Payload helpers

    /// Push payloads may carry fields at the top level (APNs custom data) or nested under
    /// "data" — merge both, with the nested values taking precedence.
    private static func payloadData(_ userInfo: [AnyHashable: Any]) -> [AnyHashable: Any] {
        guard let nested = userInfo["data"] as? [String: Any] else { return userInfo }
        var merged = userInfo
        for (key, value) in nested { merged[key] = value }
        return merged
    }

    private static func string(_ dict: [AnyHashable: Any], _ key: String) -> String? {
        if let value = dict[key] as? String { return value }
        if let value = dict[key] as? NSNumber { return value.stringValue }
        return nil
    }
}
