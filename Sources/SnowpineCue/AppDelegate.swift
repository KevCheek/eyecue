import AppKit
import Carbon.HIToolbox
import Combine
import SnowpineCueCore
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings: Settings
    lazy var model = PrompterModel(settings: settings, document: WelcomeScript.document)

    private(set) var panel: PrompterPanel!
    private(set) var hostingView: PrompterHostingView!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var scrollTotal: CGFloat = 0
    private var topBand: CGFloat = 32
    private var viewIsFloating = false
    /// Where a resize or move started.
    private var drag: (frame: NSRect, width: Double, lines: Int, limits: PanelLimits, moving: Bool, floating: Bool)?
    /// `--launch-check` starts the app without showing the strip, reports, and quits (used by CI).
    private let isLaunchCheck = CommandLine.arguments.contains("--launch-check")
    /// `--update-check` reads the update feed with no menu bar icon, strip or hotkeys, reports, and quits.
    private let isUpdateCheck = CommandLine.arguments.contains("--update-check")
    private var updateCheck: AnyObject?
    private lazy var updater: Updater = MainActor.assumeIsolated { Updater() }
    /// `--render-docs` draws the menu as a packaged app shows it, with the update items.
    var showUpdateItemsForDocs = false

    init(settings: Settings = Settings()) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isUpdateCheck {
            MainActor.assumeIsolated {
                let check = UpdateCheck()
                updateCheck = check
                check.run()
            }
            return
        }
        setUpStatusItem()
        setUpPanel()
        registerHotKeys()
        model.onProblem = { [weak self] message in self?.showProblem(message) }

        settings.objectWillChange
            .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        applySettings()
        if !isLaunchCheck { updater.start(checkNow: true) }

        if isLaunchCheck {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                let sandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
                print("LAUNCH \(sandboxed && BrandFonts.allLoaded ? "OK" : "FAIL") lines=\(model.lines.count) words=\(model.spokenCount) sandboxed=\(sandboxed)")
                fflush(stdout)
                exit(sandboxed ? 0 : 1)  // the packaged app must run in the App Sandbox
            }
        }
    }

    // MARK: Panel

    private func setUpPanel() {
        panel = PrompterPanel()
        hostingView = PrompterHostingView(rootView: PrompterView(model: model, settings: settings, topBand: topBand))
        hostingView.onScroll = { [weak self] delta in self?.scrolled(delta) }
        hostingView.onClick = { [weak self] in self?.model.toggle() }
        hostingView.makeMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        hostingView.onDragBegan = { [weak self] edges in self?.dragBegan(edges) }
        hostingView.onDrag = { [weak self] edges, dx, dy in self?.dragged(edges, dx, dy) }
        hostingView.onDragEnded = { [weak self] in self?.dragEnded() }
        hostingView.menuBandHeight = topBand
        panel.contentView = hostingView
    }

    /// Sets up the panel without showing it, for `--window-check`.
    func setUpForChecks() {
        setUpPanel()
        applySettings()
    }

    func applySettings() {
        fitToScreen()  // before the layout, so the text is laid out for the width actually shown
        model.relayout()
        model.settingsChanged()
        panel.setHiddenFromCapture(settings.hideFromSharing)
        placePanel()
        if settings.showPrompter && !isLaunchCheck {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    @objc private func screensChanged() { applySettings() }

    /// The screen with the camera notch (the built-in display), or the main screen.
    private var homeScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The room the prompter has: the strip from the top of its screen down to the Dock,
    /// the floating window the whole screen it is on.
    private func space() -> (width: CGFloat, height: CGFloat, band: CGFloat)? {
        if settings.floating {
            guard let home = homeScreen else { return nil }
            let bounds = screen(for: savedFloatingFrame(home: home))?.frame ?? home.frame
            return (bounds.width, bounds.height, Settings.floatingBand)
        }
        guard let screen = homeScreen else { return nil }
        let notch = screen.safeAreaInsets.top
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        return (screen.frame.width - 40, top - screen.visibleFrame.minY - 12, notch > 0 ? notch : 26)
    }

    /// Keeps the saved size within the screen, so every edge stays reachable. A size saved on a
    /// bigger screen shrinks to fit the one in use.
    private func fitToScreen() {
        guard let room = space() else { return }
        let limits = settings.limits(band: room.band, maxWidth: room.width, maxHeight: room.height)
        if CGFloat(settings.panelWidth) > limits.width.upperBound { settings.panelWidth = Double(limits.width.upperBound) }
        if settings.visibleLines > limits.lines.upperBound { settings.visibleLines = limits.lines.upperBound }
    }

    private func placePanel() {
        // A move in progress owns the frame, as long as the button is still down and the mode hasn't changed.
        if let drag, drag.moving, drag.floating == settings.floating, NSEvent.pressedMouseButtons & 1 == 1 { return }
        guard let frame = settings.floating ? floatingFrame() : stripFrame() else { return }
        panel.setFrame(frame, display: true)
    }

    /// Rebuilds the view when the top band or the shape changes.
    private func useBand(_ band: CGFloat) {
        hostingView.resizableEdges = settings.floating ? .all : [.left, .right, .bottom]
        hostingView.dragMoves = settings.floating
        guard band != topBand || settings.floating != viewIsFloating else { return }
        topBand = band
        viewIsFloating = settings.floating
        hostingView.menuBandHeight = band
        hostingView.rootView = PrompterView(model: model, settings: settings, topBand: band)
    }

    /// Centers the strip at the top of the screen with a notch (the built-in display),
    /// or just under the menu bar on screens without one.
    private func stripFrame() -> NSRect? {
        guard let screen = homeScreen else { return nil }
        let notch = screen.safeAreaInsets.top
        useBand(notch > 0 ? notch : 26)
        let width = min(CGFloat(settings.panelWidth), screen.frame.width - 40)
        let height = settings.panelHeight(band: topBand)
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        return NSRect(x: (screen.frame.midX - width / 2).rounded(), y: top - height, width: width, height: height)
    }

    /// The floating window at its saved place and size. The first time, it opens near the top
    /// of the screen with the camera.
    private func savedFloatingFrame(home: NSScreen) -> NSRect {
        let width = CGFloat(settings.floatWidth)
        let height = settings.panelHeight(band: Settings.floatingBand)
        let topLeft = settings.floatTopLeft
            ?? CGPoint(x: (home.visibleFrame.midX - width / 2).rounded(), y: home.visibleFrame.maxY - 48)
        return NSRect(x: topLeft.x, y: topLeft.y - height, width: width, height: height)
    }

    /// The floating window where it was left, kept on a screen.
    private func floatingFrame() -> NSRect? {
        guard let home = homeScreen else { return nil }
        useBand(Settings.floatingBand)
        let saved = savedFloatingFrame(home: home)
        let bounds = screen(for: saved)?.frame ?? home.frame
        // fitToScreen has already made it fit; this only guards against a screen change since then.
        let frame = NSRect(x: saved.minX, y: saved.maxY - min(saved.height, bounds.height),
                           width: min(saved.width, bounds.width), height: min(saved.height, bounds.height))
        return PanelGeometry.clamp(frame, to: bounds)
    }

    /// The screen the floating window is on: the one under its top band, else the one it overlaps most.
    private func screen(for frame: NSRect) -> NSScreen? {
        let grab = NSPoint(x: frame.midX, y: frame.maxY - 10)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(grab) }) { return screen }
        let overlaps = NSScreen.screens.map { ($0, $0.frame.intersection(frame)) }.filter { !$0.1.isNull }
        return overlaps.max(by: { $0.1.width * $0.1.height < $1.1.width * $1.1.height })?.0
    }

    // MARK: Resize and move

    private func dragBegan(_ edges: ResizeEdges) {
        let room = space() ?? (CGFloat(Settings.widthRange.upperBound), 10_000, topBand)
        drag = (panel.frame, settings.panelWidth, settings.visibleLines,
                settings.limits(band: topBand, maxWidth: room.width, maxHeight: room.height),
                edges.isEmpty, settings.floating)
    }

    private func dragged(_ edges: ResizeEdges, _ dx: CGFloat, _ dy: CGFloat) {
        // Ignore the rest of a drag that began before a switch between the strip and the floating window.
        guard let start = drag, start.floating == settings.floating else { return }
        if edges.isEmpty {
            guard settings.floating else { return }
            panel.setFrameOrigin(NSPoint(x: (start.frame.minX + dx).rounded(), y: (start.frame.minY + dy).rounded()))
            return
        }
        if settings.floating {
            let result = PanelGeometry.resizeFloating(start.frame, edges: edges, dx: dx, dy: dy, limits: start.limits)
            settings.floatTopLeft = CGPoint(x: result.frame.minX, y: result.frame.maxY)
            if settings.floatWidth != Double(result.frame.width) { settings.floatWidth = Double(result.frame.width) }
            if settings.floatLines != result.lines { settings.floatLines = result.lines }
        } else {
            let result = PanelGeometry.resizeStrip(width: CGFloat(start.width), lines: start.lines, edges: edges,
                                                   dx: dx, dy: dy, limits: start.limits)
            if settings.stripWidth != Double(result.width) { settings.stripWidth = Double(result.width) }
            if settings.stripLines != result.lines { settings.stripLines = result.lines }
        }
        // Follow the pointer now rather than after the settings debounce.
        model.relayout()
        placePanel()
    }

    private func dragEnded() {
        let ended = drag
        drag = nil
        // Save where the floating window was left, unless the mode changed during the move.
        if let ended, ended.moving, ended.floating, settings.floating {
            let frame = panel.frame
            let bounds = screen(for: frame)?.frame ?? homeScreen?.frame ?? frame
            let kept = PanelGeometry.clamp(frame, to: bounds)
            settings.floatTopLeft = CGPoint(x: kept.minX, y: kept.maxY)
        }
        applySettings()
    }

    private func scrolled(_ delta: CGFloat) {
        scrollTotal += delta
        let step: CGFloat = 18
        while scrollTotal <= -step { model.moveLines(1); scrollTotal += step }
        while scrollTotal >= step { model.moveLines(-1); scrollTotal -= step }
    }

    // MARK: Shortcuts

    private func registerHotKeys() {
        HotKeys.register(keyCode: kVK_ANSI_P) { [weak self] in self?.model.toggle() }
        HotKeys.register(keyCode: kVK_ANSI_R) { [weak self] in self?.model.restart() }
        HotKeys.register(keyCode: kVK_DownArrow) { [weak self] in self?.model.moveLines(1) }
        HotKeys.register(keyCode: kVK_UpArrow) { [weak self] in self?.model.moveLines(-1) }
        HotKeys.register(keyCode: kVK_ANSI_H) { [weak self] in self?.settings.showPrompter.toggle() }
        HotKeys.register(keyCode: kVK_RightArrow) { [weak self] in self?.faster() }
        HotKeys.register(keyCode: kVK_LeftArrow) { [weak self] in self?.slower() }
        HotKeys.register(keyCode: kVK_ANSI_F) { [weak self] in self?.toggleFloating() }
    }

    // MARK: Menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = MenuBarIcon.make()
            button.toolTip = "Snowpine Cue"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
    }

    /// A fresh copy of the menu, for the right-click on the strip and for the README pictures.
    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuNeedsUpdate(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let dragHint = settings.floating ? "Or drag the window's edges" : "Or drag the strip's sides and bottom"

        menu.addItem(item(model.isRunning ? "Pause" : "Start", #selector(toggleRunning), key: "p", mods: [.control, .option]))
        menu.addItem(item("Back to Start", #selector(backToStart), key: "r", mods: [.control, .option]))
        menu.addItem(item("Next Line", #selector(nextLine), key: down, mods: [.control, .option]))
        menu.addItem(item("Previous Line", #selector(previousLine), key: up, mods: [.control, .option]))
        menu.addItem(.separator())

        menu.addItem(item("Script: \(model.title)", nil, enabled: false))
        menu.addItem(item("Open Script\u{2026}", #selector(openScript)))
        menu.addItem(item("Paste Script from Clipboard", #selector(pasteScript)))
        menu.addItem(item("Reload Script", #selector(reloadScript), enabled: model.sourceURL != nil))
        menu.addItem(item("Show Welcome Guide", #selector(showWelcome)))
        menu.addItem(.separator())

        menu.addItem(item("Follow My Voice", #selector(toggleFollowVoice), state: settings.followVoice))
        menu.addItem(item("Hide from Screen Sharing", #selector(toggleHideFromSharing), state: settings.hideFromSharing))
        menu.addItem(item("Show Prompter", #selector(toggleShowPrompter), key: "h", mods: [.control, .option], state: settings.showPrompter))
        menu.addItem(item("Floating Window", #selector(toggleFloating), key: "f", mods: [.control, .option], state: settings.floating))
        menu.addItem(submenu("Text Size", [
            item("Larger", #selector(fontLarger)),
            item("Smaller", #selector(fontSmaller)),
        ]))
        menu.addItem(submenu("Width", [
            item("Wider", #selector(wider)),
            item("Narrower", #selector(narrower)),
            .separator(),
            item(dragHint, nil, enabled: false),
        ]))
        let lineChoices = settings.lineRange.lowerBound...min(settings.lineRange.upperBound, 12)
        menu.addItem(submenu("Lines", lineChoices.map { count in
            let it = item("\(count)", #selector(setLines(_:)), state: settings.visibleLines == count)
            it.tag = count
            return it
        } + [.separator(), item(dragHint, nil, enabled: false)]))
        let slider = NSMenuItem()
        slider.view = SpeedSliderView(value: settings.wordsPerMinute, range: Settings.speedRange) { [weak self] value in
            self?.settings.setSpeed(value)
        }
        menu.addItem(submenu("Scroll Speed", [
            slider,
            item("Faster", #selector(faster), key: right, mods: [.control, .option]),
            item("Slower", #selector(slower), key: left, mods: [.control, .option]),
            .separator(),
            item("Used when Follow My Voice is off", nil, enabled: false),
        ]))
        menu.addItem(.separator())

        menu.addItem(item("Audio and scripts stay on this Mac.", nil, enabled: false))
        menu.addItem(item("About Snowpine Cue", #selector(about)))
        if updater.isAvailable || showUpdateItemsForDocs {
            menu.addItem(item("Check for Updates\u{2026}", #selector(checkForUpdates), enabled: updater.canCheckForUpdates || showUpdateItemsForDocs))
            menu.addItem(item("Check for Updates Automatically", #selector(toggleAutomaticUpdates), state: updater.automaticallyChecks || showUpdateItemsForDocs))
        }
        menu.addItem(item("Quit Snowpine Cue", #selector(quit), key: "q", mods: [.command]))
    }

    private func item(_ title: String, _ action: Selector?, key: String = "", mods: NSEvent.ModifierFlags = [],
                      state: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.target = self
        it.isEnabled = enabled
        if let state { it.state = state ? .on : .off }
        return it
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        parent.submenu = menu
        return parent
    }

    // MARK: Actions

    @objc private func toggleRunning() { model.toggle() }
    @objc private func backToStart() { model.restart() }
    @objc private func nextLine() { model.moveLines(1) }
    @objc private func previousLine() { model.moveLines(-1) }
    @objc private func toggleFollowVoice() { model.pause(); settings.followVoice.toggle() }
    @objc private func toggleHideFromSharing() {
        settings.hideFromSharing.toggle()
        // Apply at once rather than after the settings debounce, so the strip is never capturable while ticked.
        panel.setHiddenFromCapture(settings.hideFromSharing)
    }
    @objc private func toggleShowPrompter() { settings.showPrompter.toggle() }
    @objc private func fontLarger() { settings.adjustFontSize(by: 2) }
    @objc private func fontSmaller() { settings.adjustFontSize(by: -2) }
    @objc private func wider() { settings.adjustWidth(by: 40) }
    @objc private func narrower() { settings.adjustWidth(by: -40) }
    @objc private func setLines(_ sender: NSMenuItem) { settings.visibleLines = sender.tag }
    @objc private func faster() { changeSpeed(by: 10) }
    @objc private func slower() { changeSpeed(by: -10) }
    @objc private func toggleFloating() { settings.floating.toggle() }

    private func changeSpeed(by delta: Double) {
        settings.adjustSpeed(by: delta)
        let speed = Int(settings.wordsPerMinute)
        // Kept short: on a MacBook the left of the top band is beside the notch.
        model.flash(settings.followVoice ? "Manual speed \(speed) wpm" : "Speed \(speed) wpm")
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showWelcome() { model.load(WelcomeScript.document, from: nil) }

    @MainActor @objc private func checkForUpdates() { updater.checkForUpdates() }
    @MainActor @objc private func toggleAutomaticUpdates() { updater.automaticallyChecks.toggle() }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A teleprompter under your camera that follows your voice. Speech is recognized on this Mac; audio and scripts are never recorded or sent anywhere. The only network use is checking GitHub for updates.\n\nMade by Snowpine Code. Free and open source under the MIT License. snowpinecode.com"),
        ])
    }

    @objc private func openScript() {
        NSApp.activate()
        let open = NSOpenPanel()
        var types: [UTType] = [.plainText, .text, .html, .rtf]
        for ext in ["md", "markdown", "docx", "doc", "odt"] {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        open.allowedContentTypes = types
        open.allowsMultipleSelection = false
        open.message = "Choose a script: text, Markdown, Word, RTF, or a slide deck HTML file with speaker notes."
        guard open.runModal() == .OK, let url = open.url else { return }
        load(url)
    }

    @objc private func reloadScript() {
        guard let url = model.sourceURL else { return }
        load(url)
    }

    @objc private func pasteScript() {
        guard let text = NSPasteboard.general.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showProblem("The clipboard has no text to use as a script.")
            return
        }
        model.pause()
        do {
            try ScriptLoader.checkLength(text)
        } catch {
            showProblem(error.localizedDescription)
            return
        }
        model.load(ScriptDocument.parse(text, format: .markdown, title: "Pasted script"), from: nil)
    }

    private func load(_ url: URL) {
        model.pause()  // the microphone goes off before a file is read
        do {
            model.load(try ScriptLoader.load(url), from: url)
        } catch {
            showProblem("Couldn't open \(url.lastPathComponent). \(error.localizedDescription)")
        }
    }

    private func showProblem(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Snowpine Cue"
        alert.informativeText = message
        alert.runModal()
    }
}
