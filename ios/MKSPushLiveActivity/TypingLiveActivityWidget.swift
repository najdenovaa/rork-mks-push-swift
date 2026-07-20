//
//  TypingLiveActivityWidget.swift
//  MKSPushLiveActivity
//
//  "Собеседник печатает…" Live Activity:
//  - Dynamic Island: compact pill only (icon + name on the left, pulsing pencil
//    on the right). Lock Screen and the expanded region use the exact same
//    slim row so a push-to-start launch never flashes a tall banner.
//

import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

private let accentGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
private let backgroundGreen = Color(red: 7 / 255, green: 26 / 255, blue: 16 / 255)

struct TypingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TypingActivityAttributes.self) { context in
            // Lock Screen / banner presentation — same slim row as compact/expanded.
            TypingCompactPillRow(senderName: context.state.senderName)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .activityBackgroundTint(backgroundGreen.opacity(0.92))
                .activitySystemActionForegroundColor(accentGreen)
        } dynamicIsland: { context in
            DynamicIsland {
                // Deliberately the same slim row as compact — nothing that grows
                // the island vertically when it first flashes expanded.
                DynamicIslandExpandedRegion(.center) {
                    TypingCompactPillRow(senderName: context.state.senderName)
                        .padding(.horizontal, 8)
                }
            } compactLeading: {
                HStack(spacing: 6) {
                    TypingIconView(size: 20)
                    Text(context.state.senderName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } compactTrailing: {
                TypingPencilIcon()
            } minimal: {
                Image(systemName: "pencil.line")
                    .foregroundStyle(accentGreen)
            }
            .keylineTint(accentGreen)
        }
    }
}

/// Single slim row shared by Lock Screen, expanded, and (visually) compact presentations.
struct TypingCompactPillRow: View {
    let senderName: String

    var body: some View {
        HStack(spacing: 6) {
            TypingIconView(size: 20)
            Text(senderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            TypingPencilIcon()
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

/// Pulsing "pencil writes" icon on the right of the pill.
struct TypingPencilIcon: View {
    var body: some View {
        Image(systemName: "pencil.line")
            .symbolEffect(.pulse, options: .repeating)
            .foregroundStyle(.secondary)
    }
}
