//
//  UserStore.swift
//  MKSPush
//

import Foundation

nonisolated enum UserStore {
    private static let key = "user_id"

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
