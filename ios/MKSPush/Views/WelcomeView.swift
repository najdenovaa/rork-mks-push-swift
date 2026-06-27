//
//  WelcomeView.swift
//  MKSPush
//
//  Welcome screen when not connected.
//  Ported from React Native build 23 WelcomeScreen.tsx.
//

import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c

    @State private var bellPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            bodySection
                .frame(maxWidth: Theme.maxContentWidth)

            Spacer()

            // Footer
            VStack(spacing: 12) {
                Text("Приложение не читает ваши сообщения. Все данные остаются на устройстве и передаются только через защищённые уведомления.")
                    .font(.system(size: 12))
                    .foregroundStyle(c.textFaint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                SiblingAppsLinks()

                legalLinks
                    .padding(.bottom, 4)
            }
            .padding(.bottom, 32)
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.bg)
    }

    // MARK: - Body (hero + cta)

    private var bodySection: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Hero icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.green, Theme.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 116, height: 116)
                    .shadow(color: Theme.green.opacity(0.35), radius: 24, y: 10)
                    .scaleEffect(bellPulse ? 1.04 : 1)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    bellPulse = true
                }
            }

            Spacer(minLength: 28)

            VStack(spacing: 12) {
                Text("MKS Push")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(c.text)

                Text("Умные уведомления")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.green)

                Text("Ваши данные в безопасности. Мы не читаем ваши сообщения.")
                    .font(.system(size: 15))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            Spacer(minLength: 16)

            // Connect button / error
            VStack(spacing: 12) {
                if let error = appState.connectError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                if appState.isConnecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Подключаем…")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.green)
                    .clipShape(.rect(cornerRadius: 16))
                } else if appState.connectError != nil {
                    Button("Повторить") {
                        Task { await appState.start() }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.green))
                } else {
                    Button("Начать") {
                        Task { await appState.start() }
                    }
                    .buttonStyle(PrimaryButtonStyle(color: Theme.green))
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 40)
        }
    }

    // MARK: - Legal links

    private var legalLinks: some View {
        HStack(spacing: 8) {
            linkButton("Privacy Policy", Theme.privacyURL)
            Text("·")
                .foregroundStyle(c.textFaint)
                .font(.system(size: 14))
            linkButton("Terms of Service", Theme.termsURL)
            Text("·")
                .foregroundStyle(c.textFaint)
                .font(.system(size: 14))
            linkButton("Support", Theme.supportURL)
        }
        .font(.system(size: 14))
        .foregroundStyle(c.textFaint)
    }

    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .underline()
        .foregroundStyle(c.textFaint)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(AppState())
}
