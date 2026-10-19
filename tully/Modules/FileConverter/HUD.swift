import AppKit
import SwiftUI

/// Small floating status card near the drop point: working -> done (click to reveal) / error.
final class HUD {
    enum State: Equatable { case working(String), done(String, [URL]), failed(String) }

    private let panel: NSPanel
    private let model = HUDModel()
    private var hideWork: DispatchWorkItem?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
    }

    func show(_ state: State, near point: NSPoint) {
        hideWork?.cancel()
        model.state = state
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        var origin = NSPoint(x: point.x - 140, y: point.y - 100)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - 288)
            origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - 72)
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        switch state {
        case .working: break
        case .done: scheduleHide(after: 4)
        case .failed: scheduleHide(after: 7)
        }
    }

    private func scheduleHide(after seconds: Double) {
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

@Observable
final class HUDModel {
    var state: HUD.State = .working("")
}

struct HUDView: View {
    let model: HUDModel

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(width: 280, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .onTapGesture {
            if case .done(_, let urls) = model.state { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var icon: some View {
        switch model.state {
        case .working: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 22)).foregroundStyle(.orange)
        }
    }

    private var title: String {
        switch model.state {
        case .working(let text): return text
        case .done(let text, _): return text
        case .failed: return "Couldn't finish"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .working: return "Working locally on your Mac…"
        case .done(_, let urls): return urls.count == 1 ? "\(urls[0].lastPathComponent) · click to show" : "\(urls.count) files · click to show"
        case .failed(let message): return message
        }
    }
}
