//
//  NotificationViewController.swift
//  MKSPushNotificationContent
//
//  Custom UI inside the expanded (long-pressed) Max message push:
//  a grid of big emoji reactions (up to 12, 6 per row) —
//  tap to react (POST /api/react), Telegram-style.
//  The emoji list comes from the push payload's top-level "reactions"
//  array; falls back to a built-in default set when absent.
//  Text replies still go through the system "Ответить" action below.
//

import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private static let serverURL = URL(string: "https://mkspush.ru")!
    private static let appGroupId = "group.ru.mskpush.app"
    // Fallback used only when the push payload doesn't carry "reactions".
    private static let defaultReactions: [String] = [
        "👍", "❤️", "🔥", "😂", "😮", "🙏", "😢", "👏", "🎉", "💯", "👎", "😡",
    ]
    private static let columnsPerRow = 6
    private static let maxReactions = 12

    private static let buttonHeight: CGFloat = 52
    private static let emojiFontSize: CGFloat = 30
    private static let rowSpacing: CGFloat = 10
    private static let verticalPadding: CGFloat = 12
    private static let horizontalPadding: CGFloat = 14
    private static func gridHeight(rowCount: Int) -> CGFloat {
        CGFloat(rowCount) * buttonHeight
            + CGFloat(max(rowCount - 1, 0)) * rowSpacing
            + verticalPadding * 2
    }

    private var chatId: String?
    private var messageId: String?
    private var isSending = false
    private var currentReactions: [String] = []

    private let container = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground

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

        // Build with the default set immediately — the grid never depends on
        // payload timing. didReceive rebuilds it with the payload's own list
        // (if present) before the extension is shown to the user.
        buildGrid(with: Self.defaultReactions)
    }

    func didReceive(_ notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        let data = Self.payloadData(userInfo)
        chatId = Self.string(data, "chat_id")
        messageId = Self.string(data, "message_id")

        // "reactions" lives at the top level of the push payload, not inside
        // the nested "data" dict — read it from the raw userInfo.
        let reactions = (userInfo["reactions"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultReactions
        buildGrid(with: reactions)

        NSLog(
            "[MKSPush ContentExt] didReceive chat_id=%@ message_id=%@ reactions=%d",
            chatId ?? "nil", messageId ?? "nil", currentReactions.count
        )
    }

    // MARK: - Grid building

    private func buildGrid(with reactions: [String]) {
        let clamped = Array(reactions.prefix(Self.maxReactions))
        guard clamped != currentReactions else { return }
        currentReactions = clamped

        container.arrangedSubviews.forEach {
            container.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let rows = stride(from: 0, to: clamped.count, by: Self.columnsPerRow).map {
            Array(clamped[$0..<min($0 + Self.columnsPerRow, clamped.count)])
        }

        for row in rows {
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

        preferredContentSize = CGSize(width: 0, height: Self.gridHeight(rowCount: rows.count))
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
