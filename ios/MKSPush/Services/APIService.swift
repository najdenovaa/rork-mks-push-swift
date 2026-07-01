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

    // MARK: - Call

    func callAnswered(userId: String, callUUID: String, conversationId: String?) async {
        var body: [String: String] = ["call_uuid": callUUID]
        if let conversationId, !conversationId.isEmpty {
            body["conversation_id"] = conversationId
        }
        await firePost(path: "api/call-answered/\(userId)", body: body)
    }

    func callDeclined(userId: String, callUUID: String) async {
        await firePost(path: "api/call-declined/\(userId)", body: ["call_uuid": callUUID])
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
