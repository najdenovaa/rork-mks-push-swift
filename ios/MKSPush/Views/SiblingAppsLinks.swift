//
//  SiblingAppsLinks.swift
//  MKSPush
//
//  "Мои проекты" section — links to sibling apps on the App Store.
//  Ported from React Native build 23 SiblingAppsLinks.tsx.
//

import SwiftUI

/// App Store links to sibling projects.
struct SiblingAppsLinks: View {
    @Environment(\.themeColors) private var c

    var body: some View {
        VStack(spacing: 12) {
            Text("Мои проекты")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)

            HStack(spacing: 32) {
                appItem(
                    name: "Мусорка",
                    url: "https://apps.apple.com/us/app/мусорка/id6762083275",
                    letter: "М"
                )
                appItem(
                    name: "Скидос",
                    url: "https://apps.apple.com/us/app/скидос/id6775503298",
                    letter: "С"
                )
            }
            .padding(.vertical, 8)
        }
    }

    private func appItem(name: String, url: String, letter: String) -> some View {
        Button {
            if let u = URL(string: url) {
                UIApplication.shared.open(u)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.white)
                        .frame(width: 64, height: 64)
                    Text(letter)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 34/255, green: 197/255, blue: 94/255))
                }
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SiblingAppsLinks()
        .padding()
        .background(Color(.systemBackground))
}
