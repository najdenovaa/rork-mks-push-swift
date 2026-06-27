//
//  ConnectedView.swift
//  MKSPush
//

import SwiftUI
import UIKit

/// Shown when the device is connected. Hosts the notification banner and events feed.
struct ConnectedView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = PushManager.shared

    @State private var events: [AppEvent] = []
    @State private var hasLoadedEvents = false
    @State private var isDisconnecting = false
    @State private var checkmarkScale: CGFloat = 0.6

    @State private var eventsTask: Task<Void, Never>?

    private let api = APIService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header

                if push.authorizationStatus != .authorized {
                    notificationBanner
                }

                eventsSection

                actionButtons
                    .padding(.top, 4)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .background(Color(.systemBackground))
        .onAppear {
            animateCheckmark()
            startEventsPolling()
            Task { await push.refreshAuthorizationStatus() }
        }
        .onDisappear { eventsTask?.cancel() }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await push.refreshAuthorizationStatus() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.green.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.green)
                    .scaleEffect(checkmarkScale)
            }
            Text("Подключено")
                .font(.title.bold())
            Text("Устройство подключено")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var notificationBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.blue)
                Text(push.authorizationStatus == .denied
                     ? "Уведомления отключены. Включить можно в Настройках устройства."
                     : "Включите уведомления, чтобы не пропускать сообщения")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }

            if push.authorizationStatus == .denied {
                Button("Открыть настройки") { openSettings() }
                    .buttonStyle(SecondaryButtonStyle(color: Theme.blue))
            } else {
                Button("Включить") {
                    Task { await push.requestAuthorization() }
                }
                .buttonStyle(SecondaryButtonStyle(color: Theme.blue))
            }
        }
        .padding(18)
        .background(Theme.blue.opacity(0.08))
        .clipShape(.rect(cornerRadius: 18))
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Последние события")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if events.isEmpty {
                emptyEvents
            } else {
                VStack(spacing: 10) {
                    ForEach(events) { event in
                        eventCard(event)
                    }
                }
            }
        }
    }

    private func eventCard(_ event: AppEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(event.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(event.displayTime)
                .font(.caption.weight(.medium))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var emptyEvents: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(hasLoadedEvents ? "Событий пока нет." : "Загрузка событий…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(.secondarySystemBackground))
        .clipShape(.rect(cornerRadius: 14))
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button("Открыть приложение") { openMaxApp() }
                .buttonStyle(PrimaryButtonStyle(color: Theme.green))

            Button {
                Task { await disconnect() }
            } label: {
                HStack(spacing: 8) {
                    if isDisconnecting { ProgressView().tint(Theme.red) }
                    Text("Отключить")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .disabled(isDisconnecting)
        }
    }

    // MARK: - Actions

    private func animateCheckmark() {
        checkmarkScale = 0.6
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
            checkmarkScale = 1
        }
    }

    private func startEventsPolling() {
        guard let userId = appState.userId else { return }
        eventsTask?.cancel()
        eventsTask = Task {
            while !Task.isCancelled {
                if let fetched = try? await api.events(userId: userId) {
                    events = fetched
                    hasLoadedEvents = true
                } else if !hasLoadedEvents {
                    hasLoadedEvents = true
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func disconnect() async {
        isDisconnecting = true
        eventsTask?.cancel()
        await appState.disconnect()
        isDisconnecting = false
    }

    private func openMaxApp() {
        guard let url = URL(string: "https://mkspush.ru/go") else { return }
        UIApplication.shared.open(url)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
