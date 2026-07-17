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
    /// Base64-encoded PNG QR code, served directly by the status endpoint.
    let qrPng: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case status
        case pairing
        case hint
        case qrPng = "qr_png"
    }
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

// MARK: - Events

/// GET /api/events/{userId}
nonisolated struct EventsResponse: Codable, Sendable {
    let ok: Bool?
    let events: [EventItem]?
}

nonisolated struct EventItem: Codable, Sendable, Identifiable {
    let title: String
    let body: String
    let time: String

    var id: String { "\(time)-\(title)" }
}

// MARK: - Call answer

/// POST /api/call-answered/{userId} → { ok, accept: { ok } }
nonisolated struct CallAnsweredResponse: Codable, Sendable {
    let ok: Bool?
    let accept: CallAnsweredAccept?
}

nonisolated struct CallAnsweredAccept: Codable, Sendable {
    let ok: Bool
}

// MARK: - Widget inbox feed

/// One row of the "recent Max messages" Home Screen widget feed.
nonisolated struct InboxFeedItem: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let chatId: String
    let chatType: String?
    let title: String
    let body: String
    let time: String

    enum CodingKeys: String, CodingKey {
        case id
        case chatId = "chat_id"
        case chatType = "chat_type"
        case title
        case body
        case time
    }
}

/// GET /api/inbox/{userId}?limit=5
nonisolated struct InboxResponse: Codable, Sendable {
    let ok: Bool?
    let items: [InboxFeedItem]?
    let unreadCount: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case items
        case unreadCount = "unread_count"
    }
}
