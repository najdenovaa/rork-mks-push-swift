//
//  TypingLiveActivityWidget.swift
//  MKSPushLiveActivity
//
//  "Собеседник печатает…" Live Activity:
//  - Dynamic Island compact: app icon on the left + 3 animated green dots on
//    the right. No sender name anywhere — just icon + dots.
//  - Lock Screen / expanded use the same slim icon + dots row so a
//    push-to-start launch never flashes a tall banner.
//

import ActivityKit
import Combine
import SwiftUI
import UIKit
import WidgetKit

private let accentGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
private let backgroundGreen = Color(red: 7 / 255, green: 26 / 255, blue: 16 / 255)

struct TypingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TypingActivityAttributes.self) { _ in
            // Lock Screen / banner presentation — same slim row as expanded.
            TypingPillRow()
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .activityBackgroundTint(backgroundGreen.opacity(0.92))
                .activitySystemActionForegroundColor(accentGreen)
        } dynamicIsland: { _ in
            DynamicIsland {
                // Deliberately the same slim row as compact — nothing that grows
                // the island vertically when it first flashes expanded.
                DynamicIslandExpandedRegion(.center) {
                    TypingPillRow()
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                TypingIconView(size: 20)
            } compactTrailing: {
                TypingDotsView()
            } minimal: {
                TypingDotsView()
            }
            .keylineTint(accentGreen)
        }
    }
}

/// Single slim row shared by Lock Screen and the expanded island region.
struct TypingPillRow: View {
    var body: some View {
        HStack {
            TypingIconView(size: 20)
            Spacer(minLength: 4)
            TypingDotsView()
        }
    }
}

/// App icon (falls back to an "M" monogram if the bundled asset is missing).
struct TypingIconView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let uiImage = UIImage(named: "WidgetAppIcon", in: .main, compatibleWith: nil) {
                Image(uiImage: uiImage)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(accentGreen.opacity(0.22))
                    .overlay {
                        Text("M")
                            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                            .foregroundStyle(accentGreen)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.28))
    }
}

/// Three green "typing" dots cycling via Timer (TimelineView does not animate
/// inside Live Activities).
struct TypingDotsView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(accentGreen)
                    .frame(width: 6, height: 6)
                    .opacity(i == phase ? 1.0 : 0.35)
                    .offset(y: i == phase ? -2 : 0)
            }
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}
