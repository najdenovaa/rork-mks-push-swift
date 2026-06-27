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
                VStack(spacing: 22) {
                    header

                    statusText

                    SiblingAppsLinks()
                        .padding(.top, 12)

                    if push.authorizationStatus != .authorized {
                        notificationBanner
                    }

                    openAppButton

                    legalLinks
                        .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .padding(.bottom, 48)
            }
        }
        .background(c.bg)
        .onAppear {
            Task {
                await push.refreshAuthorizationStatus()
            }
            appState.startStatusPolling(interval: 60)
        }
        .onDisappear {
            appState.stopStatusPolling()
        }
        .alert("Disconnect?", isPresented: $showDisconnectAlert) {
            Button("Disconnect", role: .destructive) {
                Task { await disconnect() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will stop receiving notifications from connected apps.")
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
        Text("Push notification delivery from web apps is enabled")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(c.text)
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
                    ? "Notifications are disabled. You can enable them in device Settings."
                    : "Enable notifications so you don't miss messages"
                )
                .font(.subheadline)
                .foregroundStyle(c.text)
                Spacer(minLength: 0)
            }

            if push.authorizationStatus == .denied {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.primary))
            } else {
                Button("Enable") {
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
        Button("Open App") {
            DeepLinkManager.shared.openLinkedApp()
        }
        .buttonStyle(PrimaryButtonStyle(color: Theme.green))
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

#Preview {
    ConnectedView()
        .environmentObject(AppState())
}
