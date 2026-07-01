//
//  ConnectedView.swift
//  MKSPush
//
//  Connected screen: status circle, notification banner, events feed, actions, legal links.
//  Pixel-parity with React Native ConnectedScreen.tsx.
//

import SwiftUI

struct ConnectedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.themeColors) private var c
    @ObservedObject private var push = PushManager.shared

    @State private var isDisconnecting = false
    @State private var showDisconnectAlert = false
    @State private var events: [EventItem] = []
    @State private var eventsTask: Task<Void, Never>?

    private let api = APIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Status circle — always active on Connected screen
                StatusCircle(status: .active)
                    .padding(.top, 24)

                // Status text
                Text("Подключено")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.green)
                    .padding(.top, 16)

                // Sub text
                Text("Уведомления с веб-приложений приходят автоматически")
                    .font(.system(size: 15))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                // Notification banner (before body, not inside status block)
                if push.authorizationStatus != .authorized {
                    notificationBanner
                        .padding(.top, 24)
                }

                // Events feed
                eventsSection
                    .padding(.top, 28)

                // Open profile button
                Button("Открыть профиль") {
                    DeepLinkManager.shared.openLinkedApp(
                        httpsURL: nil,
                        userId: appState.userId
                    )
                }
                .buttonStyle(ConnectedPrimaryButtonStyle())
                .padding(.top, 28)

                // Disconnect button — border only, red text, no fill
                Button("Отключить") {
                    showDisconnectAlert = true
                }
                .buttonStyle(ConnectedDisconnectButtonStyle())
                .padding(.top, 14)

                // Legal links (EN)
                legalLinks
                    .padding(.top, 22)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
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
            startEventsPolling()
        }
        .onDisappear {
            appState.stopStatusPolling()
            eventsTask?.cancel()
        }
        .alert("Отключить?", isPresented: $showDisconnectAlert) {
            Button("Отключить", role: .destructive) {
                Task { await disconnect() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы перестанете получать push-уведомления с веб-приложений.")
        }
    }

    // MARK: - Notification banner

    private var notificationBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                push.authorizationStatus == .denied
                ? "Уведомления отключены. Включить можно в Настройках устройства."
                : "Включите уведомления, чтобы не пропускать сообщения"
            )
            .font(.subheadline)
            .foregroundStyle(c.text)

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
        .padding(16)
        .background(c.surface)
        .clipShape(.rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(c.border, lineWidth: 1)
        }
    }

    // MARK: - Events feed

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title row with count
            HStack {
                Text("Последние события")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Text("\(events.count)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(c.border.opacity(0.5))
                    .clipShape(.capsule)
            }

            if events.isEmpty {
                Text("Событий пока нет. Они появятся при получении данных.")
                    .font(.system(size: 14))
                    .foregroundStyle(c.textFaint)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(events) { event in
                            eventCard(event)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private func eventCard(_ event: EventItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.text)
                Spacer()
                Text(formatTime(event.time))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textFaint)
            }
            Text(event.body)
                .font(.system(size: 14))
                .foregroundStyle(c.textSecondary)
        }
        .padding(12)
        .background(c.card)
        .clipShape(.rect(cornerRadius: 10))
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
        .foregroundStyle(Color(red: 136/255, green: 136/255, blue: 136/255))
    }

    // MARK: - Actions

    private func disconnect() async {
        isDisconnecting = true
        eventsTask?.cancel()
        appState.stopStatusPolling()
        await appState.disconnect()
        isDisconnecting = false
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Events polling

    private func startEventsPolling() {
        eventsTask?.cancel()
        eventsTask = Task {
            while !Task.isCancelled {
                if let userId = appState.userId {
                    if let fetched = try? await api.fetchEvents(userId: userId) {
                        await MainActor.run { events = fetched }
                    }
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    // MARK: - Time formatting

    private func formatTime(_ utcString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let str = utcString.hasSuffix("Z") ? utcString : utcString + "Z"
        guard let date = formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str) else {
            return utcString
        }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return timeFormatter.string(from: date)
    }
}

// MARK: - Connected primary button (height 56, borderRadius 16, Theme.primary)

private struct ConnectedPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Theme.primary.opacity(configuration.isPressed ? 0.85 : 1))
            .clipShape(.rect(cornerRadius: 16))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Connected disconnect button (border only, red text, no fill)

private struct ConnectedDisconnectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.red)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.clear)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Theme.green, lineWidth: 2)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

#Preview {
    ConnectedView()
        .environmentObject(AppState())
}
