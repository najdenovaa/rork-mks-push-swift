//
//  UserStore.swift
//  MKSPush
//

import Foundation

/// Lightweight persistence for the device's userId. Safe to read from any context.
nonisolated enum UserStore {
    private static let key = "mks_user_id"

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

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
