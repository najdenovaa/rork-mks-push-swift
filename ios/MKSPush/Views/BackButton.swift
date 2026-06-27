//
//  BackButton.swift
//  MKSPush
//
//  Ported from React Native build 23 BackButton.tsx.
//

import SwiftUI

/// Styled back navigation button — "← Назад".
struct BackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text("←")
                    .font(.system(size: 24, weight: .semibold))
                Text("Назад")
                    .font(.system(size: 18, weight: .semibold))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}

#Preview {
    BackButton {}
}
