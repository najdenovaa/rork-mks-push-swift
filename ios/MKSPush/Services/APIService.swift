//
//  APIService.swift
//  MKSPush
//

import Foundation

/// Networking layer for the MKS Push backend. All methods are nonisolated and safe to call from any context.
nonisolated struct APIService: Sendable {
    static let shared = APIService()

    let baseURL = URL(string: "https://mkspush.ru")!

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// URL for the QR PNG image. Appends a cache-busting timestamp.
    func qrURL(userId: String) -> URL {
        var url = baseURL.appendingPathComponent("api/max-qr/\(userId)")
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970)))]
            if let u = comps.url { url = u }
        }
        return url
    }

    /// POST /api/connect — registers a new device and returns its userId.
    func connect() async throws -> ConnectResponse {
        let url = baseURL.appendingPathComponent("api/connect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["push_token": "pending"])
        let (data, _) = try await session.data(for: request)
        return try Self.decoder.decode(ConnectResponse.self, from: data)
    }

    /// GET /api/status/{userId}
    func status(userId: String) async throws -> ConnectionStatus {
        let url = baseURL.appendingPathComponent("api/status/\(userId)")
        let (data, _) = try await session.data(from: url)
        let response = try Self.decoder.decode(StatusResponse.self, from: data)
        return ConnectionStatus(from: response.status)
    }

    /// GET /api/events/{userId}
    func events(userId: String) async throws -> [AppEvent] {
        let url = baseURL.appendingPathComponent("api/events/\(userId)")
        let (data, _) = try await session.data(from: url)
        let response = try Self.decoder.decode(EventsResponse.self, from: data)
        return response.events ?? []
    }

    /// Downloads the QR PNG image data.
    func qrImageData(userId: String) async throws -> Data {
        let (data, response) = try await session.data(from: qrURL(userId: userId))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    /// POST /api/token/{userId} — sends the standard APNs device token.
    func sendAPNsToken(userId: String, token: String) async {
        await post(path: "api/token/\(userId)", body: ["token": token, "type": "apns"])
    }

    /// POST /api/voip-token/{userId} — sends the PushKit VoIP token.
    func sendVoipToken(userId: String, token: String) async {
        await post(path: "api/voip-token/\(userId)", body: ["voip_token": token])
    }

    /// POST /api/call-declined/{userId}
    func callDeclined(userId: String, callUUID: String) async {
        await post(path: "api/call-declined/\(userId)", body: ["call_uuid": callUUID])
    }

    /// POST /api/disconnect/{userId}
    func disconnect(userId: String) async {
        await post(path: "api/disconnect/\(userId)", body: [:])
    }

    private func post(path: String, body: [String: String]) async {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            _ = try await session.data(for: request)
        } catch {
            print("[APIService] POST \(path) failed: \(error.localizedDescription)")
        }
    }
}
