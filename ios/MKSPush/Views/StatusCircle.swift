//
//  StatusCircle.swift
//  MKSPush
//
//  Large circular status indicator with animated pulse halo for "active".
//  Ported from React Native build 23 StatusCircle.tsx.
//

import SwiftUI

/// Animated status indicator — green circle with checkmark and pulsing halo when active.
struct StatusCircle: View {
    let status: ConnectionStatus

    private let size: CGFloat = 80

    var body: some View {
        ZStack {
            if status == .active {
                PulseHalo(color: Theme.green, size: size)
            }
            Circle()
                .strokeBorder(color, lineWidth: 3)
                .frame(width: size, height: size)
                .overlay {
                    if status == .active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Theme.green)
                    }
                }
        }
        .frame(width: size, height: size)
    }

    private var color: Color {
        switch status {
        case .active:  return Theme.green
        case .pending: return Theme.primary
        case .unknown: return Theme.gray
        }
    }
}

// MARK: - Pulse halo

private struct PulseHalo: View {
    let color: Color
    let size: CGFloat

    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(animating ? 0 : 0.35)
            .scaleEffect(animating ? 1.6 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                    animating = true
                }
            }
    }
}

#Preview {
    VStack(spacing: 40) {
        StatusCircle(status: .active)
        StatusCircle(status: .pending)
        StatusCircle(status: .unknown)
    }
    .padding()
    .background(Color(.systemBackground))
}
