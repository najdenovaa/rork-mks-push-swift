//
//  PushManager.swift
//  MKSPush
//
//  Standard APNs notification registration with retry.
//  Retries every 15s until the server confirms receipt.
//  Ported from React Native build 23 PushTokenSync.
//

import Combine
import Foundation
import UIKit
import UserNotifications
import SwiftUI

/// Manages standard notification permission + APNs token registration with retry.
@MainActor
final class PushManager: NSObject, ObservableObject {
    static let shared = PushManager()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let api = APIService.shared
    private var retryTask: Task<Void, Never>?
    private var currentToken: String?

    private override init() {
        super.init()
    }

    // MARK: - Permission

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        } catch {
            print("[PushManager] requestAuthorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Re-register if already authorized (e.g. on cold start).
    func registerIfAuthorized() {
        Task {
            await refreshAuthorizationStatus()
            if authorizationStatus == .authorized {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    // MARK: - Token handling

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        currentToken = token
        startRetryLoop(token: token)
    }

    func didFailToRegister(error: Error) {
        print("[PushManager] APNs registration failed: \(error.localizedDescription)")
    }

    /// Re-send token on return to foreground.
    func syncOnForeground() {
        guard let token = currentToken else { return }
        startRetryLoop(token: token)
    }

    /// Force-start retry loop if we have a token but no loop is running.
    /// Called from AppState.start() after userId becomes available.
    func kickRetryIfNeeded() {
        guard let token = currentToken else { return }
        if retryTask == nil || retryTask?.isCancelled == true {
            startRetryLoop(token: token)
        }
    }

    // MARK: - Retry loop

    func startRetryLoop(token: String) {
        retryTask?.cancel()
        retryTask = Task {
            while !Task.isCancelled {
                guard let userId = UserStore.userId else {
                    // No userId yet — sleep and retry
                    try? await Task.sleep(for: .seconds(15))
                    continue
                }
                do {
                    try await api.sendAPNsToken(userId: userId, token: token)
                    print("[PushManager] APNs token synced successfully")
                    break
                } catch {
                    print("[PushManager] APNs token sync failed, retrying in 15s: \(error.localizedDescription)")
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

// MARK: - Scene-phase observer for foreground re-sync

struct PushTokenSyncViewModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    PushManager.shared.syncOnForeground()
                    CallManager.shared.syncVoipToken()
                }
            }
    }
}

extension View {
    func withPushTokenSync() -> some View {
        modifier(PushTokenSyncViewModifier())
    }
}
