//
//  WelcomeView.swift
//  MKSPush
//
//  Welcome screen when not connected.
//  Pixel-parity with React Native WelcomeScreen.tsx.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            if appState.isConnecting {
                loadingState
            } else {
                bodyContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg)
    }

    // MARK: - Body (with footer)

    private var bodyContent: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            bodySection
                .frame(maxWidth: Theme.maxContentWidth)

            Spacer()

            // Footer
            VStack(spacing: 12) {
                SiblingAppsLinks()

                Text("Приложение не читает ваши сообщения. Только доставка уведомлений.")
                    .font(.system(size: 16))
                    .foregroundStyle(c.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                legalLinks
                    .padding(.bottom, 4)
            }
            .padding(.bottom, 32)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Body

    private var bodySection: some View {
        VStack(spacing: 0) {
            if appState.isConnecting {
                loadingState
            } else {
                contentState
            }
        }
    }

    // MARK: - Loading state

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Подключаем...")
                .font(.system(size: 20))
                .foregroundStyle(c.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content state

    private var contentState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Title
            Text("MKS Push")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(c.text)

            // Subtitle
            Text("Умные уведомления")
                .font(.system(size: 20))
                .foregroundStyle(c.textSecondary)
                .padding(.top, 8)

            Spacer(minLength: 20)

            // Security text
            Text("Ваши данные в безопасности. Мы не читаем ваши сообщения.")
                .font(.system(size: 18))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(8)
                .padding(.horizontal, 24)

            Spacer(minLength: 40)

            // Button / error
            VStack(spacing: 12) {
                if let error = appState.connectError {
                    Text("Не удалось подключиться к серверу. Проверьте интернет и нажмите \u{00AB}Повторить\u{00BB}.")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)

                    Button("Повторить") {
                        Task { await appState.start() }
                    }
                    .buttonStyle(WelcomePrimaryButtonStyle())
                } else {
                    Button("Начать") {
                        Task { await appState.start() }
                    }
                    .buttonStyle(WelcomePrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Legal links (EN)

    private var legalLinks: some View {
        HStack(spacing: 8) {
            linkButton("Privacy Policy", Theme.privacyURL)
            Text("|")
                .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
                .font(.system(size: 14))
            linkButton("Terms of Service", Theme.termsURL)
            Text("|")
                .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
                .font(.system(size: 14))
            linkButton("Support", Theme.supportURL)
        }
        .font(.system(size: 14))
    }

    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .underline()
        .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
    }
}

// MARK: - Welcome primary button (height 60, borderRadius 16, Theme.primary)

private struct WelcomePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AppState())
}
