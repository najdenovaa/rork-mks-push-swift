//
//  TypingPush.swift
//  MKSPush
//
//  Parses silent "typing" pushes (push_type == "typing") that drive the
//  Dynamic Island Live Activity. Fields may arrive at the top level of the
//  APNs payload or nested under "data" — same convention as ReplyManager.
//

import Foundation

nonisolated enum TypingPush {
    nonisolated enum EventKind: String {
        case start
        case refresh
        case end
    }

    nonisolated struct Event {
        let kind: EventKind
        let chatId: String
        let senderId: String
        let senderName: String?
    }

    /// Whether this push payload is a typing push (never shows a banner).
    static func isTyping(_ userInfo: [AnyHashable: Any]) -> Bool {
        string(payloadData(userInfo), "push_type") == "typing"
    }

    /// Parses a typing push into an event. Returns nil if the payload is not
    /// a typing push or is missing the required chat_id / typing_event fields.
    static func parse(_ userInfo: [AnyHashable: Any]) -> Event? {
        let data = payloadData(userInfo)
        guard string(data, "push_type") == "typing" else { return nil }
        guard let rawEvent = string(data, "typing_event"),
              let kind = EventKind(rawValue: rawEvent) else { return nil }
        guard let chatId = string(data, "chat_id"), !chatId.isEmpty else { return nil }
        return Event(
            kind: kind,
            chatId: chatId,
            senderId: string(data, "sender_id") ?? "",
            senderName: string(data, "sender_name")
        )
    }

    // MARK: - Payload helpers

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
