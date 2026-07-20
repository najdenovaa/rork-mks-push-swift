//
//  AppDelegate.swift
//  MKSPush
//
//  App delegate bootstraps PushKit/CallKit, APNs, deep links, and applies
//  push notification badge from payload.
//

import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Debug: dump UIBackgroundModes from final Info.plist
        if let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
            print("[DEBUG] UIBackgroundModes: \(modes)")
            NSLog("[DEBUG] UIBackgroundModes: %@", modes.description)
        } else {
            print("[DEBUG] UIBackgroundModes: NOT FOUND IN PLIST")
            NSLog("[DEBUG] UIBackgroundModes: NOT FOUND IN PLIST")
        }

        // VoIP pushes for CallKit — register and schedule 30s check
        CallManager.shared.registerForVoIPPushes()
        CallManager.shared.reRegisterIfNeeded()
        CallManager.shared.scheduleDelayedVoipCheck()

        // Standard APNs registration
        PushManager.shared.registerIfAuthorized()

        // Inline "Ответить" action on Max message pushes (lock screen / Notification Center / banner)
        ReplyManager.registerCategories()

        // Live Activity push-to-start token for the typing indicator (iOS 17.2+)
        if #available(iOS 16.2, *) {
            TypingActivityManager.observePushToStartToken()
        }

        // Also sync VoIP token if persisted from previous launch
        CallManager.shared.syncVoipToken()

        // Badge & notification delegate
        UNUserNotificationCenter.current().delegate = self

        // Reset badge on cold start
        BadgeSync.shared.resetBadge()

        return true
    }

    // MARK: - APNs

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error: error)
    }

    // MARK: - Deep links

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // Dispatch to the ContentView's AppState via notification
        NotificationCenter.default.post(name: .mkspushDeepLink, object: url)
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications in foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo

        // Typing pushes drive the Dynamic Island Live Activity only — never a banner/sound.
        if TypingPush.isTyping(userInfo) {
            if #available(iOS 16.2, *) {
                Task { await TypingActivityManager.handle(payload: userInfo) }
            }
            completionHandler([])
            return
        }

        // Apply badge from payload if present
        if let aps = userInfo["aps"] as? [String: Any], let badge = aps["badge"] as? Int {
            BadgeSync.shared.applyBadge(badge)
        }
        // Keep the Home Screen widget's feed fresh whenever a push arrives in the foreground.
        // Wrapped in a background task so the refresh can finish even if the app is about
        // to be backgrounded right after the banner is shown.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "widget-refresh-willpresent") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        Task {
            await WidgetFeedManager.refresh(userId: UserStore.userId)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// Silent/background push delivery — refresh the widget feed even if the app never comes to foreground.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Silent typing push → Live Activity only; no widget refresh, no badge.
        if TypingPush.isTyping(userInfo) {
            guard #available(iOS 16.2, *) else {
                completionHandler(.noData)
                return
            }
            var typingTask: UIBackgroundTaskIdentifier = .invalid
            typingTask = UIApplication.shared.beginBackgroundTask(withName: "typing-live-activity") {
                UIApplication.shared.endBackgroundTask(typingTask)
                typingTask = .invalid
            }
            Task {
                await TypingActivityManager.handle(payload: userInfo)
                if typingTask != .invalid {
                    UIApplication.shared.endBackgroundTask(typingTask)
                    typingTask = .invalid
                }
                completionHandler(.noData)
            }
            return
        }

        if let aps = userInfo["aps"] as? [String: Any], let badge = aps["badge"] as? Int {
            BadgeSync.shared.applyBadge(badge)
        }
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "widget-refresh-remote-notification") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        Task {
            let refreshed = await WidgetFeedManager.refresh(userId: UserStore.userId)
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            completionHandler(refreshed ? .newData : .noData)
        }
    }

    /// Handle notification tap or inline action.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        // Apply badge from payload
        if let aps = userInfo["aps"] as? [String: Any], let badge = aps["badge"] as? Int {
            BadgeSync.shared.applyBadge(badge)
        }

        // Inline "Ответить" action from long-press — send text to server, never open the app.
        // completionHandler() is deferred until the HTTP request actually finishes (see
        // handleReplyAction), so the system keeps us alive for delivery instead of racing it.
        if response.actionIdentifier == ReplyManager.replyActionIdentifier,
           let textResponse = response as? UNTextInputNotificationResponse {
            handleReplyAction(
                textResponse: textResponse,
                userInfo: userInfo,
                identifier: response.notification.request.identifier,
                completionHandler: completionHandler
            )
            return
        }

        Task { await WidgetFeedManager.refresh(userId: UserStore.userId) }
        DeepLinkManager.shared.openAppFromPush(userInfo: userInfo)
        completionHandler()
    }

    /// Sends the typed reply text to the server without opening the app. Wrapped in a
    /// background task so iOS keeps the process alive long enough for the HTTP request
    /// to finish; `completionHandler()` is only invoked once that request settles.
    private func handleReplyAction(textResponse: UNTextInputNotificationResponse, userInfo: [AnyHashable: Any], identifier: String, completionHandler: @escaping () -> Void) {
        guard ReplyManager.isReplyable(userInfo: userInfo) else {
            completionHandler()
            return
        }
        guard let userId = UserStore.userId, !userId.isEmpty else {
            completionHandler()
            return
        }
        guard let chatId = ReplyManager.chatId(from: userInfo) else {
            completionHandler()
            return
        }
        let text = textResponse.userText

        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "quick-reply-send") {
            // Expiration handler: the system is about to kill us — still signal completion
            // so the notification UI doesn't hang, then close out the background task.
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
            completionHandler()
        }

        Task {
            let success = await ReplyManager.sendReply(userId: userId, chatId: chatId, text: text)
            if success {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
            }
            if bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(bgTask)
                bgTask = .invalid
            }
            // Only signal completion to the system after the HTTP request has finished.
            completionHandler()
        }
    }
}

extension Notification.Name {
    static let mkspushDeepLink = Notification.Name("mkspushDeepLink")
}
