import AppKit
import SnowpineCueCore

/// `SnowpineCue --window-check`: sets up the real panel without showing it, then feeds the real
/// mouse handling simulated presses and drags, and checks where the window ends up: resizing
/// the strip, a click to start and pause, the speed menu, the floating window, moving it and
/// resizing it from a corner. Uses its own settings, never the user's, and never the microphone.
enum WindowCheck {
    @MainActor
    static func run() -> Int32 {
        let suite = "snowpine-cue.window-check"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        guard let defaults = UserDefaults(suiteName: suite) else { return fail(["no defaults"]) }
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else {
            print("WINDOW SKIP: no screen attached")
            return 0
        }

        let settings = Settings(defaults: defaults)
        settings.followVoice = false  // so a click scrolls instead of starting the microphone
        settings.showPrompter = false  // the panel is never put on screen
        let app = AppDelegate(settings: settings)
        app.setUpForChecks()
        let panel: NSPanel = app.panel
        let view: PrompterHostingView = app.hostingView
        var problems: [String] = []
        func expect(_ ok: Bool, _ message: @autoclosure () -> String) { if !ok { problems.append(message()) } }

        // The strip: drag the right side out 60 points. Both sides move, so it stays centered.
        let strip = panel.frame
        drag(view, panel, from: NSPoint(x: strip.width - 3, y: strip.height / 2), by: NSPoint(x: 60, y: 0))
        expect(panel.frame.width == strip.width + 120, "strip width \(panel.frame.width), expected \(strip.width + 120)")
        expect(abs(panel.frame.midX - strip.midX) <= 1, "strip moved off center: \(panel.frame.midX) vs \(strip.midX)")

        // The strip: drag the bottom down two lines. The top stays under the camera.
        let lines = settings.stripLines
        drag(view, panel, from: NSPoint(x: panel.frame.width / 2 - 80, y: 3), by: NSPoint(x: 0, y: -2 * settings.lineHeight))
        expect(settings.stripLines == lines + 2, "strip lines \(settings.stripLines), expected \(lines + 2)")
        expect(panel.frame.maxY == strip.maxY, "strip top moved: \(panel.frame.maxY) vs \(strip.maxY)")
        let stripAfter = (width: panel.frame.width, lines: settings.stripLines)

        // A click starts scrolling and a second one pauses.
        click(view, panel, at: NSPoint(x: panel.frame.width / 2 - 120, y: panel.frame.height / 2))
        expect(app.model.mode == .scrolling, "a click did not start scrolling (\(app.model.mode))")
        click(view, panel, at: NSPoint(x: panel.frame.width / 2 - 120, y: panel.frame.height / 2))
        expect(app.model.mode == .paused, "a second click did not pause (\(app.model.mode))")

        // Scroll Speed > Faster raises the speed by 10 and says so in the strip.
        let speed = settings.wordsPerMinute
        perform("Faster", in: "Scroll Speed", of: app.makeMenu())
        expect(settings.wordsPerMinute == speed + 10, "speed \(settings.wordsPerMinute), expected \(speed + 10)")
        expect(app.model.statusText == "Speed \(Int(speed + 10)) wpm", "speed notice was \"\(app.model.statusText)\"")

        // Floating Window: a larger window of its own size, away from the notch.
        perform("Floating Window", in: nil, of: app.makeMenu())
        app.applySettings()
        let float = panel.frame
        expect(settings.floating, "Floating Window did not switch on")
        expect(view.dragMoves && view.resizableEdges == .all, "the floating window is not movable and resizable")
        expect(float.width == CGFloat(settings.floatWidth), "floating width \(float.width), expected \(settings.floatWidth)")
        expect(float.height > strip.height, "floating window \(float.height) high is not larger than the strip (\(strip.height))")

        // Drag the floating window by its middle: it moves, and remembers where it was left.
        // The moves and resizes go toward the side with room, so they work on any screen size.
        let room = NSScreen.screens.first(where: { $0.frame.intersects(float) })?.frame ?? float
        let moveX: CGFloat = float.maxX + 60 <= room.maxX ? 60 : -60
        drag(view, panel, from: NSPoint(x: float.width / 2 - 100, y: float.height / 2), by: NSPoint(x: moveX, y: -60))
        let moved = panel.frame
        expect(moved.minX == float.minX + moveX && moved.minY == float.minY - 60,
               "move ended at \(moved.origin), expected \(NSPoint(x: float.minX + moveX, y: float.minY - 60))")
        expect(settings.floatTopLeft == CGPoint(x: moved.minX, y: moved.maxY), "the new position was not saved")
        expect(app.model.mode == .paused, "dragging the window also started or paused the prompter")

        // Drag a bottom corner: wider and two lines taller, with the top and the opposite side put.
        let floatLines = settings.floatLines
        let growRight = moved.maxX + 100 <= room.maxX
        let corner = NSPoint(x: growRight ? moved.width - 3 : 3, y: 3)
        drag(view, panel, from: corner, by: NSPoint(x: growRight ? 100 : -100, y: -2 * settings.lineHeight))
        expect(panel.frame.width == moved.width + 100, "floating width \(panel.frame.width), expected \(moved.width + 100)")
        expect(settings.floatLines == floatLines + 2, "floating lines \(settings.floatLines), expected \(floatLines + 2)")
        let keptSide = growRight ? panel.frame.minX == moved.minX : panel.frame.maxX == moved.maxX
        expect(keptSide && panel.frame.maxY == moved.maxY, "the opposite corner moved while resizing: \(moved) to \(panel.frame)")

        // Back to the strip, which kept its own size.
        perform("Floating Window", in: nil, of: app.makeMenu())
        app.applySettings()
        expect(!settings.floating, "Floating Window did not switch off")
        expect(panel.frame.width == stripAfter.width && settings.stripLines == stripAfter.lines,
               "the strip came back at \(panel.frame.width) wide with \(settings.stripLines) lines")
        expect(panel.frame.maxY == strip.maxY, "the strip came back away from the top")

        // Switching back to the strip in the middle of a move puts the strip under the camera
        // and leaves the floating window's saved place alone.
        perform("Floating Window", in: nil, of: app.makeMenu())
        app.applySettings()
        let savedPlace = settings.floatTopLeft
        drag(view, panel, from: NSPoint(x: panel.frame.width / 2 - 100, y: panel.frame.height / 2), by: NSPoint(x: 200, y: -150)) {
            perform("Floating Window", in: nil, of: app.makeMenu())
            app.applySettings()
        }
        expect(!settings.floating, "Floating Window did not switch off mid-move")
        expect(panel.frame.maxY == strip.maxY && panel.frame.width == stripAfter.width,
               "after a mid-move switch the strip is at \(panel.frame)")
        expect(!view.dragMoves && view.resizableEdges == [.left, .right, .bottom], "the strip kept the floating window's mouse handling")
        expect(settings.floatTopLeft == savedPlace, "a move cut short by the switch still saved a new place")

        // A size too big for the screen shrinks to fit, with the text laid out for the width shown.
        let home = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        settings.stripFontSize = 64
        settings.stripLines = 10
        settings.stripWidth = 2400
        app.applySettings()
        expect(panel.frame.minY >= home.visibleFrame.minY, "a large strip runs off the screen (bottom at \(panel.frame.minY))")
        expect(settings.textWidth == panel.frame.width - 2 * Settings.horizontalPadding,
               "strip text laid out \(settings.textWidth) wide in a \(panel.frame.width) window")
        perform("Floating Window", in: nil, of: app.makeMenu())
        settings.floatWidth = 2400
        settings.floatLines = 24
        app.applySettings()
        let shown = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) })?.frame ?? home.frame
        expect(shown.contains(panel.frame), "a large floating window runs off its screen: \(panel.frame) on \(shown)")
        expect(settings.textWidth == panel.frame.width - 2 * Settings.horizontalPadding,
               "floating text laid out \(settings.textWidth) wide in a \(panel.frame.width) window")

        guard problems.isEmpty else { return fail(problems) }
        print("WINDOW OK strip=\(Int(stripAfter.width))x\(stripAfter.lines) floating=\(Int(settings.floatWidth))x\(settings.floatLines) speed=\(Int(settings.wordsPerMinute))")
        return 0
    }

    // MARK: Simulated mouse

    /// Presses at a point in the window, moves in a few steps, and lets go, as a person would.
    /// `midway` runs halfway through, while the button is still down.
    @MainActor
    private static func drag(_ view: NSView, _ window: NSWindow, from point: NSPoint, by delta: NSPoint,
                             midway: (() -> Void)? = nil) {
        let start = window.convertPoint(toScreen: point)
        view.mouseDown(with: event(.leftMouseDown, at: start, in: window))
        let steps = 6
        for step in 1...steps {
            if step == steps / 2 + 1 { midway?() }
            let fraction = CGFloat(step) / CGFloat(steps)
            let screen = NSPoint(x: start.x + delta.x * fraction, y: start.y + delta.y * fraction)
            view.mouseDragged(with: event(.leftMouseDragged, at: screen, in: window))
        }
        view.mouseUp(with: event(.leftMouseUp, at: NSPoint(x: start.x + delta.x, y: start.y + delta.y), in: window))
    }

    @MainActor
    private static func click(_ view: NSView, _ window: NSWindow, at point: NSPoint) {
        let screen = window.convertPoint(toScreen: point)
        view.mouseDown(with: event(.leftMouseDown, at: screen, in: window))
        view.mouseUp(with: event(.leftMouseUp, at: screen, in: window))
    }

    /// A mouse event at a screen point, located relative to where the window is now.
    @MainActor
    private static func event(_ type: NSEvent.EventType, at screen: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: window.convertPoint(fromScreen: screen), modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// Chooses a menu item by its title, as a click would.
    @MainActor
    private static func perform(_ title: String, in submenu: String?, of menu: NSMenu) {
        let items = submenu.flatMap { name in menu.items.first { $0.title == name }?.submenu?.items } ?? menu.items
        guard let item = items.first(where: { $0.title == title }), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    private static func fail(_ problems: [String]) -> Int32 {
        for problem in problems { FileHandle.standardError.write(Data("WINDOW FAIL: \(problem)\n".utf8)) }
        return 1
    }
}
