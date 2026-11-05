import AppKit
import EyeCueCore

if let flag = CommandLine.arguments.firstIndex(of: "--smoke-test") {
    let folder = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : FileManager.default.currentDirectoryPath
    let code = MainActor.assumeIsolated { SmokeTest.run(outputDirectory: folder) }
    exit(code)
}

if let flag = CommandLine.arguments.firstIndex(of: "--render-docs") {
    let folder = CommandLine.arguments.indices.contains(flag + 1) ? CommandLine.arguments[flag + 1] : "docs"
    let code = MainActor.assumeIsolated { DocsRenderer.run(outputDirectory: folder) }
    exit(code)
}

// `EyeCue --check-script <file>` shows how a script file will be read, without opening the app.
if let flag = CommandLine.arguments.firstIndex(of: "--check-script"), CommandLine.arguments.indices.contains(flag + 1) {
    let url = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    do {
        let document = try ScriptLoader.load(url)
        let prepared = PreparedScript(document)
        print("\(document.title): \(document.sections.count) sections, \(prepared.spokenCount) words")
        for section in document.sections.prefix(4) {
            print("  [\(section.heading ?? "no heading")] \(section.paragraphs.first?.prefix(90) ?? "")")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
