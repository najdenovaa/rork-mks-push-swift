//
//  NotificationViewController.swift
//  MKSPushNotificationContent
//
//  Custom UI inside the expanded (long-pressed) Max message push:
//  a horizontally scrollable row of big emoji reactions — swipe left/right
//  to browse, tap to react (POST /api/react), Telegram-style.
//  Text replies still go through the system "Ответить" action below.
//

import UIKit
import UserNotifications
import UserNotificationsUI

final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private static let serverURL = URL(string: "https://mkspush.ru")!
    private static let appGroupId = "group.ru.mskpush.app"
    private static let emojis = ["👍", "❤️", "🔥", "😂", "😮", "😢", "🙏", "👏", "🎉", "💯", "👎", "😡"]

    private static let rowHeight: CGFloat = 72
    private static let emojiButtonSize: CGFloat = 56
    private static let emojiFontSize: CGFloat = 36

    private var chatId: String?
    private var messageId: String?
    private var isReactable = false
    private var isSending = false

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .secondarySystemBackground

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -16),
        ])

        for (index, emoji) in Self.emojis.enumerated() {
            let button = UIButton(type: .custom)
            button.setTitle(emoji, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: Self.emojiFontSize)
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = .systemGray5
            button.layer.cornerRadius = Self.emojiButtonSize / 2
            button.tag = index
            button.addTarget(self, action: #selector(reactionTapped(_:)), for: .touchUpInside)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalToConstant: Self.emojiButtonSize),
                button.heightAnchor.constraint(equalToConstant: Self.emojiButtonSize),
            ])
            stack.addArrangedSubview(button)
        }
    }

    override func viewDidLayoutSubviews() {
        // view.bounds.width is 0 in viewDidLoad/didReceive — the extension only
        // gets its real width here, so this is the reliable place to size content.
        super.viewDidLayoutSubviews()
        updatePreferredSize()
    }

    func didReceive(_ notification: UNNotification) {
        let data = Self.payloadData(notification.request.content.userInfo)
        chatId = Self.string(data, "chat_id")
        messageId = Self.string(data, "message_id")
        // No message_id (or non-reactable push) — hide the row entirely.
        isReactable = (chatId?.isEmpty == false) && (messageId?.isEmpty == false)
        NSLog(
            "[MKSPush ContentExt] chat_id=%@ message_id=%@ reactable=%d width=%.0f",
            chatId ?? "nil", messageId ?? "nil", isReactable ? 1 : 0, view.bounds.width
        )
        updatePreferredSize()
    }

    private func updatePreferredSize() {
        scrollView.isHidden = !isReactable
        guard isReactable else {
            preferredContentSize = .zero
            return
        }
        guard view.bounds.width > 0 else { return } // wait for real layout
        preferredContentSize = CGSize(width: view.bounds.width, height: Self.rowHeight)
    }

    // MARK: - Reaction tap

    @objc private func reactionTapped(_ sender: UIButton) {
        guard !isSending,
              let chatId, let messageId,
              let emoji = sender.title(for: .normal),
              let userId = Self.storedUserId(), !userId.isEmpty else { return }
        isSending = true

        UIView.animate(withDuration: 0.12, animations: {
            sender.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
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
