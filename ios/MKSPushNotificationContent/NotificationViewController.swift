//
//  NotificationViewController.swift
//  MKSPushNotificationContent
//
//  Custom UI inside the expanded (long-pressed) Max message push:
//  a static 2-row grid of 6 big emoji reactions each (12 total) —
//  tap to react (POST /api/react), Telegram-style.
//  Text replies still go through the system "Ответить" action below.
//

import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private static let serverURL = URL(string: "https://mkspush.ru")!
    private static let appGroupId = "group.ru.mskpush.app"
    // 2 rows x 6 columns, most-used reactions first.
    private static let emojiRows: [[String]] = [
        ["👍", "❤️", "🔥", "😂", "😮", "🙏"],
        ["😢", "👏", "🎉", "💯", "👎", "😡"],
    ]

    private static let buttonHeight: CGFloat = 52
    private static let emojiFontSize: CGFloat = 30
    private static let rowSpacing: CGFloat = 10
    private static let verticalPadding: CGFloat = 12
    private static let horizontalPadding: CGFloat = 14
    private static var gridHeight: CGFloat {
        CGFloat(emojiRows.count) * buttonHeight
            + CGFloat(emojiRows.count - 1) * rowSpacing
            + verticalPadding * 2
    }

    private var chatId: String?
    private var messageId: String?
    private var isSending = false

    private let container = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground

        // Fix the height immediately — the grid never depends on payload or layout
        // timing. Hiding/zeroing based on payload was what produced the blank area:
        // the system had already reserved space but the grid was invisible.
        preferredContentSize = CGSize(width: 0, height: Self.gridHeight)

        container.axis = .vertical
        container.spacing = Self.rowSpacing
        container.distribution = .fillEqually
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.horizontalPadding),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.horizontalPadding),
            container.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.verticalPadding),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.verticalPadding),
        ])

        for row in Self.emojiRows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            rowStack.alignment = .fill

            for emoji in row {
                let button = UIButton(type: .custom)
                button.setTitle(emoji, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: Self.emojiFontSize)
                button.setTitleColor(.label, for: .normal)
                button.backgroundColor = .systemGray5
                button.layer.cornerRadius = Self.buttonHeight / 2
                button.addTarget(self, action: #selector(reactionTapped(_:)), for: .touchUpInside)
                rowStack.addArrangedSubview(button)
            }
            container.addArrangedSubview(rowStack)
        }
    }

    func didReceive(_ notification: UNNotification) {
        // Only parse the payload here — the grid is ALWAYS visible (the max_reply
        // category is only attached to reactable message pushes anyway). Tap-time
        // guards handle any push that somehow lacks chat_id/message_id.
        let data = Self.payloadData(notification.request.content.userInfo)
        chatId = Self.string(data, "chat_id")
        messageId = Self.string(data, "message_id")
        NSLog(
            "[MKSPush ContentExt] didReceive chat_id=%@ message_id=%@",
            chatId ?? "nil", messageId ?? "nil"
        )
        preferredContentSize = CGSize(width: 0, height: Self.gridHeight)
    }

    // MARK: - Reaction tap

    @objc private func reactionTapped(_ sender: UIButton) {
        guard !isSending,
              let chatId, let messageId,
              let emoji = sender.title(for: .normal),
              let userId = Self.storedUserId(), !userId.isEmpty else { return }
        isSending = true

        UIView.animate(withDuration: 0.12, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
            sender.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.3)
        })
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        sendReaction(userId: userId, chatId: chatId, messageId: messageId, emoji: emoji) { [weak self] success in
            DispatchQueue.main.async {
                guard let self else { return }
                if success {
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    self.extensionContext?.dismissNotificationContentExtension()
                } else {
                    self.isSending = false
                    UIView.animate(withDuration: 0.12) {
                        sender.transform = .identity
                        sender.backgroundColor = .systemGray5
                    }
                }
            }
        }
    }

    private func sendReaction(userId: String, chatId: String, messageId: String, emoji: String, completion: @escaping (Bool) -> Void) {
        let url = Self.serverURL.appendingPathComponent("api/react/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        let chatIdValue: Any = Int(chatId) ?? chatId
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "chat_id": chatIdValue,
            "message_id": messageId,
            "reaction": emoji,
        ])
        URLSession.shared.dataTask(with: request) { _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false)
            if !ok {
                NSLog("[MKSPush ContentExt] react failed: %@", error?.localizedDescription ?? "http error")
            }
            completion(ok)
        }.resume()
    }

    // MARK: - Helpers

    /// userId is mirrored by the main app into the shared App Group defaults.
    private static func storedUserId() -> String? {
        UserDefaults(suiteName: appGroupId)?.string(forKey: "user_id")
    }

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
