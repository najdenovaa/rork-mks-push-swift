//
//  StatusCircle.swift
//  MKSPush
//
//  Large circular status indicator with animated pulse halo for "active".
//  Pixel-parity with React Native StatusCircle.tsx.
//

import SwiftUI

/// Animated status indicator — filled circle with white checkmark and pulsing halo when active.
struct StatusCircle: View {
    let status: ConnectionStatus

    private let size: CGFloat = 80

    var body: some View {
        ZStack {
            if status == .active {
                PulseHalo(color: Theme.green, size: size)
            }
            Circle()
                .fill(fillColor)
                .frame(width: size, height: size)
                .overlay {
                    if status == .active {
                        Image(systemName: "checkmark")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .frame(width: size, height: size)
    }

    private var fillColor: Color {
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
            .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: animating)
            .onAppear { animating = true }
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
