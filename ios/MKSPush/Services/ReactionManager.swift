//
//  ReactionManager.swift
//  MKSPush
//
//  Emoji reactions on Max push notifications:
//  - Long-press a message push → tap 👍 / 🔥 / ❤️ → POST /api/react (reaction on
//    the original Max message, not a reply).
//  - Fallback: typing a single emoji into the "Ответить" field routes to the
//    react API instead of sending an emoji reply message.
//  Registers the shared "max_reply" category (reply action + 3 reaction actions).
//

import Foundation
import UserNotifications

/// Eligibility + sending logic for push notification reactions.
/// Never used for channels, calls, reactions, VK pushes, or review/demo pushes.
enum ReactionManager {
    static let thumbsUpActionIdentifier = "react_thumbs_up"
    static let fireActionIdentifier = "react_fire"
    static let heartActionIdentifier = "react_heart"

    static let reactionActionIdentifiers: Set<String> = [
        thumbsUpActionIdentifier, fireActionIdentifier, heartActionIdentifier,
    ]

    /// Emojis Max supports as reactions — used for the emoji-only reply fallback.
    private static let knownReactionEmojis: Set<String> = [
        "👍", "👎", "🔥", "❤️", "❤", "😂", "😍", "😮", "😢", "😡",
        "🎉", "💯", "🙏", "👏", "😁", "🤔", "💩",
    ]

    // MARK: - Registration

    /// Registers the shared "max_reply" category: inline text reply + 3 reaction
    /// buttons (iOS shows up to 4 actions). Single registration point for the app —
    /// replaces ReplyManager.registerCategories().
    static func registerCategories() {
        let replyAction = UNTextInputNotificationAction(
            identifier: ReplyManager.replyActionIdentifier,
            title: "Ответить",
            options: [],
            textInputButtonTitle: "Отправить",
            textInputPlaceholder: "Сообщение…"
        )
        let thumbsUp = UNNotificationAction(identifier: thumbsUpActionIdentifier, title: "👍", options: [])
        let fire = UNNotificationAction(identifier: fireActionIdentifier, title: "🔥", options: [])
        let heart = UNNotificationAction(identifier: heartActionIdentifier, title: "❤️", options: [])

        let category = UNNotificationCategory(
            identifier: ReplyManager.categoryIdentifier,
            actions: [replyAction, thumbsUp, fire, heart],
            intentIdentifiers: ["INSendMessageIntent"],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Eligibility

    /// Whether a push payload supports reactions: a plain message push (not call/
    /// reaction/vk/review/channel) carrying both chat_id and message_id.
    static func isReactable(userInfo: [AnyHashable: Any]) -> Bool {
        guard ReplyManager.isReplyable(userInfo: userInfo) else { return false }
        guard let messageId = ReplyManager.messageId(from: userInfo), !messageId.isEmpty else {
            return false
        }
        return true
    }

    // MARK: - Actions

    /// Maps a notification action identifier to its reaction emoji.
    static func reactionEmoji(for actionIdentifier: String) -> String? {
        switch actionIdentifier {
        case thumbsUpActionIdentifier: return "👍"
        case fireActionIdentifier: return "🔥"
        case heartActionIdentifier: return "❤️"
        default: return nil
        }
    }

    /// If the reply text is a single known reaction emoji (and nothing else),
    /// returns it — the caller should send a reaction instead of a text reply.
    static func isEmojiOnlyReactionText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 8 else { return nil }
        if knownReactionEmojis.contains(trimmed) { return trimmed }
        // Single grapheme that renders as emoji (covers skin tones / variants).
        guard trimmed.count == 1, let scalar = trimmed.unicodeScalars.first else { return nil }
        if scalar.properties.isEmojiPresentation || trimmed.unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
            return trimmed
        }
        return nil
    }

    // MARK: - Sending

    /// Sends an emoji reaction to the server. Returns true on success.
    @discardableResult
    static func sendReaction(userId: String, chatId: String, messageId: String, reaction: String) async -> Bool {
        do {
            try await APIService.shared.sendReaction(userId: userId, chatId: chatId, messageId: messageId, reaction: reaction)
            print("[ReactionManager] react ok chat=\(chatId) msg=\(messageId) emoji=\(reaction)")
            return true
        } catch {
            print("[ReactionManager] react failed: \(error.localizedDescription)")
            return false
        }
    }
}
