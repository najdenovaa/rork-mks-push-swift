//
//  APIService.swift
//  MKSPush
//
//  Networking layer matching React Native build 23 endpoints.
//

import Foundation

nonisolated struct APIService: Sendable {
    static let shared = APIService()

    let baseURL = URL(string: Theme.serverURL)!

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

    // MARK: - QR

    func qrURL(userId: String) -> URL {
        var url = baseURL.appendingPathComponent("api/max-qr/\(userId)")
        if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
            if let u = comps.url { url = u }
        }
        return url
    }

    func qrImageData(userId: String) async throws -> Data {
        let (data, response) = try await session.data(from: qrURL(userId: userId))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    // MARK: - Connect / Status / 2FA

    func connect() async throws -> ConnectResponse {
        let url = baseURL.appendingPathComponent("api/connect")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["push_token": "pending"])
        let (data, _) = try await session.data(for: request)
        return try Self.decoder.decode(ConnectResponse.self, from: data)
    }

    func status(userId: String) async throws -> StatusResponse {
        let url = baseURL.appendingPathComponent("api/status/\(userId)")
        let (data, _) = try await session.data(from: url)
        return try Self.decoder.decode(StatusResponse.self, from: data)
    }

    func submit2FA(userId: String, password: String) async throws -> TwoFAResponse {
        let url = baseURL.appendingPathComponent("api/2fa/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 409 {
            let body = try? Self.decoder.decode(TwoFAResponse.self, from: data)
            return TwoFAResponse(ok: false, error: body?.error ?? "Неверный пароль. Попробуйте снова.")
        }
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(TwoFAResponse.self, from: data)
    }

    // MARK: - Reply (inline notification reply)

    func sendReply(userId: String, chatId: String, text: String) async throws {
        let url = baseURL.appendingPathComponent("api/reply/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: ["chat_id": chatId, "text": text])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw URLError(.badServerResponse, userInfo: ["body": body, "status": http.statusCode])
        }
    }

    // MARK: - Tokens

    func sendAPNsToken(userId: String, token: String) async throws {
        let url = baseURL.appendingPathComponent("api/token/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token, "type": "apns"])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw URLError(.badServerResponse, userInfo: ["body": body, "status": http.statusCode])
        }
    }

    func sendVoipToken(userId: String, token: String) async throws {
        let url = baseURL.appendingPathComponent("api/voip-token/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["voip_token": token])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw URLError(.badServerResponse, userInfo: ["body": body, "status": http.statusCode])
        }
    }

    /// POST /api/typing-token/{userId} — ActivityKit push-to-start token for the
    /// typing Live Activity (iOS 17.2+), so the server can start it via APNs.
    func sendTypingActivityToken(userId: String, token: String) async throws {
        let url = baseURL.appendingPathComponent("api/typing-token/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": token])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw URLError(.badServerResponse, userInfo: ["body": body, "status": http.statusCode])
        }
    }

    // MARK: - Call

    func callAnswered(userId: String, callUUID: String, conversationId: String?) async -> Bool {
        var body: [String: String] = ["call_uuid": callUUID]
        if let conversationId, !conversationId.isEmpty {
            body["conversation_id"] = conversationId
        }
        let url = baseURL.appendingPathComponent("api/call-answered/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                let resp = try Self.decoder.decode(CallAnsweredResponse.self, from: data)
                return resp.accept?.ok ?? false
            }
        } catch {
            print("[APIService] callAnswered failed: \(error.localizedDescription)")
        }
        return false
    }

    func callDeclined(userId: String, callUUID: String, conversationId: String?) async {
        var body: [String: String] = ["call_uuid": callUUID]
        if let conversationId, !conversationId.isEmpty {
            body["conversation_id"] = conversationId
        }
        await firePost(path: "api/call-declined/\(userId)", body: body)
    }

    func callJoinRetry(userId: String, conversationId: String?) async {
        var body: [String: String] = [:]
        if let conversationId, !conversationId.isEmpty {
            body["conversation_id"] = conversationId
        }
        await firePost(path: "api/call-join-retry/\(userId)", body: body)
    }

    // MARK: - Disconnect

    func disconnect(userId: String) async {
        await firePost(path: "api/disconnect/\(userId)", body: [:])
    }

    // MARK: - Badge

    func resetBadge(userId: String) async {
        await firePost(path: "api/badge/\(userId)/reset", body: [:])
    }

    // MARK: - Open target

    func openTarget(userId: String) async throws -> String? {
        let url = baseURL.appendingPathComponent("api/open-target/\(userId)")
        let (data, _) = try await session.data(from: url)
        let resp = try Self.decoder.decode(OpenTargetResponse.self, from: data)
        return resp.url
    }

    // MARK: - Widget inbox feed

    /// GET /api/inbox/{userId}?limit={limit} — recent Max messages for the Home Screen widget.
    func fetchInbox(userId: String, limit: Int) async throws -> [InboxFeedItem] {
        try await fetchInboxResponse(userId: userId, limit: limit).items ?? []
    }

    /// Same endpoint as `fetchInbox`, but returns the full response including `unread_count`.
    func fetchInboxResponse(userId: String, limit: Int) async throws -> InboxResponse {
        let url = baseURL.appendingPathComponent("api/inbox/\(userId)")
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let finalURL = comps.url else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: finalURL)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try Self.decoder.decode(InboxResponse.self, from: data)
    }

    // MARK: - Events

    func fetchEvents(userId: String) async throws -> [EventItem] {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8
        config.waitsForConnectivity = false
        let s = URLSession(configuration: config)
        let url = baseURL.appendingPathComponent("api/events/\(userId)")
        let (data, response) = try await s.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw URLError(.badServerResponse, userInfo: ["status": 404])
        }
        let resp = try Self.decoder.decode(EventsResponse.self, from: data)
        return resp.events ?? []
    }

    // MARK: - Helpers

    private func firePost(path: String, body: [String: String]) async {
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
