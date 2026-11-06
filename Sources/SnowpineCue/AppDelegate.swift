import AppKit
import Carbon.HIToolbox
import Combine
import SnowpineCueCore
import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings: Settings
    lazy var model = PrompterModel(settings: settings, document: WelcomeScript.document)

    private var panel: PrompterPanel!
    private var hostingView: PrompterHostingView!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var scrollTotal: CGFloat = 0
    private var topBand: CGFloat = 32
    /// `--launch-check` starts the app without showing the strip, reports, and quits (used by CI).
    private let isLaunchCheck = CommandLine.arguments.contains("--launch-check")

    init(settings: Settings = Settings()) {
        self.settings = settings
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        hostingView.menuBandHeight = topBand
        panel.contentView = hostingView
    }

    private func applySettings() {
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

    @objc private func screensChanged() { placePanel() }

    /// Centers the strip at the top of the screen with a notch (the built-in display),
    /// or just under the menu bar on screens without one.
    private func placePanel() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let notch = screen.safeAreaInsets.top
        let band = notch > 0 ? notch : 26
        if band != topBand {
            topBand = band
            hostingView.menuBandHeight = band
            hostingView.rootView = PrompterView(model: model, settings: settings, topBand: band)
        }
        let width = min(CGFloat(settings.panelWidth), screen.frame.width - 40)
        let height = band + CGFloat(settings.visibleLines) * settings.lineHeight + 14
        let top = notch > 0 ? screen.frame.maxY : screen.visibleFrame.maxY
        panel.setFrame(NSRect(x: (screen.frame.midX - width / 2).rounded(), y: top - height, width: width, height: height),
                       display: true)
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
        menu.addItem(submenu("Text Size", [
            item("Larger", #selector(fontLarger)),
            item("Smaller", #selector(fontSmaller)),
        ]))
        menu.addItem(submenu("Width", [
            item("Wider", #selector(wider)),
            item("Narrower", #selector(narrower)),
        ]))
        menu.addItem(submenu("Lines", (2...6).map { count in
            let it = item("\(count)", #selector(setLines(_:)), state: settings.visibleLines == count)
            it.tag = count
            return it
        }))
        menu.addItem(submenu("Scroll Speed", [
            item("\(Int(settings.wordsPerMinute)) words a minute, when not following your voice", nil, enabled: false),
            item("Faster", #selector(faster)),
            item("Slower", #selector(slower)),
        ]))
        menu.addItem(.separator())

        menu.addItem(item("Audio stays on this Mac. Nothing is recorded.", nil, enabled: false))
        menu.addItem(item("About Snowpine Cue", #selector(about)))
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
    @objc private func faster() { settings.adjustSpeed(by: 15) }
    @objc private func slower() { settings.adjustSpeed(by: -15) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showWelcome() { model.load(WelcomeScript.document, from: nil) }

    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A teleprompter under your camera that follows your voice. Speech is recognized on this Mac; audio is never recorded or sent anywhere.\n\nMade by Snowpine Code. Free and open source under the MIT License. snowpinecode.com"),
        ])
    }

    @objc private func openScript() {
        NSApp.activate()
        let open = NSOpenPanel()
        var types: [UTType] = [.plainText, .text, .html, .rtf, .rtfd]
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
