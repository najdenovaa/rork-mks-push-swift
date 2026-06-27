//
//  WelcomeView.swift
//  MKSPush
//

import SwiftUI

/// First screen shown when the device is not connected.
struct WelcomeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var bellPulse = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            // Hero icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Theme.green, Theme.greenDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 116, height: 116)
                    .shadow(color: Theme.green.opacity(0.4), radius: 24, y: 10)
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

            VStack(spacing: 14) {
                Text("MKS Push")
                    .font(.system(size: 40, weight: .bold, design: .rounded))

                Text("Умные уведомления")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.green)

                Text("Получайте push-уведомления о новых сообщениях и звонках.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
            }

            Spacer()

            VStack(spacing: 12) {
                if let error = appState.connectError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    Task { await appState.start() }
                } label: {
                    HStack(spacing: 8) {
                        if appState.isConnecting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(appState.isConnecting ? "Подключение…" : "Начать")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(appState.isConnecting)
            }
            .padding(.horizontal, 24)

            // Legal links
            HStack(spacing: 18) {
                Link("Политика конфиденциальности", destination: URL(string: "https://mkspush.ru/privacy")!)
                Link("Пользовательское соглашение", destination: URL(string: "https://mkspush.ru/terms")!)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
