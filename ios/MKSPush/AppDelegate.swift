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
        // VoIP pushes for CallKit
        CallManager.shared.registerForVoIPPushes()

        // Standard APNs registration
        PushManager.shared.registerIfAuthorized()

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
        // Apply badge from payload if present
        let userInfo = notification.request.content.userInfo
        if let aps = userInfo["aps"] as? [String: Any], let badge = aps["badge"] as? Int {
            BadgeSync.shared.applyBadge(badge)
        }
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo

        // Apply badge from payload
        if let aps = userInfo["aps"] as? [String: Any], let badge = aps["badge"] as? Int {
            BadgeSync.shared.applyBadge(badge)
        }

        DeepLinkManager.shared.openAppFromPush(userInfo: userInfo)
        completionHandler()
    }
}

extension Notification.Name {
    static let mkspushDeepLink = Notification.Name("mkspushDeepLink")
}
