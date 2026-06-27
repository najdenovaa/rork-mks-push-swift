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
            switch appState.route {
            case .welcome:
                WelcomeView()
            case .qr:
                QRView()
            case .connected:
                ConnectedView()
            }
        }
        .environment(\.themeColors, ThemeColors(colorScheme: colorScheme))
        .environmentObject(appState)
        .withBadgeSync()
        .withPushTokenSync()
        .onReceive(NotificationCenter.default.publisher(for: .mkspushDeepLink)) { notif in
            if let url = notif.object as? URL {
                DeepLinkManager.shared.handleDeepLink(url, appState: appState)
            }
        }
    }
}

#Preview {
    ContentView()
}
