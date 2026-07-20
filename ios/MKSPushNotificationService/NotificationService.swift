//
//  NotificationService.swift
//  MKSPushNotificationService
//
//  Turns incoming message pushes into Telegram-style notifications:
//  - Communication Notification (INSendMessageIntent) with the sender's round
//    avatar on the left + app icon badge (system-drawn, nothing manual).
//  - Rich media: downloads media_url (photo / video thumbnail) and attaches it
//    so the image preview shows in the banner / lock screen.
//  Both are applied together when the payload carries both.
//
//  Server payload:
//  {
//    "aps": {"alert": {"title":"(Max) Имя","body":"текст"}, "mutable-content": 1},
//    "chat_id": "...", "sender_id": "...", "sender_name": "Имя",
//    "sender_avatar_url": "https://...",
//    "media_url": "https://...", "media_type": "image|video|audio",
//    "push_type": "message"
//  }
//

import Intents
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        let data = Self.payloadData(request.content.userInfo)

        // Rich media: "image" and "video" both deliver a still image URL
        // (video → thumbnail). "audio" and everything else stays text-only.
        let mediaType = Self.string(data, "media_type")
        let mediaURL: URL? = {
            guard mediaType == "image" || mediaType == "video",
                  let urlString = Self.string(data, "media_url") else { return nil }
            return URL(string: urlString)
        }()
        let avatarURL: URL? = Self.string(data, "sender_avatar_url").flatMap { URL(string: $0) }

        // Download avatar + media in parallel, then compose the final content.
        let group = DispatchGroup()
        var avatarData: Data?
        var mediaAttachment: UNNotificationAttachment?

        if let avatarURL {
            group.enter()
            Self.downloadData(from: avatarURL) { downloaded in
                avatarData = downloaded
                group.leave()
            }
        }
        if let mediaURL {
            group.enter()
            Self.downloadAttachment(from: mediaURL) { attachment in
                mediaAttachment = attachment
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            if let mediaAttachment {
                content.attachments = [mediaAttachment]
            }
            guard let self else {
                contentHandler(content)
                return
            }
            let finalContent = self.applyCommunicationStyle(content, data: data, avatarData: avatarData)
            self.bestAttemptContent = (finalContent as? UNMutableNotificationContent) ?? content
            contentHandler(finalContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Ran out of time (30s budget) — hand back whatever we have so far
        // rather than let the system show a generic "new notification".
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Communication Notification (Telegram-style avatar)

    /// Donates an incoming INSendMessageIntent so iOS renders the sender's round
    /// avatar with the app icon badge (system Communication Notification style).
    private func applyCommunicationStyle(
        _ content: UNMutableNotificationContent,
        data: [AnyHashable: Any],
        avatarData: Data?
    ) -> UNNotificationContent {
        guard let senderName = Self.string(data, "sender_name"),
              let senderId = Self.string(data, "sender_id") else {
            return content
        }

        var avatarImage: INImage?
        if let avatarData {
            avatarImage = INImage(imageData: avatarData)
        }

        let sender = INPerson(
            personHandle: INPersonHandle(value: senderId, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: avatarImage,
            contactIdentifier: nil,
            customIdentifier: senderId
        )

        let chatId = Self.string(data, "chat_id") ?? UUID().uuidString
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: chatId,
            serviceName: "Max",
            sender: sender,
            attachments: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        interaction.donate()

        if let updated = try? content.updating(from: intent) {
            return updated
        }
        return content
    }

    // MARK: - Downloads

    /// Downloads raw bytes (avatar image) with a 20s timeout.
    private static func downloadData(from url: URL, completion: @escaping (Data?) -> Void) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data, error == nil else {
                completion(nil)
                return
            }
            completion(data)
        }.resume()
    }

    /// Downloads the media (photo, or video thumbnail image) and wraps it as a
    /// notification attachment, saved with a .jpg extension.
    private static func downloadAttachment(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        URLSession.shared.downloadTask(with: request) { location, _, error in
            guard let location, error == nil else {
                completion(nil)
                return
            }
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("jpg")
            do {
                try FileManager.default.moveItem(at: location, to: tmp)
                let attachment = try UNNotificationAttachment(
                    identifier: "media",
                    url: tmp,
                    options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Payload helpers

    /// Payload fields can arrive top-level or nested under "data" (mirrors
    /// ReplyManager's payload parsing on the app side).
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
