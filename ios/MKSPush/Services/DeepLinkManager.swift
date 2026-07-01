//
//  DeepLinkManager.swift
//  MKSPush
//
//  Handles mkspush:// deep links, push notification taps,
//  and the openLinkedApp flow. Ported from React Native lib/notifications.ts.
//

import Combine
import Foundation
import SwiftUI
import UIKit

/// Resolves and opens the correct target app/URL for deep links and push taps.
final class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()

    private let api = APIService.shared

    private init() {}

    // MARK: - Incoming deep link

    /// Handle mkspush://pair?user_id=XXX
    func handleDeepLink(_ url: URL, appState: AppState) {
        guard let scheme = url.scheme?.lowercased(), scheme == "mkspush" else { return }
        guard url.host == "pair" else { return }
        guard let query = url.query else {
            // Just "mkspush://pair" without query — ignore
            return
        }
        // Parse user_id from query string
        let params = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let userId = params.first(where: { $0.name == "user_id" })?.value, !userId.isEmpty {
            DispatchQueue.main.async {
                appState.setUserIdFromDeepLink(userId)
            }
        }
    }

    // MARK: - Push notification tap

    /// Called when user taps a push notification. Opens the appropriate app.
    func openAppFromPush(userInfo: [AnyHashable: Any]) {
        // Parse URL from either direct "url" key (APNs) or nested "data.url" (Expo)
        let urlString = (userInfo["url"] as? String)
            ?? (userInfo["data"] as? [String: Any])?["url"] as? String

        // VK links → open VK native
        if let url = urlString, isVKURL(url) {
            openVKNative()
            return
        }

        // Other: resolve via open-target
        let resolved = resolvePushOpenURL(urlString)
        openLinkedApp(httpsURL: resolved)
    }

    /// Opens a linked app from the ConnectedScreen "Открыть приложение" button.
    /// - If the URL is a Max link (max.ru), skips server open-target entirely.
    /// - Server open-target is called only when the URL is nil or the generic mkspush.ru/go.
    func openLinkedApp(httpsURL: String? = nil, userId: String? = nil) {
        let resolvedUserId: String? = userId ?? extractUserIdFromMKSURL(httpsURL) ?? UserStore.userId

        // VK → open native
        if let url = httpsURL, isVKURL(url) {
            openVKNative()
            return
        }

        // Max URL → skip server, go straight to native max://
        if let url = httpsURL, isAllowedMaxURL(url) {
            fallbackOpen(httpsURL: httpsURL)
            return
        }

        // open-target only when no URL or the generic mkspush.ru/go link
        let useOpenTarget = httpsURL == nil || isMKSGoURL(httpsURL!)
        if useOpenTarget, let uid = resolvedUserId {
            Task {
                if let target = try? await api.openTarget(userId: uid), let t = URL(string: target) {
                    await MainActor.run { UIApplication.shared.open(t) }
                    return
                }
                await MainActor.run { self.fallbackOpen(httpsURL: httpsURL) }
            }
        } else {
            fallbackOpen(httpsURL: httpsURL)
        }
    }

    // MARK: - Private helpers

    private func fallbackOpen(httpsURL: String?) {
        if let url = httpsURL, isAllowedMaxURL(url), let native = nativeMaxURL(url) {
            UIApplication.shared.open(URL(string: native)!)

        } else if let url = httpsURL, let u = URL(string: url) {
            UIApplication.shared.open(u)
        } else {
            openFallbackApp()
        }
    }

    private func openFallbackApp() {
        guard let url = URL(string: "max://") else { return }
        UIApplication.shared.open(url)
    }

    private func resolvePushOpenURL(_ urlString: String?) -> String? {
        if let url = urlString, isAllowedOpenURL(url) {
            return url
        }
        return Theme.linkedAppURL
    }

    // MARK: - URL predicates

    private func isVKURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://vk.com") || lower.hasPrefix("https://vk.me")
            || lower.hasPrefix("vk.com") || lower.hasPrefix("vk://")
            || lower.contains("mkspush.ru/go?s=vk") || lower.contains("mkspush.ru/go/vk")
    }

    private func openVKNative() {
        guard let vkURL = URL(string: "vk://") else { return }
        UIApplication.shared.open(vkURL) { success in
            if !success {
                print("[DeepLinkManager] Failed to open vk://")
            }
        }
    }

    private func isAllowedOpenURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        let allowedHosts = ["max.ru", "vk.com", "mkspush.ru"]
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased() else { return false }
        return allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") })
    }

    private func isMKSGoURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower == Theme.linkedAppURL.lowercased()
            || lower == "mkspush.ru/go"
            || lower.contains("mkspush.ru/go")
    }

    private func isAllowedMaxURL(_ url: String) -> Bool {
        guard let host = URLComponents(string: url)?.host?.lowercased() else { return false }
        return host == "max.ru" || host.hasSuffix(".max.ru")
    }

    private func nativeMaxURL(_ httpsURL: String) -> String? {
        guard var comps = URLComponents(string: httpsURL),
              let host = comps.host else { return nil }
        comps.scheme = Theme.linkedAppScheme
        // If host is exactly "max.ru" or ends with ".max.ru", keep it
        if host == "max.ru" || host.hasSuffix(".max.ru") {
            return comps.string
        }
        return "\(Theme.linkedAppScheme)://"
    }

    private func extractUserIdFromMKSURL(_ urlString: String?) -> String? {
        guard let url = urlString,
              let components = URLComponents(string: url),
              let host = components.host?.lowercased(),
              host.hasSuffix("mkspush.ru") || host == "mkspush.ru" else { return nil }
        // Try path segments: /pair/USER_ID or query ?user_id=XXX
        let pathParts = components.path.split(separator: "/").map(String.init)
        if let idx = pathParts.firstIndex(of: "pair"), idx + 1 < pathParts.count {
            return pathParts[idx + 1]
        }
        if let userId = components.queryItems?.first(where: { $0.name == "user_id" })?.value {
            return userId
        }
        return nil
    }
}
