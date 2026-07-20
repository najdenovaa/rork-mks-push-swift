//
//  NotificationService.swift
//  MKSPushNotificationService
//
//  Downloads and attaches rich media (photo, or video thumbnail) to incoming
//  push notifications so the image shows up in the banner / lock screen.
//  Server payload:
//  {
//    "aps": {"alert": {...}, "mutable-content": 1},
//    "media_url": "https://...",
//    "media_type": "image" | "video" | "audio"
//  }
//

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
        let mediaType = Self.string(data, "media_type")

        // "audio" (and anything else) ships as text-only for now — no attachment.
        guard mediaType == "image" || mediaType == "video",
              let urlString = Self.string(data, "media_url"),
              let url = URL(string: urlString) else {
            contentHandler(content)
            return
        }

        downloadAttachment(from: url, mediaType: mediaType!) { attachment in
            if let attachment {
                content.attachments = [attachment]
            }
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Ran out of time (30s budget) — hand back whatever we have so far
        // rather than let the system show a generic "new notification".
        if let contentHandler, let bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    /// Downloads the media (photo, or video thumbnail image) and wraps it as a
    /// notification attachment. Both "image" and "video" media types are
    /// delivered as a still image URL by the server (video thumbnail), so both
    /// are saved with a .jpg extension.
    private func downloadAttachment(
        from url: URL,
        mediaType: String,
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
