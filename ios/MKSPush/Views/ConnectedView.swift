//
//  ConnectedView.swift
//  MKSPush
//
//  Connected screen: status circle, notification banner, actions, legal links.
//  Ported from React Native build 23 ConnectedScreen.tsx.
//

import SwiftUI

struct ConnectedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c
    @ObservedObject private var push = PushManager.shared

    @State private var isDisconnecting = false
    @State private var showDisconnectAlert = false

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                BackButton { showDisconnectAlert = true }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            ScrollView {
                VStack(spacing: 24) {
                    header

                    statusText

                    subText

                    if push.authorizationStatus != .authorized {
                        notificationBanner
                    }

                    openAppButton

                    legalLinks
                        .padding(.top, 12)

                    disconnectButton
                        .padding(.top, 8)

                    SiblingAppsLinks()
                        .padding(.top, 28)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .padding(.bottom, 48)
            }
        }
        .background(c.bg)
        .disabled(isDisconnecting)
        .overlay {
            if isDisconnecting {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                ProgressView()
                    .tint(Theme.green)
            }
        }
        .onAppear {
            Task {
                await push.refreshAuthorizationStatus()
            }
            appState.startStatusPolling(interval: 60)
        }
        .onDisappear {
            appState.stopStatusPolling()
        }
        .alert("Отключиться?", isPresented: $showDisconnectAlert) {
            Button("Отключить", role: .destructive) {
                Task { await disconnect() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы перестанете получать уведомления от подключённых приложений.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 16) {
            StatusCircle(status: appState.status)
                .padding(.top, 8)
        }
    }

    // MARK: - Status text

    private var statusText: some View {
        Text("Доставка уведомлений с веб-приложений включена")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Theme.green)
            .multilineTextAlignment(.center)
    }

    // MARK: - Sub text

    private var subText: some View {
        Text("Push-уведомления с ваших веб-приложений приходят автоматически")
            .font(.system(size: 18))
            .foregroundStyle(c.textSecondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Notification banner

    private var notificationBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                Text(
                    push.authorizationStatus == .denied
                    ? "Уведомления отключены. Включить можно в Настройках устройства."
                    : "Включите уведомления, чтобы не пропускать сообщения"
                )
                .font(.subheadline)
                .foregroundStyle(c.text)
                Spacer(minLength: 0)
            }

            if push.authorizationStatus == .denied {
                Button("Открыть настройки") { openSettings() }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.primary))
            } else {
                Button("Включить") {
                    Task { await push.requestAuthorization() }
                }
                .buttonStyle(SecondaryButtonStyle(color: Theme.primary))
            }
        }
        .padding(18)
        .background(Theme.primary.opacity(0.08))
        .clipShape(.rect(cornerRadius: 14))
    }

    // MARK: - Open app button

    private var openAppButton: some View {
        Button("Открыть приложение") {
            DeepLinkManager.shared.openLinkedApp()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.green))
    }

    // MARK: - Disconnect button

    private var disconnectButton: some View {
        Button("Отключить") {
            showDisconnectAlert = true
        }
        .buttonStyle(DestructiveButtonStyle())
    }

    // MARK: - Legal links

    private var legalLinks: some View {
        HStack(spacing: 8) {
            linkButton("Политика конфиденциальности", Theme.privacyURL)
            Text("·")
                .foregroundStyle(c.textFaint)
                .font(.system(size: 14))
            linkButton("Пользовательское соглашение", Theme.termsURL)
            Text("·")
                .foregroundStyle(c.textFaint)
                .font(.system(size: 14))
            linkButton("Поддержка", Theme.supportURL)
        }
    }

    private func linkButton(_ title: String, _ urlString: String) -> some View {
        Button(title) {
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
        }
        .buttonStyle(.plain)
        .underline()
        .font(.system(size: 14))
        .foregroundStyle(c.textFaint)
    }

    // MARK: - Actions

    private func disconnect() async {
        isDisconnecting = true
        appState.stopStatusPolling()
        await appState.disconnect()
        isDisconnecting = false
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Destructive button style

private struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.red.opacity(0.1))
            .clipShape(.rect(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ConnectedView()
        .environmentObject(AppState())
}
