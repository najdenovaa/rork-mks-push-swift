//
//  TypingActivityAttributes.swift
//  MKSPush
//
//  KEEP IN SYNC with MKSPushLiveActivity/TypingActivityAttributes.swift.
//  ActivityKit matches the app's activity to the extension's renderer by the
//  type name and Codable layout, so both copies must stay identical.
//

import ActivityKit
import Foundation

@available(iOS 16.1, *)
nonisolated struct TypingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var senderName: String
    }

    var chatId: String
    var senderId: String
}
