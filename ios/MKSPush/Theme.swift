//
//  Theme.swift
//  MKSPush
//

import SwiftUI
import Combine

/// App color palette and reusable style helpers.
enum Theme {
    static let green = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)   // #34C759
    static let greenDeep = Color(red: 40 / 255, green: 167 / 255, blue: 69 / 255) // #28A745
    static let blue = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)     // #007AFF
    static let red = Color(red: 1, green: 59 / 255, blue: 48 / 255)              // #FF3B30
}

/// A large, prominent rounded button used for primary actions.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.green

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(
                LinearGradient(
                    colors: [color, color.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(.rect(cornerRadius: 16))
            .shadow(color: color.opacity(0.35), radius: configuration.isPressed ? 4 : 12, y: configuration.isPressed ? 2 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// A secondary, tinted-capsule button.
struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(color.opacity(0.12))
            .clipShape(.rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Animated three-dot "waiting" indicator.
struct AnimatedDots: View {
    var color: Color = .secondary
    @State private var phase = 0

    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .opacity(phase == index ? 1 : 0.3)
                    .scaleEffect(phase == index ? 1.2 : 1)
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phase = (phase + 1) % 3
            }
        }
    }
}
