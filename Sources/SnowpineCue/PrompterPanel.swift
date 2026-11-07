import AppKit
import SnowpineCueCore
import SwiftUI

/// A borderless panel that can sit over the menu bar, under the camera, or float anywhere.
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
        isMovable = false  // The app moves it itself, so a click can still start and pause
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

/// Hosts the SwiftUI view and turns the mouse into prompter commands:
/// - a click starts or pauses, and scrolling moves by lines;
/// - the three dots, a right-click or a Control-click open the same menu as the menu bar icon,
///   so the menu is always reachable, even when a crowded menu bar hides the icon behind the notch;
/// - dragging an edge resizes, and dragging the floating window moves it.
final class PrompterHostingView: NSHostingView<PrompterView> {
    var onScroll: ((CGFloat) -> Void)?
    var onClick: (() -> Void)?
    var makeMenu: (() -> NSMenu)?
    /// Called once when a resize or move starts, then with the edges being dragged (empty for a move)
    /// and how far the pointer has moved since the press, in screen points with y up.
    var onDragBegan: ((ResizeEdges) -> Void)?
    var onDrag: ((ResizeEdges, CGFloat, CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    /// Height of the top band, where the three dots sit.
    var menuBandHeight: CGFloat = 32
    /// The edges a drag can resize: the strip's sides and bottom, or every edge of the floating window.
    var resizableEdges: ResizeEdges = [.left, .right, .bottom]
    /// Whether dragging inside the prompter moves it (the floating window) or does nothing (the strip).
    var dragMoves = false

    private enum Press {
        case none
        case body(start: NSPoint, moving: Bool)
        case resize(ResizeEdges, start: NSPoint)
    }
    private var press = Press.none
    /// How far the pointer must travel before a press on the floating window becomes a move, not a click.
    private let moveThreshold: CGFloat = 4

    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY) }
    override func rightMouseDown(with event: NSEvent) { showMenu(for: event) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // A drag whose mouse up never arrived (the window was hidden mid-drag) ends here.
        switch press {
        case .resize, .body(_, true): onDragEnded?()
        default: break
        }
        if event.modifierFlags.contains(.control) || isOnMenuDots(event) {
            press = .none
            showMenu(for: event)
            return
        }
        let start = screenPoint(event)
        let edges = edges(at: event.locationInWindow)
        if edges.isEmpty {
            press = .body(start: start, moving: false)
        } else {
            press = .resize(edges, start: start)
            onDragBegan?(edges)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = screenPoint(event)
        switch press {
        case .none:
            break
        case .resize(let edges, let start):
            onDrag?(edges, point.x - start.x, point.y - start.y)
        case .body(let start, let moving):
            guard dragMoves else { return }
            if !moving {
                guard hypot(point.x - start.x, point.y - start.y) >= moveThreshold else { return }
                press = .body(start: start, moving: true)
                onDragBegan?([])
            }
            onDrag?([], point.x - start.x, point.y - start.y)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let finished = press
        press = .none
        switch finished {
        case .none:
            break
        case .body(_, let moving):
            if moving { onDragEnded?() } else { onClick?() }
        case .resize:
            onDragEnded?()
        }
    }

    // MARK: Cursor

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self && area.userInfo?["snowpineCue"] != nil {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: ["snowpineCue": true]))
    }

    override func mouseMoved(with event: NSEvent) {
        guard case .none = press else { return }
        Self.cursor(for: edges(at: event.locationInWindow)).set()
    }

    override func mouseExited(with event: NSEvent) {
        guard case .none = press else { return }
        NSCursor.arrow.set()
    }

    static func cursor(for edges: ResizeEdges) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition?
            switch edges {
            case [.left]: position = .left
            case [.right]: position = .right
            case [.top]: position = .top
            case [.bottom]: position = .bottom
            case [.left, .top]: position = .topLeft
            case [.right, .top]: position = .topRight
            case [.left, .bottom]: position = .bottomLeft
            case [.right, .bottom]: position = .bottomRight
            default: position = nil
            }
            if let position { return .frameResize(position: position, directions: .all) }
            return .arrow
        }
        if edges.isEmpty { return .arrow }
        if edges == [.left] || edges == [.right] { return .resizeLeftRight }
        if edges == [.top] || edges == [.bottom] { return .resizeUpDown }
        return .crosshair
    }

    // MARK: Helpers

    private func edges(at pointInWindow: NSPoint) -> ResizeEdges {
        guard let window else { return [] }
        let edges = PanelGeometry.edges(at: pointInWindow, in: window.frame.size, allowed: resizableEdges)
        // The three dots win over the right edge in the top band.
        if isOnMenuDots(pointInWindow) { return [] }
        return edges
    }

    private func screenPoint(_ event: NSEvent) -> NSPoint {
        guard let window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func isOnMenuDots(_ event: NSEvent) -> Bool { isOnMenuDots(event.locationInWindow) }

    private func isOnMenuDots(_ point: NSPoint) -> Bool {
        guard let window else { return false }
        // origin at the window's bottom left
        return point.x >= window.frame.width - 52 && point.x <= window.frame.width - PanelGeometry.edgeGrab
            && point.y >= window.frame.height - menuBandHeight
    }

    private func showMenu(for event: NSEvent) {
        guard let menu = makeMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}
