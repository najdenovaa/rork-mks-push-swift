//
//  DeepLinkManager.swift
//  MKSPush
//
//  Handles mkspush:// deep links, push notification taps,
//  and the openLinkedApp flow. Pixel-parity with React Native lib/notifications.ts.
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

        // Extract userId from /go/{id} or /pair/{id} in the URL
        let pushUserId = extractUserIdFromPushURL(urlString)

        // VK links → open VK native
        if let url = urlString, isVKURL(url) {
            openVKNative()
            return
        }

        // Resolve and open via linked app flow
        let resolved = resolvePushOpenURL(urlString)
        openLinkedApp(httpsURL: resolved, userId: pushUserId)
    }

    /// Opens a linked app from the ConnectedScreen "Открыть профиль" button.
    func openLinkedApp(httpsURL: String? = nil, userId: String? = nil) {
        // VK → open native
        if let url = httpsURL, isVKURL(url) {
            openVKNative()
            return
        }

        // Resolve userId ONLY from passed param or URL — never fall back to UserStore.userId
        let resolvedUserId: String? = userId ?? extractUserIdFromMKSURL(httpsURL) ?? extractUserIdFromPushURL(httpsURL)

        // Fetch open-target from server ONLY when we have a userId
        // AND there's no specific URL (or it's the generic mkspush.ru/go)
        if let uid = resolvedUserId, httpsURL == nil || isMKSGoURL(httpsURL!) {
            Task {
                if let target = try? await api.openTarget(userId: uid), let t = URL(string: target) {
                    await MainActor.run { UIApplication.shared.open(t) }
                    return
                }
                await MainActor.run { self.fallbackOpen(httpsURL: httpsURL) }
            }
            return
        }

        // Max URL → native scheme (production push taps)
        if let url = httpsURL, isAllowedMaxURL(url), let native = nativeMaxURL(url) {
            if let u = URL(string: native) {
                UIApplication.shared.open(u)
                return
            }
        }

        // Open https URL directly or fallback
        fallbackOpen(httpsURL: httpsURL)
    }

    // MARK: - Private helpers

    private func fallbackOpen(httpsURL: String?) {
        if let url = httpsURL, let u = URL(string: url) {
            if isAllowedMaxURL(url), let native = nativeMaxURL(url), let nu = URL(string: native) {
                UIApplication.shared.open(nu)
                return
            }
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
        let pathParts = components.path.split(separator: "/").map(String.init)
        if let idx = pathParts.firstIndex(of: "pair"), idx + 1 < pathParts.count {
            return pathParts[idx + 1]
        }
        if let userId = components.queryItems?.first(where: { $0.name == "user_id" })?.value {
            return userId
        }
        return nil
    }

    /// Extract userId from push URL paths like /go/{id} or /pair/{id}
    private func extractUserIdFromPushURL(_ urlString: String?) -> String? {
        guard let url = urlString,
              let components = URLComponents(string: url) else { return nil }
        let pathParts = components.path.split(separator: "/").map(String.init)
        if let idx = pathParts.firstIndex(of: "go"), idx + 1 < pathParts.count {
            return pathParts[idx + 1]
        }
        if let idx = pathParts.firstIndex(of: "pair"), idx + 1 < pathParts.count {
            return pathParts[idx + 1]
        }
        return extractUserIdFromMKSURL(urlString)
    }
}
