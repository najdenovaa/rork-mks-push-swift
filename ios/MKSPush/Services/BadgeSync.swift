//
//  BadgeSync.swift
//  MKSPush
//
//  Keeps the iOS app icon badge in sync with the server.
//  Ported from React Native build 23 BadgeSync.tsx.
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// Non-UI service that resets the app badge on launch/foreground
/// and applies badges from incoming push notifications.
@MainActor
final class BadgeSync: ObservableObject {

    static let shared = BadgeSync()

    private let api = APIService.shared

    private init() {}

    /// Call on launch and when scene becomes active.
    func resetBadge() {
        UIApplication.shared.applicationIconBadgeNumber = 0
        guard let userId = UserStore.userId else { return }
        Task {
            await api.resetBadge(userId: userId)
        }
    }

    /// Apply badge number from a push payload.
    func applyBadge(_ number: Int) {
        UIApplication.shared.applicationIconBadgeNumber = number
    }
}

// MARK: - SwiftUI scene-phase observer

/// Attach to root view to reset badge on foreground.
struct BadgeSyncViewModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var badgeSync = BadgeSync.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                badgeSync.resetBadge()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    badgeSync.resetBadge()
                }
            }
    }
}

extension View {
    func withBadgeSync() -> some View {
        modifier(BadgeSyncViewModifier())
    }
}
