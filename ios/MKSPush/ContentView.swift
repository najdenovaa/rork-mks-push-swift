//
//  ContentView.swift
//  MKSPush
//

import SwiftUI

/// Root view that routes between the three top-level screens based on connection state.
struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        Group {
            switch appState.route {
            case .welcome:
                WelcomeView()
                    .transition(.opacity)
            case .qr:
                QRView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            case .connected:
                ConnectedView()
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appState.route)
        .environmentObject(appState)
    }
}

#Preview {
    ContentView()
}
