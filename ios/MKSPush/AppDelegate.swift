//
//  AppDelegate.swift
//  MKSPush
//

import UIKit

/// App delegate to bootstrap PushKit/CallKit at launch and handle APNs token callbacks.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Register for VoIP pushes immediately — required for CallKit privileges.
        CallManager.shared.registerForVoIPPushes()
        // Re-register for standard APNs notifications if the user already granted permission.
        PushManager.shared.registerIfAuthorized()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushManager.shared.didFailToRegister(error: error)
    }
}
