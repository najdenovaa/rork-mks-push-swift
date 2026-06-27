//
//  Theme.swift
//  MKSPush
//
//  Color palette matching React Native build 23.
//

import Combine
import SwiftUI

/// App-wide design constants and reusable views.
enum Theme {
    // Brand (from RN const Brand)
    static let primary = Color(red: 22/255, green: 163/255, blue: 74/255)      // #16A34A
    static let green    = Color(red: 34/255, green: 197/255, blue: 94/255)     // #22C55E
    static let red      = Color(red: 239/255, green: 68/255, blue: 68/255)     // #EF4444
    static let amber    = Color(red: 245/255, green: 158/255, blue: 11/255)    // #F59E0B
    static let gray     = Color(red: 142/255, green: 142/255, blue: 147/255)   // #8E8E93

    // Light palette
    static let bgLight        = Color(red: 220/255, green: 252/255, blue: 231/255) // #DCFCE7
    static let surfaceLight   = Color.white
    static let cardLight      = Color(red: 245/255, green: 245/255, blue: 247/255) // #F5F5F7
    static let textLight      = Color(red: 10/255, green: 31/255, blue: 18/255)     // #0A1F12
    static let textSecLight   = Color(red: 90/255, green: 125/255, blue: 101/255)   // #5A7D65
    static let textFaintLight = Color(red: 143/255, green: 170/255, blue: 151/255)  // #8FAA97
    static let borderLight    = Color(red: 209/255, green: 232/255, blue: 214/255)  // #D1E8D6

    // Dark palette
    static let bgDark         = Color(red: 7/255, green: 26/255, blue: 16/255)      // #071A10
    static let surfaceDark    = Color(red: 15/255, green: 42/255, blue: 26/255)     // #0F2A1A
    static let cardDark       = Color(red: 28/255, green: 28/255, blue: 28/255)     // #1C1C1E
    static let textDark       = Color(red: 243/255, green: 255/255, blue: 245/255)  // #F3FFF5
    static let textSecDark    = Color(red: 183/255, green: 217/255, blue: 193/255)  // #B7D9C1
    static let textFaintDark  = Color(red: 77/255, green: 122/255, blue: 94/255)    // #4D7A5E
    static let borderDark     = Color(red: 29/255, green: 75/255, blue: 46/255)     // #1D4B2E

    // Server URLs
    static let serverURL      = "https://mkspush.ru"
    static let privacyURL     = "https://mkspush.ru/privacy"
    static let termsURL       = "https://mkspush.ru/terms"
    static let supportURL     = "https://mkspush.ru/support"
    static let linkedAppURL   = "https://mkspush.ru/go"
    static let linkedAppScheme = "max"

    static let maxContentWidth: CGFloat = 500
}

// MARK: - Environment colour resolver

struct ThemeColors {
    let bg: Color
    let surface: Color
    let card: Color
    let text: Color
    let textSecondary: Color
    let textFaint: Color
    let border: Color
    let green: Color
    let red: Color
    let amber: Color
    let onAccent: Color
}

extension ThemeColors {
    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            bg = Theme.bgDark
            surface = Theme.surfaceDark
            card = Theme.cardDark
            text = Theme.textDark
            textSecondary = Theme.textSecDark
            textFaint = Theme.textFaintDark
            border = Theme.borderDark
            green = Theme.green
            red = Theme.red
            amber = Theme.amber
            onAccent = .white
        default:
            bg = Theme.bgLight
            surface = Theme.surfaceLight
            card = Theme.cardLight
            text = Theme.textLight
            textSecondary = Theme.textSecLight
            textFaint = Theme.textFaintLight
            border = Theme.borderLight
            green = Theme.green
            red = Theme.red
            amber = Theme.amber
            onAccent = .white
        }
    }
}

private struct ThemeColorsKey: EnvironmentKey {
    static let defaultValue = ThemeColors(colorScheme: .light)
}

extension EnvironmentValues {
    var themeColors: ThemeColors {
        get { self[ThemeColorsKey.self] }
        set { self[ThemeColorsKey.self] = newValue }
    }
}

// MARK: - Primary button

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.green
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(color.opacity(isEnabled ? 1 : 0.5))
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Secondary outline button

struct SecondaryButtonStyle: ButtonStyle {
    var color: Color = Theme.primary

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

// MARK: - Animated dots

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
