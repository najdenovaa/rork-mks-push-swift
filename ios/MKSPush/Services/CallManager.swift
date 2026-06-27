//
//  CallManager.swift
//  MKSPush
//
//  Handles VoIP pushes (PushKit) and the native incoming call UI (CallKit).
//

import Foundation
import PushKit
import CallKit
import AVFoundation
import UIKit

/// Parsed incoming VoIP call payload.
nonisolated struct IncomingCall: Sendable {
    let callerName: String
    let callerId: String?
    let conversationId: String?
    let callUUID: UUID
    let isVideo: Bool
}

/// Central coordinator for PushKit VoIP registration and CallKit call reporting.
final class CallManager: NSObject {
    static let shared = CallManager()

    private let provider: CXProvider
    private let callController = CXCallController()
    private var voipRegistry: PKPushRegistry?

    /// Tracks the call UUID -> raw UUID string from payload (for server callbacks).
    private var activeCalls: [UUID: IncomingCall] = [:]

    private override init() {
        let config = CXProviderConfiguration(localizedName: "MKS Push")
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.generic]
        if let icon = UIImage(named: "AppIcon") ?? UIImage(named: "icon") {
            config.iconTemplateImageData = icon.pngData()
        }
        config.ringtoneSound = nil // use system default ringtone
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// Registers for VoIP pushes. Call once at launch.
    func registerForVoIPPushes() {
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        voipRegistry = registry
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

    /// Opens the MAX app (server redirects appropriately).
    private func openMaxApp() {
        guard let url = URL(string: "https://mkspush.ru/go") else { return }
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
        print("[CallManager] VoIP token updated")
        guard let userId = UserStore.userId else { return }
        Task { await APIService.shared.sendVoipToken(userId: userId, token: token) }
    }

    nonisolated func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        print("[CallManager] VoIP token invalidated")
    }

    /// Apple REQUIRES every VoIP push to report a call to CallKit before the completion handler fires.
    nonisolated func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        let dict = payload.dictionaryPayload
        let callerName = (dict["caller_name"] as? String) ?? "Входящий вызов"
        let callerId = dict["caller_id"] as? String
        let conversationId = dict["conversation_id"] as? String
        let isVideo = (dict["is_video"] as? Bool) ?? ((dict["is_video"] as? NSNumber)?.boolValue ?? false)
        let uuid = (dict["call_uuid"] as? String).flatMap { UUID(uuidString: $0) } ?? UUID()

        let call = IncomingCall(
            callerName: callerName,
            callerId: callerId,
            conversationId: conversationId,
            callUUID: uuid,
            isVideo: isVideo
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
        Task { @MainActor in
            self.openMaxApp()
            action.fulfill()
            self.activeCalls[action.callUUID] = nil
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor in
            if let call = self.activeCalls[action.callUUID], let userId = UserStore.userId {
                await APIService.shared.callDeclined(userId: userId, callUUID: call.callUUID.uuidString)
            }
            action.fulfill()
            self.activeCalls[action.callUUID] = nil
        }
    }

    nonisolated func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("[CallManager] didActivate audio session error: \(error.localizedDescription)")
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
