//
//  AppModels.swift
//  MKSPush
//

import Foundation

/// Connection status reported by the server.
nonisolated enum ConnectionStatus: String, Codable, Sendable {
    case pending
    case active
    case unknown

    init(from rawValue: String?) {
        switch rawValue?.lowercased() {
        case "active", "connected": self = .active
        case "pending", "waiting": self = .pending
        default: self = .unknown
        }
    }
}

/// Response from POST /api/connect
nonisolated struct ConnectResponse: Codable, Sendable {
    let ok: Bool
    let userId: String
    let status: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case userId = "user_id"
        case status
    }
}

/// Response from GET /api/status/{userId}
nonisolated struct StatusResponse: Codable, Sendable {
    let ok: Bool?
    let status: String?
}

/// Response from GET /api/events/{userId}
nonisolated struct EventsResponse: Codable, Sendable {
    let ok: Bool?
    let events: [AppEvent]?
}

/// A single event in the feed.
nonisolated struct AppEvent: Codable, Sendable, Identifiable {
    let title: String
    let body: String
    let time: String

    var id: String { "\(title)|\(body)|\(time)" }

    /// Formats the UTC timestamp into a local HH:mm string. Falls back to the raw value.
    var displayTime: String {
        AppEvent.timeFormatter.formatted(from: time)
    }

    private static let timeFormatter = EventTimeFormatter()
}

/// Parses common UTC timestamp formats and renders a local HH:mm string.
nonisolated struct EventTimeFormatter: Sendable {
    func formatted(from raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) {
            return Self.output.string(from: date)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return Self.output.string(from: date)
        }

        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss"] {
            fallback.dateFormat = format
            if let date = fallback.date(from: raw) {
                return Self.output.string(from: date)
            }
        }
        return raw
    }

    private static let output: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()
}
