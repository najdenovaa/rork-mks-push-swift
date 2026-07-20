//
//  TypingLiveActivityWidget.swift
//  MKSPushLiveActivity
//
//  "Собеседник печатает…" Live Activity:
//  - Dynamic Island: compact pill only (icon + name on the left, pulsing pencil
//    on the right). The island may grow horizontally but never in height —
//    the expanded region is a single slim row.
//  - Lock Screen (devices without Dynamic Island): compact strip, same layout.
//

import ActivityKit
import SwiftUI
import WidgetKit

private let accentGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
private let backgroundGreen = Color(red: 7 / 255, green: 26 / 255, blue: 16 / 255)

struct TypingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TypingActivityAttributes.self) { context in
            // Lock Screen / banner presentation — compact strip.
            TypingLiveActivityView(senderName: context.state.senderName)
                .activityBackgroundTint(backgroundGreen.opacity(0.92))
                .activitySystemActionForegroundColor(accentGreen)
        } dynamicIsland: { context in
            DynamicIsland {
                // Intentionally a single slim center row — nothing that grows
                // the island vertically when long-pressed.
                DynamicIslandExpandedRegion(.center) {
                    TypingRowView(senderName: context.state.senderName)
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

/// App icon (or sender initials fallback) shown on the left of the pill.
struct TypingIconView: View {
    let size: CGFloat

    var body: some View {
        Image("WidgetAppIcon")
            .resizable()
            .aspectRatio(contentMode: .fill)
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

/// Single slim row reused by the expanded center region: name + pencil.
struct TypingRowView: View {
    let senderName: String

    var body: some View {
        HStack(spacing: 8) {
            TypingIconView(size: 20)
            Text(senderName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text("печатает…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            TypingPencilIcon()
        }
    }
}

/// Lock Screen presentation — a compact strip mirroring the pill layout.
struct TypingLiveActivityView: View {
    let senderName: String

    var body: some View {
        HStack(spacing: 10) {
            TypingIconView(size: 24)
            Text(senderName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Text("печатает…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "pencil.line")
                .symbolEffect(.pulse, options: .repeating)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
