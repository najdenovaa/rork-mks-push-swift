//
//  AppModels.swift
//  MKSPush
//

import Foundation

// MARK: - Connection status

nonisolated enum ConnectionStatus: String, Codable, Sendable, Equatable {
    case unknown
    case pending
    case active
}

// MARK: - Pairing mode

nonisolated enum PairingMode: String, Codable, Sendable, Equatable {
    case qr
    case needs2FA = "needs_2fa"
    case active
    case unknown
}

// MARK: - API responses

/// POST /api/connect
nonisolated struct ConnectResponse: Codable, Sendable {
    let ok: Bool
    let userId: String

    enum CodingKeys: String, CodingKey {
        case ok
        case userId = "user_id"
    }
}

/// GET /api/status/{userId}
nonisolated struct StatusResponse: Codable, Sendable {
    let ok: Bool?
    let status: String?
    let pairing: String?
    let hint: String?
}

/// POST /api/2fa/{userId}
nonisolated struct TwoFAResponse: Codable, Sendable {
    let ok: Bool?
    let error: String?
}

/// GET /api/open-target/{userId}
nonisolated struct OpenTargetResponse: Codable, Sendable {
    let ok: Bool?
    let url: String?
}

/// POST /api/badge/{userId}/reset
nonisolated struct BadgeResetResponse: Codable, Sendable {
    let ok: Bool?
}
