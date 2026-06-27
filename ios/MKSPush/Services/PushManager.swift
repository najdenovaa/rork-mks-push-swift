//
//  PushManager.swift
//  MKSPush
//
//  Standard remote (APNs) notification registration. Optional — the app works without it.
//

import Foundation
import Combine
import UIKit
import UserNotifications

/// Observable manager for standard notification permission + APNs token registration.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    /// Current notification authorization status.
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var pendingTokenSend = false

    private override init() {
        super.init()
    }

    /// Refreshes the cached authorization status from the system.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Requests notification permission. Returns true if granted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                pendingTokenSend = true
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            print("[PushManager] requestAuthorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Called when APNs returns a device token.
    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        guard let userId = UserStore.userId else { return }
        Task { await APIService.shared.sendAPNsToken(userId: userId, token: token) }
    }

    func didFailToRegister(error: Error) {
        print("[PushManager] APNs registration failed: \(error.localizedDescription)")
    }

    /// Re-registers if permission is already granted (e.g. on launch).
    func registerIfAuthorized() {
        Task {
            await refreshAuthorizationStatus()
            if authorizationStatus == .authorized {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
}
