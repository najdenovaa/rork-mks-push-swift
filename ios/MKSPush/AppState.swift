//
//  AppState.swift
//  MKSPush
//

import Foundation
import Combine

/// The three top-level screens of the app.
nonisolated enum AppRoute: Equatable {
    case welcome
    case qr
    case connected
}

/// Drives navigation between Welcome / QR / Connected based on server status.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var route: AppRoute = .welcome
    @Published private(set) var userId: String?
    @Published private(set) var isConnecting = false
    @Published var connectError: String?

    private let api = APIService.shared
    private var statusPollTask: Task<Void, Never>?

    init() {
        if let id = UserStore.userId, !id.isEmpty {
            userId = id
            // We have a saved user — verify status to decide which screen to show.
            route = .qr
            Task { await self.resolveInitialRoute() }
        }
    }

    /// On launch with a saved user, check status once and route accordingly.
    private func resolveInitialRoute() async {
        guard let id = userId else { return }
        if let status = try? await api.status(userId: id), status == .active {
            route = .connected
        } else {
            route = .qr
        }
    }

    /// "Начать" tapped — register the device and move to the QR screen.
    func start() async {
        guard !isConnecting else { return }
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        do {
            let response = try await api.connect()
            UserStore.userId = response.userId
            userId = response.userId
            route = .qr
        } catch {
            connectError = "Не удалось подключиться. Попробуйте ещё раз."
            print("[AppState] connect failed: \(error.localizedDescription)")
        }
    }

    /// Called by the QR screen when the server reports an active connection.
    func markConnected() {
        route = .connected
    }

    /// Disconnect: notify server, clear storage, return to Welcome.
    func disconnect() async {
        statusPollTask?.cancel()
        if let id = userId {
            await api.disconnect(userId: id)
        }
        UserStore.clear()
        userId = nil
        route = .welcome
    }
}
