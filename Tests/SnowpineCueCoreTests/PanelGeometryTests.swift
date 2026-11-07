import CoreGraphics
import Testing
@testable import SnowpineCueCore

private let limits = PanelLimits(width: 360...1200, lines: 2...10, lineHeight: 34, chrome: 52)
private let size = CGSize(width: 600, height: 52 + 3 * 34)

@Test func pressInTheMiddleIsNotAResize() {
    #expect(PanelGeometry.edges(at: CGPoint(x: 300, y: 60), in: size, allowed: .all) == [])
}

@Test func pressOnAnEdgeOrCornerPicksThoseEdges() {
    #expect(PanelGeometry.edges(at: CGPoint(x: 3, y: 60), in: size, allowed: .all) == .left)
    #expect(PanelGeometry.edges(at: CGPoint(x: 597, y: 60), in: size, allowed: .all) == .right)
    #expect(PanelGeometry.edges(at: CGPoint(x: 300, y: 2), in: size, allowed: .all) == .bottom)
    #expect(PanelGeometry.edges(at: CGPoint(x: 590, y: 4), in: size, allowed: .all) == [.right, .bottom])
    #expect(PanelGeometry.edges(at: CGPoint(x: 4, y: 150), in: size, allowed: .all) == [.left, .top])
}

@Test func theStripCannotBeResizedFromItsTop() {
    let strip: ResizeEdges = [.left, .right, .bottom]
    #expect(PanelGeometry.edges(at: CGPoint(x: 300, y: 152), in: size, allowed: strip) == [])
    #expect(PanelGeometry.edges(at: CGPoint(x: 597, y: 152), in: size, allowed: strip) == .right)
}

@Test func stripSidesMoveTogetherSoItStaysCentered() {
    let wider = PanelGeometry.resizeStrip(width: 600, lines: 3, edges: .right, dx: 50, dy: 0, limits: limits)
    #expect(wider.width == 700)
    let alsoWider = PanelGeometry.resizeStrip(width: 600, lines: 3, edges: .left, dx: -50, dy: 0, limits: limits)
    #expect(alsoWider.width == 700)
    #expect(alsoWider.lines == 3)
}

@Test func stripBottomSnapsToWholeLines() {
    // Down by two lines (y grows upward, so down is negative).
    #expect(PanelGeometry.resizeStrip(width: 600, lines: 3, edges: .bottom, dx: 0, dy: -68, limits: limits).lines == 5)
    // Less than half a line does nothing; more than half adds one.
    #expect(PanelGeometry.resizeStrip(width: 600, lines: 3, edges: .bottom, dx: 0, dy: -16, limits: limits).lines == 3)
    #expect(PanelGeometry.resizeStrip(width: 600, lines: 3, edges: .bottom, dx: 0, dy: -18, limits: limits).lines == 4)
}

@Test func stripStaysWithinItsLimits() {
    let tiny = PanelGeometry.resizeStrip(width: 600, lines: 3, edges: [.right, .bottom], dx: -500, dy: 500, limits: limits)
    #expect(tiny.width == 360)
    #expect(tiny.lines == 2)
    let huge = PanelGeometry.resizeStrip(width: 600, lines: 3, edges: [.left, .bottom], dx: -900, dy: -2000, limits: limits)
    #expect(huge.width == 1200)
    #expect(huge.lines == 10)
}

@Test func floatingCornerKeepsTheOppositeCornerPut() {
    let frame = CGRect(x: 100, y: 400, width: 600, height: limits.height(lines: 3))
    let result = PanelGeometry.resizeFloating(frame, edges: [.right, .bottom], dx: 80, dy: -68, limits: limits)
    #expect(result.lines == 5)
    #expect(result.frame.width == 680)
    #expect(result.frame.minX == frame.minX)
    #expect(result.frame.maxY == frame.maxY)   // the top stays put
    #expect(result.frame.height == limits.height(lines: 5))
}

@Test func floatingLeftAndTopEdgesKeepTheRightAndBottomPut() {
    let frame = CGRect(x: 100, y: 400, width: 600, height: limits.height(lines: 3))
    let left = PanelGeometry.resizeFloating(frame, edges: .left, dx: -40, dy: 0, limits: limits)
    #expect(left.frame.maxX == frame.maxX)
    #expect(left.frame.width == 640)
    let top = PanelGeometry.resizeFloating(frame, edges: .top, dx: 0, dy: 34, limits: limits)
    #expect(top.lines == 4)
    #expect(top.frame.minY == frame.minY)
}

@Test func clampPullsAWindowBackOnScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let offRight = PanelGeometry.clamp(CGRect(x: 1400, y: 300, width: 600, height: 200), to: screen)
    #expect(offRight.maxX == screen.maxX)
    let aboveTop = PanelGeometry.clamp(CGRect(x: 100, y: 900, width: 600, height: 200), to: screen)
    #expect(aboveTop.maxY == screen.maxY)
    let tooBig = PanelGeometry.clamp(CGRect(x: 50, y: 50, width: 2000, height: 1200), to: screen)
    #expect(tooBig.minX == 0)
    #expect(tooBig.maxY == screen.maxY)   // the top band stays reachable
}

@Test func aDraggedEdgeStopsAtTheScreenSoTheOppositeEdgeStaysPut() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let frame = CGRect(x: 600, y: 300, width: 820, height: limits.height(lines: 3))
    let right = PanelGeometry.resizeFloating(frame, edges: .right, dx: 100, dy: 0, limits: limits, within: screen)
    #expect(right.frame.minX == 600)
    #expect(right.frame.maxX == 1440)
    let bottom = PanelGeometry.resizeFloating(frame, edges: .bottom, dx: 0, dy: -5000, limits: limits, within: screen)
    #expect(bottom.frame.maxY == frame.maxY)
    #expect(bottom.frame.minY >= 0)
    let left = CGRect(x: 40, y: 300, width: 820, height: limits.height(lines: 3))
    let leftward = PanelGeometry.resizeFloating(left, edges: .left, dx: -100, dy: 0, limits: limits, within: screen)
    #expect(leftward.frame.maxX == left.maxX)
    #expect(leftward.frame.minX == 0)
}
