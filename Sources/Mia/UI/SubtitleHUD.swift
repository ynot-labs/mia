import SwiftUI
import AppKit

/// Controller that manages the floating subtitle HUD window.
/// Creates a draggable, closable NSPanel that floats above other windows.
@MainActor
final class SubtitleHUDController: ObservableObject {
    private var panel: NSPanel?
    private var hostingView: NSView?

    @Published var currentText: String = ""
    @Published var subtitleLines: [SubtitleLine] = []

    func show(_ line: SubtitleLine) {
        subtitleLines.append(line)
        if subtitleLines.count > 10 { subtitleLines.removeFirst() }
        currentText = line.text
        ensurePanelExists()
    }

    func showEmpty() {
        ensurePanelExists()
    }

    func hide() {
        // Save and detach before close to avoid windowWillClose → hide() recursion
        let p = panel
        panel = nil
        p?.delegate = nil
        hostingView = nil
        subtitleLines.removeAll()
        currentText = ""
        p?.close()
    }

    var isVisible: Bool { panel != nil }

    // MARK: - Panel creation

    private func ensurePanelExists() {
        guard panel == nil else { return }

        let panelWidth: CGFloat = 800
        let panelHeight: CGFloat = 180

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Allow dragging by the background
        panel.isMovableByWindowBackground = true

        // Visual effect background
        let visualEffect = NSVisualEffectView(frame: panel.contentView!.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // SwiftUI subtitle content
        let subtitleView = SubtitleView(controller: self)
        let hostingView = NSHostingView(rootView: subtitleView)
        hostingView.frame = visualEffect.bounds
        hostingView.autoresizingMask = [.width, .height]

        visualEffect.addSubview(hostingView)
        panel.contentView?.addSubview(visualEffect)
        hostingView.translatesAutoresizingMaskIntoConstraints = true

        // Position at bottom center
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrame(NSRect(
                x: screenFrame.midX - panelWidth / 2,
                y: screenFrame.minY + 120,
                width: panelWidth,
                height: panelHeight
            ), display: true)
        }

        // Delegate to handle close button → call hide()
        panel.delegate = self.hudDelegate
        self.hudDelegate.onClose = { [weak self] in self?.hide() }

        panel.orderFrontRegardless()
        self.panel = panel
        self.hostingView = hostingView
    }

    private let hudDelegate = HUDWindowDelegate()
}

// MARK: - Window delegate for close button

private final class HUDWindowDelegate: NSObject, NSWindowDelegate {
    var onClose: (() -> Void)?

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
