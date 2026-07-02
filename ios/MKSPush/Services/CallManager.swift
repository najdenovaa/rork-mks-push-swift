//
//  CallManager.swift
//  MKSPush
//
//  Handles VoIP pushes (PushKit) and the native incoming call UI (CallKit).
//

import Foundation
import Combine
import PushKit
import CallKit
import AVFoundation
import UIKit
import UserNotifications

/// Parsed incoming VoIP call payload.
nonisolated struct IncomingCall: Sendable {
    let callerName: String
    let callerId: String?
    let conversationId: String?
    let callUUID: UUID
    let isVideo: Bool
    let vcp: String?
}

/// Central coordinator for PushKit VoIP registration and CallKit call reporting.
final class CallManager: NSObject, ObservableObject {
    static let shared = CallManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var voipRegistry: PKPushRegistry?
    private var voipRetryTask: Task<Void, Never>?
    private var storedVoipToken: String?
    private var delayedCheckTask: Task<Void, Never>?

    /// Debug status for ConnectedView footer: "waiting" / "len=64" / "sent" / "error"
    @Published var voipDebugStatus: String = "waiting"

    /// UIBackgroundModes from final Info.plist — "voip, remote-notification" or "NOT FOUND"
    @Published var backgroundModesDebugLine: String = "NOT FOUND"

    /// Tracks the call UUID -> raw UUID string from payload (for server callbacks).
    private var activeCalls: [UUID: IncomingCall] = [:]

    /// When set, the answered call is waiting for audio session to activate before we can end it cleanly.
    private var pendingEndAfterAnswer: UUID?

    private override init() {
        let config = CXProviderConfiguration(localizedName: "MKS Push")
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        if let icon = UIImage(named: "AppIcon") ?? UIImage(named: "icon") {
            config.iconTemplateImageData = icon.pngData()
        }
        config.ringtoneSound = nil
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)

        // Restore persisted VoIP token
        if let saved = UserDefaults.standard.string(forKey: "mkspush.voip_token"), !saved.isEmpty {
            storedVoipToken = saved
            voipDebugStatus = "len=\(saved.count)"
            print("[CallManager] restored persisted VoIP token len=\(saved.count) prefix=\(String(saved.prefix(8)))")
            // Trigger sync immediately if userId already available
            if UserStore.userId != nil {
                syncVoipToken()
            }
        } else {
            print("[CallManager] no persisted VoIP token on init")
        }

