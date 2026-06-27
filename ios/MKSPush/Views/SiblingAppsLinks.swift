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
            Text("My Projects")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)

            HStack(spacing: 32) {
                appItem(
                    name: "Musorka",
                    url: "https://apps.apple.com/us/app/мусорка/id6762083275",
                    letter: "M"
                )
                appItem(
                    name: "Skidos",
                    url: "https://apps.apple.com/us/app/скидос/id6775503298",
                    letter: "C"
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
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white)
                    .frame(width: 64, height: 64)
                    .overlay {
                        Text(letter)
                            .font(.title.bold())
                            .foregroundStyle(Theme.green)
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
