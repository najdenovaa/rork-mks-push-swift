//
//  AppState.swift
//  MKSPush
//
//  State machine matching React Native providers/app.tsx build 23.
//

import Foundation
import SwiftUI
import Combine

/// Top-level screen routes.
enum AppRoute: Equatable {
    case welcome
    case qr
    case connected
}

/// Observable state machine managing user identity, pairing flow, and routing.
@MainActor
final class AppState: ObservableObject {
    // MARK: - Published state

    @Published var route: AppRoute = .welcome
    @Published var userId: String?
    @Published var status: ConnectionStatus = .unknown
    @Published var pairing: PairingMode = .unknown
    @Published var pairingHint: String?
    @Published var isConnecting = false
    @Published var connectError: String?
    @Published var isLoaded = false
    @Published var isBootstrapping = false
    /// Base64 PNG QR code payload from the server (nil when not provided, falls back to /api/max-qr/{userId}).
    @Published var qrPng: String?

    // MARK: - Dependencies

    private let api = APIService.shared
    private var statusPollTask: Task<Void, Never>?
    private var initialCheckDone = false

    // MARK: - Init

    init() {
        if let id = UserStore.userId, !id.isEmpty {
            userId = id
            // Fast path: if we last knew the account was active, route straight to the
            // Connected screen immediately instead of blocking on a network round-trip.
            // A background refresh still runs to catch any server-side changes.
            if UserStore.cachedStatus == ConnectionStatus.active.rawValue {
                status = .active
                pairing = .active
                route = .connected
                isLoaded = true
            } else {
                route = .qr
            }
            Task { await resolveInitialRoute() }
        } else {
            isLoaded = true
        }
    }

    /// Determine initial route from saved userId.
    private func resolveInitialRoute() async {
        guard let id = userId else {
            isLoaded = true
            return
        }
        let wasActiveFromCache = status == .active
        isBootstrapping = true
        do {
            let resp = try await api.status(userId: id)
            applyStatusPayload(resp)
            reroute()
        } catch {
            // Network hiccup on launch: don't kick an already-active user back to QR —
            // keep showing Connected from cache and let a later poll correct it.
            if !wasActiveFromCache {
                status = .unknown
                pairing = .unknown
                reroute()
            }
        }
        if route == .connected {
            CallManager.shared.syncVoipToken()
        }
        initialCheckDone = true
        isBootstrapping = false
        isLoaded = true
    }

    // MARK: - Check status

    func checkStatus() async {
        guard let id = userId else { return }
        do {
            let resp = try await api.status(userId: id)
            applyStatusPayload(resp)
        } catch {
            // Keep current state on network error
        }
        reroute()
    }

    /// Poll status periodically at the given interval until cancelled.
    func startStatusPolling(interval: TimeInterval, stopWhenConnected: Bool = true) {
        guard let id = userId else { return }
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                if let resp = try? await api.status(userId: id) {
                    applyStatus(resp)
                    reroute()
                    if stopWhenConnected && route == .connected { break }
                }
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopStatusPolling() {
        statusPollTask?.cancel()
        statusPollTask = nil
    }

    // MARK: - Parse status response

    private func applyStatus(_ resp: StatusResponse) {
        let wasActive = status == .active
        status = ConnectionStatus(rawValue: resp.status ?? "unknown") ?? .unknown
        if let p = resp.pairing {
            pairing = PairingMode(rawValue: p) ?? .unknown
        }
        pairingHint = resp.hint
        qrPng = resp.qrPng

        // Keep the Home Screen widget's "recent messages" feed in sync right after connecting.
        if status == .active {
            if !wasActive, let id = userId {
                Task { await WidgetFeedManager.refresh(userId: id) }
            }
        } else if wasActive {
            WidgetFeedStore.markDisconnected()
        }
    }

    /// Applies a status response AND persists the raw status string to disk so the next
    /// cold launch can route immediately without waiting on the network (see init()).
    private func applyStatusPayload(_ resp: StatusResponse) {
        applyStatus(resp)
        UserStore.cachedStatus = resp.status
    }

    /// Compute the screen from current state.
    private func reroute() {
        if userId == nil {
            route = .welcome
        } else if status == .active {
            route = .connected
        } else {
            route = .qr
        }
    }

    // MARK: - Connect

    func start() async {
        guard !isConnecting else { return }
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        do {
            let resp = try await api.connect()
            UserStore.userId = resp.userId
            UserStore.cachedStatus = ConnectionStatus.pending.rawValue
            userId = resp.userId
            status = .pending
            pairing = .qr
            pairingHint = nil
            route = .qr
            // Trigger token sync loops now that userId is available
            PushManager.shared.kickRetryIfNeeded()
            CallManager.shared.syncVoipToken()
        } catch {
            connectError = "Сервер временно недоступен. Проверьте подключение к интернету и попробуйте снова."
        }
    }

    // MARK: - 2FA

    func submit2FA(password: String) async -> String? {
        guard let id = userId else { return nil }
        do {
            let resp = try await api.submit2FA(userId: id, password: password)
            if resp.ok == true {
                pairingHint = nil
                // After successful 2FA, status may flip — poll once
                await checkStatus()
                return nil
            } else {
                return resp.error ?? "Неверный пароль. Попробуйте снова."
            }
        } catch {
            return "Неверный пароль. Попробуйте снова."
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        statusPollTask?.cancel()
        if let id = userId {
            await api.disconnect(userId: id)
        }
        UserStore.clear()
        userId = nil
        status = .unknown
        pairing = .unknown
        pairingHint = nil
        route = .welcome
        WidgetFeedStore.markDisconnected()
    }

    /// Called by deep link: mkspush://pair?user_id=XXX
    func setUserIdFromDeepLink(_ id: String) {
        UserStore.userId = id
        UserStore.cachedStatus = nil
        userId = id
        status = .unknown
        pairing = .unknown
        pairingHint = nil
        route = .qr
        Task {
            await checkStatus()
            CallManager.shared.syncVoipToken()
        }
    }

    // MARK: - Reconnect (session expired)

    /// Reconnect after session expiry (404 on QR).
    /// Clears UserStore, gets a new userId via POST /api/connect, and returns to QR.
    func reconnect() async {
        statusPollTask?.cancel()
        UserStore.clear()
        do {
            let resp = try await api.connect()
            UserStore.userId = resp.userId
            UserStore.cachedStatus = ConnectionStatus.pending.rawValue
            userId = resp.userId
            status = .pending
            pairing = .qr
            pairingHint = nil
            route = .qr
            PushManager.shared.kickRetryIfNeeded()
            CallManager.shared.syncVoipToken()
        } catch {
            // Fallback to full disconnect on failure
            userId = nil
            status = .unknown
            pairing = .unknown
            pairingHint = nil
            route = .welcome
        }
    }
}