        // Read UIBackgroundModes from final Info.plist
        if let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
            backgroundModesDebugLine = modes.joined(separator: ", ")
        } else {
            backgroundModesDebugLine = "NOT FOUND"
        }
        print("[CallManager] backgroundModesDebugLine: \(backgroundModesDebugLine)")
    }

    // MARK: - Registration

    /// Registers for VoIP pushes. Call once at launch, and again on foreground if token still nil.
    func registerForVoIPPushes() {
        guard voipRegistry == nil else {
            print("[CallManager] registerForVoIPPushes skipped: registry exists")
            return
        }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        voipRegistry = registry
        print("[CallManager] PKPushRegistry created, desiredPushTypes=[.voIP]")
    }

    /// Re-register for VoIP pushes if we still have no token.
    /// Called from AppDelegate on launch AND from scenePhase .active handler.
    func reRegisterIfNeeded() {
        guard storedVoipToken == nil else {
            print("[CallManager] reRegisterIfNeeded skipped: already have token len=\(storedVoipToken!.count)")
            return
        }
        if voipRegistry != nil {
            print("[CallManager] reRegisterIfNeeded: registry exists, waiting for token")
            // Try to sync persisted token if available
            if let saved = UserDefaults.standard.string(forKey: "mkspush.voip_token"), !saved.isEmpty {
                storedVoipToken = saved
                syncVoipToken()
            }
            return
        }
        print("[CallManager] reRegisterIfNeeded: no stored token, re-registering")
        registerForVoIPPushes()
    }

    /// Schedule a 30-second delayed check from MainActor.
    func scheduleDelayedVoipCheck() {
        delayedCheckTask?.cancel()
        delayedCheckTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            if Task.isCancelled { return }
            if storedVoipToken == nil {
                let center = UNUserNotificationCenter.current()
                let settings = await center.notificationSettings()
                let isAuthorized = settings.authorizationStatus == .authorized
                print("[CallManager] VoIP token still nil 30s after launch, UNAuthorized=\(isAuthorized)")
                if voipDebugStatus == "waiting" {
                    voipDebugStatus = "waiting (30s)"
                }
                // Re-register as a final attempt
                registerForVoIPPushes()
            }
        }
    }

    // MARK: - VoIP token sync

    /// Triggers the retry loop for any stored VoIP token.
    func syncVoipToken() {
        guard let token = storedVoipToken else {
            print("[CallManager] syncVoipToken skipped: no stored token")
            return
        }
        startVoipRetryLoop(token: token)
    }

    private func startVoipRetryLoop(token: String) {
        voipRetryTask?.cancel()
        voipRetryTask = Task {
            while !Task.isCancelled {
                guard let userId = UserStore.userId else {
                    print("[CallManager] VoIP retry: no userId yet, sleeping 15s")
                    try? await Task.sleep(for: .seconds(15))
                    continue
                }
                do {
                    try await APIService.shared.sendVoipToken(userId: userId, token: token)
                    await MainActor.run { self.voipDebugStatus = "sent" }
                    print("[CallManager] VoIP token sent to server userId prefix=\(String(userId.prefix(6)))")
                    break
                } catch {
                    let nsError = error as NSError
                    let status = nsError.userInfo["status"] as? Int ?? -1
                    let body = nsError.userInfo["body"] as? String ?? ""
                    print("[CallManager] VoIP token sync failed (HTTP \(status), body: \(body)), retrying in 15s: \(error.localizedDescription)")
                    await MainActor.run { self.voipDebugStatus = "error" }
                }
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    /// Reports an incoming call to CallKit, showing the native full-screen UI.
    func reportIncomingCall(_ call: IncomingCall, completion: @escaping () -> Void) {
        activeCalls[call.callUUID] = call

        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: call.callerId ?? call.callerName)
        update.localizedCallerName = call.callerName
        update.hasVideo = call.isVideo
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        provider.reportNewIncomingCall(with: call.callUUID, update: update) { error in
            if let error {
                print("[CallManager] reportNewIncomingCall failed: \(error.localizedDescription)")
            }
            completion()
        }
    }

    /// Opens the MAX app via deep link with optional conversationId and vcp, falling back to website.
    private func openMaxApp(conversationId: String?, vcp: String?) {
        var comps = URLComponents(string: "max://call")
        var items: [URLQueryItem] = []
        if let conversationId { items.append(URLQueryItem(name: "conversationId", value: conversationId)) }
        if let vcp, !vcp.isEmpty { items.append(URLQueryItem(name: "vcp", value: vcp)) }
        comps?.queryItems = items.isEmpty ? nil : items
        let maxCallURL = comps?.url

        let candidates: [URL?] = [maxCallURL, URL(string: "max://"), URL(string: "https://max.ru/")]
        let urls = candidates.compactMap { $0 }
        guard let url = urls.first else { return }
        print("[CallManager] openMaxApp vcpLen=\(vcp?.count ?? 0) urlPrefix=\(url.absoluteString.prefix(80))")
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

// MARK: - PKPushRegistryDelegate

extension CallManager: PKPushRegistryDelegate {
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        let prefix = String(token.prefix(8))
        NSLog("[CallManager] VoIP token received len=%d prefix=%@", token.count, prefix)
        print("[CallManager] VoIP token received len=\(token.count) prefix=\(prefix)")

        Task { @MainActor in
            self.storedVoipToken = token
            self.voipDebugStatus = "len=\(token.count)"
            // Persist to UserDefaults so token survives app restarts
            UserDefaults.standard.set(token, forKey: "mkspush.voip_token")
            print("[CallManager] VoIP token persisted to UserDefaults")
            self.delayedCheckTask?.cancel()
            self.syncVoipToken()
        }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[CallManager] VoIP token invalidated for type: \(type.rawValue)")
        Task { @MainActor in
            self.storedVoipToken = nil
            self.voipDebugStatus = "waiting"
            UserDefaults.standard.removeObject(forKey: "mkspush.voip_token")
        }
    }

    /// Apple REQUIRES every VoIP push to report a call to CallKit before the completion handler fires.
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let callerName = (dict["caller_name"] as? String) ?? "Входящий вызов"
        let callerId = dict["caller_id"] as? String
        let conversationId = dict["conversation_id"] as? String
        let isVideo = (dict["is_video"] as? Bool) ?? ((dict["is_video"] as? NSNumber)?.boolValue ?? false)
        let vcp = dict["vcp"] as? String
        let uuid = (dict["call_uuid"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()

        let call = IncomingCall(
            callerName: callerName,
            callerId: callerId,
            conversationId: conversationId,
            callUUID: uuid,
            isVideo: isVideo,
            vcp: vcp
        )

        Task { @MainActor in
            self.reportIncomingCall(call, completion: completion)
        }
    }
}

// MARK: - CXProviderDelegate

extension CallManager: CXProviderDelegate {
    nonisolated func providerDidReset(_ provider: CXProvider) {
        Task { @MainActor in self.activeCalls.removeAll() }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        let callUUID = action.callUUID
        Task { @MainActor in
            let call = self.activeCalls[callUUID]
            var didAccept = false
            if let call, let userId = UserStore.userId {
                didAccept = await APIService.shared.callAnswered(
                    userId: userId,
                    callUUID: call.callUUID.uuidString,
                    conversationId: call.conversationId
                )
            }
            action.fulfill()
            if didAccept {
                self.openMaxApp(conversationId: call?.conversationId, vcp: call?.vcp)
                // Don't end the call yet — wait for audio session to activate first.
                // CXEndCallAction before activation leaves the "Подключаюсь" UI stuck.
                self.pendingEndAfterAnswer = callUUID
                print("[CallManager] answer fulfilled, pendingEndAfterAnswer=\(callUUID.uuidString)")
                // Fire-and-forget: after 2 seconds, retry join with vcp on server
                let userId = UserStore.userId
                let conversationId = call?.conversationId
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if let userId {
                        await APIService.shared.callJoinRetry(userId: userId, conversationId: conversationId)
                    }
                }
                // Fallback: if audio session never activates, close after 800ms anyway.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    self.finishAnsweredCallIfPending(callUUID)
                }
            } else {
                // Server rejected or no call info — end immediately with failed reason
                self.activeCalls[callUUID] = nil
                self.provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
                print("[CallManager] answer rejected, reported endedAt reason=.failed for \(callUUID.uuidString)")
            }
        }
    }

    /// Reports the call as ended via provider.reportCall and cleans up bookkeeping.
    private func finishAnsweredCallIfPending(_ callUUID: UUID) {
        guard pendingEndAfterAnswer == callUUID else { return }
        pendingEndAfterAnswer = nil
        activeCalls[callUUID] = nil
        provider.reportCall(with: callUUID, endedAt: Date(), reason: .answeredElsewhere)
        print("[CallManager] finishAnsweredCallIfPending: reported endedAt for \(callUUID.uuidString)")
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            if let userId = UserStore.userId {
                let call = self.activeCalls[action.callUUID]
                let callUUID = call?.callUUID.uuidString ?? action.callUUID.uuidString
                let conversationId = call?.conversationId
                await APIService.shared.callDeclined(userId: userId, callUUID: callUUID, conversationId: conversationId)
            }
            self.pendingEndAfterAnswer = nil
            action.fulfill()
            self.activeCalls[action.callUUID] = nil
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        // We don't need a real audio session — just deactivate immediately
        // so the system doesn't show the "connecting" CallKit UI.
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CallManager] didActivate deactivate error: \(error.localizedDescription)")
        }
        // If we were waiting for activation to end the answered call, do it now.
        Task { @MainActor in
            if let callUUID = self.pendingEndAfterAnswer {
                self.finishAnsweredCallIfPending(callUUID)
            }
        }
    }

    nonisolated func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[CallManager] didDeactivate audio session error: \(error.localizedDescription)")
        }
    }
}
