//
//  UserStore.swift
//  MKSPush
//

import Foundation

nonisolated enum UserStore {
    private static let key = "user_id"
    private static let statusKey = "app_status"

    static var userId: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }

    /// Last known connection status ("active" / "pending" / "unknown"), cached so the app
    /// can route straight to the correct screen on launch without waiting for the network.
    static var cachedStatus: String? {
        get { UserDefaults.standard.string(forKey: statusKey) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: statusKey)
            } else {
                UserDefaults.standard.removeObject(forKey: statusKey)
            }
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: statusKey)
    }
}
