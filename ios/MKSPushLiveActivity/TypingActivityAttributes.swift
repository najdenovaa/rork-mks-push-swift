//
//  TypingActivityAttributes.swift
//  MKSPushLiveActivity
//
//  KEEP IN SYNC with MKSPush/Models/TypingActivityAttributes.swift.
//  ActivityKit matches the host app's activity to this renderer by the type
//  name and Codable layout, so both copies must stay identical.
//

import ActivityKit
import Foundation

nonisolated struct TypingActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var senderName: String
    }

    var chatId: String
    var senderId: String
}
