// tully/Modules/TabSwitch/TabSwitchOverlayView.swift
import SwiftUI

struct TabSwitchOverlayView: View {
    @Environment(TabSwitchService.self) private var service

    var body: some View {
        let cols = min(max(service.windows.count, 1), 6)
        let columns = Array(repeating: GridItem(.fixed(196), spacing: 12), count: cols)

        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Array(service.windows.enumerated()), id: \.element.id) { index, window in
                WindowCard(info: window, isSelected: index == service.selectedIndex)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .ignoresSafeArea()
    }
}

private struct WindowCard: View {
    let info: WindowInfo
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.1))

                if let thumbnail = info.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let icon = info.appIcon {
                    VStack(spacing: 6) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 52, height: 52)
                        Text(info.appName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 180, height: 112)

            VStack(spacing: 2) {
                Text(info.appName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if !info.windowTitle.isEmpty && info.windowTitle != info.appName {
                    Text(info.windowTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: 180)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
    }
}
