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

    // MARK: - Dependencies

    private let api = APIService.shared
    private var statusPollTask: Task<Void, Never>?
    private var initialCheckDone = false

    // MARK: - Init

    init() {
        if let id = UserStore.userId, !id.isEmpty {
            userId = id
            route = .qr
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
        do {
            let resp = try await api.status(userId: id)
            applyStatus(resp)
        } catch {
            status = .unknown
            pairing = .unknown
        }
        reroute()
        initialCheckDone = true
        isLoaded = true
    }

    // MARK: - Check status

    func checkStatus() async {
        guard let id = userId else { return }
        do {
            let resp = try await api.status(userId: id)
            applyStatus(resp)
        } catch {
            // Keep current state on network error
        }
        reroute()
    }

    /// Poll status periodically at the given interval until cancelled.
    func startStatusPolling(interval: TimeInterval) {
        guard let id = userId else { return }
        statusPollTask?.cancel()
        statusPollTask = Task {
            while !Task.isCancelled {
                if let resp = try? await api.status(userId: id) {
                    applyStatus(resp)
                    reroute()
                    if route == .connected { break }
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
        status = ConnectionStatus(rawValue: resp.status ?? "unknown") ?? .unknown
        if let p = resp.pairing {
            pairing = PairingMode(rawValue: p) ?? .unknown
        }
        pairingHint = resp.hint
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
            userId = resp.userId
            status = .pending
            pairing = .qr
            pairingHint = nil
            route = .qr
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
    }

    /// Called by deep link: mkspush://pair?user_id=XXX
    func setUserIdFromDeepLink(_ id: String) {
        UserStore.userId = id
        userId = id
        status = .unknown
        pairing = .unknown
        pairingHint = nil
        route = .qr
        Task { await checkStatus() }
    }
}
