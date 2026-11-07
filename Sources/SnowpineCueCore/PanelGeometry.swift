import CoreGraphics

/// Which edges of the prompter a drag is resizing.
public struct ResizeEdges: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let left = ResizeEdges(rawValue: 1 << 0)
    public static let right = ResizeEdges(rawValue: 1 << 1)
    public static let top = ResizeEdges(rawValue: 1 << 2)
    public static let bottom = ResizeEdges(rawValue: 1 << 3)
    public static let all: ResizeEdges = [.left, .right, .top, .bottom]
}

/// How big the prompter may get, and how its height relates to the number of lines.
public struct PanelLimits: Sendable {
    public var width: ClosedRange<CGFloat>
    public var lines: ClosedRange<Int>
    public var lineHeight: CGFloat
    /// The height that isn't script lines: the top band and the bottom margin.
    public var chrome: CGFloat

    public init(width: ClosedRange<CGFloat>, lines: ClosedRange<Int>, lineHeight: CGFloat, chrome: CGFloat) {
        self.width = width
        self.lines = lines
        self.lineHeight = max(1, lineHeight)
        self.chrome = chrome
    }

    public func height(lines count: Int) -> CGFloat { chrome + CGFloat(count) * lineHeight }

    /// The whole number of lines nearest to a height, within the limits.
    public func lines(forHeight height: CGFloat) -> Int {
        let raw = ((height - chrome) / lineHeight).rounded()
        guard raw.isFinite else { return lines.lowerBound }
        return min(lines.upperBound, max(lines.lowerBound, Int(raw)))
    }

    public func clampWidth(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return width.lowerBound }
        return min(width.upperBound, max(width.lowerBound, value.rounded()))
    }
}

/// Sizes and positions for the prompter window, kept free of AppKit so they can be tested.
/// Coordinates follow AppKit: the origin is at the bottom left and y grows upward.
public enum PanelGeometry {
    /// How close to an edge, in points, a press starts a resize.
    public static let edgeGrab: CGFloat = 8
    /// Near a corner, a press this close to one edge and on the other edge resizes both.
    public static let cornerGrab: CGFloat = 18

    /// The edges under a point inside a window of the given size, limited to the edges that can move.
    public static func edges(at point: CGPoint, in size: CGSize, allowed: ResizeEdges) -> ResizeEdges {
        let nearLeft = point.x <= edgeGrab
        let nearRight = point.x >= size.width - edgeGrab
        let nearBottom = point.y <= edgeGrab
        let nearTop = point.y >= size.height - edgeGrab
        let cornerLeft = point.x <= cornerGrab
        let cornerRight = point.x >= size.width - cornerGrab
        let cornerBottom = point.y <= cornerGrab
        let cornerTop = point.y >= size.height - cornerGrab

        var hit: ResizeEdges = []
        if nearLeft || (cornerLeft && (nearBottom || nearTop)) { hit.insert(.left) }
        if nearRight || (cornerRight && (nearBottom || nearTop)) { hit.insert(.right) }
        if nearBottom || (cornerBottom && (nearLeft || nearRight)) { hit.insert(.bottom) }
        if nearTop || (cornerTop && (nearLeft || nearRight)) { hit.insert(.top) }
        return hit.intersection(allowed)
    }

    /// The strip hangs from the notch and stays centered under it, so its two sides move
    /// together and only its bottom edge moves up or down. `dx` and `dy` are how far the
    /// pointer has moved since the press, in screen points (y up).
    public static func resizeStrip(width: CGFloat, lines: Int, edges: ResizeEdges,
                                   dx: CGFloat, dy: CGFloat, limits: PanelLimits) -> (width: CGFloat, lines: Int) {
        var newWidth = width
        if edges.contains(.right) {
            newWidth = width + 2 * dx
        } else if edges.contains(.left) {
            newWidth = width - 2 * dx
        }
        var newLines = lines
        if edges.contains(.bottom) {
            newLines = limits.lines(forHeight: limits.height(lines: lines) - dy)
        }
        return (limits.clampWidth(newWidth), newLines)
    }

    /// The floating window: the dragged edges move and the opposite edges stay put.
    /// The height snaps to whole lines.
    public static func resizeFloating(_ frame: CGRect, edges: ResizeEdges, dx: CGFloat, dy: CGFloat,
                                      limits: PanelLimits) -> (frame: CGRect, lines: Int) {
        var width = frame.width
        var minX = frame.minX
        if edges.contains(.right) {
            width = limits.clampWidth(frame.width + dx)
        } else if edges.contains(.left) {
            width = limits.clampWidth(frame.width - dx)
            minX = frame.maxX - width
        }

        var lines = limits.lines(forHeight: frame.height)
        if edges.contains(.top) {
            lines = limits.lines(forHeight: frame.height + dy)
        } else if edges.contains(.bottom) {
            lines = limits.lines(forHeight: frame.height - dy)
        }
        let height = limits.height(lines: lines)
        // Moving the top keeps the bottom where it is; anything else keeps the top where it is.
        let minY = edges.contains(.top) ? frame.minY : frame.maxY - height
        return (CGRect(x: minX, y: minY, width: width, height: height), lines)
    }

    /// Keeps a window inside the bounds when it fits there, and pins it to the top left when it doesn't,
    /// so its top band (where it is dragged from) is always reachable.
    public static func clamp(_ frame: CGRect, to bounds: CGRect) -> CGRect {
        var result = frame
        if frame.width <= bounds.width {
            result.origin.x = min(max(frame.minX, bounds.minX), bounds.maxX - frame.width)
        } else {
            result.origin.x = bounds.minX
        }
        if frame.height <= bounds.height {
            result.origin.y = min(max(frame.minY, bounds.minY), bounds.maxY - frame.height)
        } else {
            result.origin.y = bounds.maxY - frame.height
        }
        return result
    }
}
