//
//  ContentView.swift
//  MKSPush
//
//  Root view: routes between Welcome / QR / Connected screens,
//  provides theme colours, handles deep links.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if !appState.isLoaded {
                loadingView
            } else {
                switch appState.route {
                case .welcome:
                    WelcomeView()
                case .qr:
                    QRView()
                case .connected:
                    ConnectedView()
                }
            }
        }
        .environment(\.themeColors, ThemeColors(colorScheme: colorScheme))
        .environmentObject(appState)
        .withBadgeSync()
        .withPushTokenSync()
        .withWidgetFeedSync()
        .onReceive(NotificationCenter.default.publisher(for: .mkspushDeepLink)) { notif in
            if let url = notif.object as? URL {
                DeepLinkManager.shared.handleDeepLink(url, appState: appState)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Загрузка…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ThemeColors(colorScheme: colorScheme).bg)
    }
}

#Preview {
    ContentView()
}
