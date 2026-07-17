//
//  WidgetSharedViews.swift
//  MKSPushWidget
//
//  Small shared pieces (header, background, empty state) reused across all
//  three Home Screen widgets so their look stays identical.
//

import SwiftUI
import WidgetKit

/// Header row shown at the top of every widget: the app icon plus a small "MKS Push" label.
struct WidgetHeader: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("WidgetAppIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .clipShape(.rect(cornerRadius: 4))
            Text("MKS Push")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// The shared green gradient background for all widgets.
struct WidgetBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 7 / 255, green: 26 / 255, blue: 16 / 255),
                Color(red: 12 / 255, green: 40 / 255, blue: 24 / 255),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Small centered placeholder text used when a widget has nothing to show.
struct WidgetEmptyState: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 4)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
        }
    }
}
