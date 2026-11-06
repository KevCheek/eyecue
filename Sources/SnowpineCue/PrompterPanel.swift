import AppKit
import SwiftUI

/// A borderless panel that can sit over the menu bar, under the camera.
/// It never takes keyboard focus, so typing and Zoom keep working while it shows.
final class PrompterPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar  // above the menu bar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        sharingType = .none  // hidden from capture from the start; settings can change it later
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Borderless windows are normally pushed below the menu bar; this one belongs at the very top.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    /// Keeps the panel out of screen sharing, recordings and screenshots.
    /// This is the standard macOS window setting; test it with your own call app before relying on it.
    func setHiddenFromCapture(_ hidden: Bool) {
        sharingType = hidden ? .none : .readOnly
    }
}

/// Hosts the SwiftUI view and turns scrolling and clicks into prompter commands.
/// The three dots, a right-click or a Control-click open the same menu as the menu bar icon,
/// so the menu is always reachable, even when a crowded menu bar hides the icon behind the notch.
final class PrompterHostingView: NSHostingView<PrompterView> {
    var onScroll: ((CGFloat) -> Void)?
    var onClick: (() -> Void)?
    var makeMenu: (() -> NSMenu)?
    /// Height of the top band, where the three dots sit.
    var menuBandHeight: CGFloat = 32

    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) || isOnMenuDots(event) { showMenu(for: event) } else { onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { showMenu(for: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func isOnMenuDots(_ event: NSEvent) -> Bool {
        guard let window else { return false }
        let point = event.locationInWindow  // origin at the window's bottom left
        return point.x >= window.frame.width - 52 && point.y >= window.frame.height - menuBandHeight
    }

    private func showMenu(for event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
