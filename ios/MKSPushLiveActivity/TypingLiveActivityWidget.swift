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

/// Three green "typing" dots. Timers and regular SwiftUI animations are frozen
/// inside Live Activities (the island is rendered as an out-of-process
/// snapshot), so the only reliably animated option is an SF Symbol effect:
/// `ellipsis` + `.variableColor` is system-driven and keeps looping on its own.
struct TypingDotsView: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "ellipsis")
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers.nonReversing,
                    options: .repeating
                )
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentGreen)
        } else {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(accentGreen)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}
