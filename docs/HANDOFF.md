# EyeCue 0.1.0: handoff

EyeCue is a free, open-source Mac teleprompter. It shows your script in a small strip under the
MacBook camera, follows your voice with on-device speech recognition, and hides itself from screen
sharing. It is sandboxed with no network access.

- **Code:** https://github.com/KevCheek/eyecue (public, MIT license, copyright Kevin Cheek). This file is `docs/HANDOFF.md` in it.
- **Download:** on the GitHub page, Code > Download ZIP gives the source without Git history.

## 1. Take it over

Pick one:

- **Transfer the repository** to your company's GitHub organization: on GitHub, open the repo, then
  Settings > General > Danger Zone > Transfer ownership. Issues, stars and settings move with it,
  and the old link redirects. Best if the company should own the project.
- **Fork it** into the company's organization. The original stays on KevCheek and the fork links
  back to it.
- **Start fresh** from the downloaded zip (no Git history):
  ```bash
  cd eyecue-main   # the folder GitHub's zip unpacks to
  git init -b main && git add . && git commit -m "EyeCue 0.1.0"
  git remote add origin https://github.com/OWNER/eyecue.git
  git push -u origin main
  ```

To keep a company name off the public page, publish under an organization named after the app
(`eyecue-app` was free on Nov 5, 2026) whose profile shows only the app.

## 2. Build it (about a minute)

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
scripts/test.sh                  # 23 tests, the no-network check, a render check
scripts/build-app.sh --install   # builds EyeCue and moves it to ~/Applications
```

## 3. Brand it

| What | Where |
| --- | --- |
| App name | `Resources/Info.plist` (CFBundleName, CFBundleDisplayName), menu titles in `Sources/EyeCue/AppDelegate.swift` |
| App icon | `Resources/AppIcon.png` (1024 x 1024, transparent corners); the build turns it into the .icns |
| Menu bar icon | `Sources/EyeCue/MenuBarIcon.swift` (drawn in code, 18 x 18 points, template image) |
| Strip colors | `Palette` in `Sources/EyeCue/PrompterView.swift` |
| Fonts | `Sources/EyeCue/Settings.swift` (Avenir Next by default) |
| Bundle ID | `BUNDLE_ID=com.yourcompany.EyeCue scripts/build-app.sh` (default `local.eyecue.EyeCue`) |
| Version | `VERSION=0.2.0 scripts/build-app.sh` |
| About box text | `about()` in `Sources/EyeCue/AppDelegate.swift` |
| Welcome guide | `WelcomeScript` in `Sources/EyeCue/ScriptLoader.swift` |
| Copyright | `LICENSE` (keep the MIT terms; change the holder if the company should own it) |
| README pictures | `EyeCue --render-docs docs` redraws them from the real strip, menu and icon |

## 4. Finish it

- **Live tests** with a person at the Mac: read a script aloud and check it keeps pace; share the
  whole screen in a Zoom test meeting and check the strip doesn't appear.
- **Store-style page:** several captioned screenshots and a short video with narration and music.
  GitHub only plays videos uploaded through its own editor, so either drag the video into
  README.md on github.com, or build a project page with GitHub Pages.
- **Downloadable app:** an Apple Developer ID ($99 a year) lets you sign and notarize a download
  that opens without warnings. Until then, people build from source.
- **iPhone version (idea):** the voice-following and script code in `Sources/EyeCueCore` has no
  Mac-only code and would carry over. It needs full Xcode and a new iPhone interface.

## Checked before handoff (Nov 5, 2026)

- 23 unit tests pass: voice following (straight reads, misheard words, skipped sentences, side
  talk), script parsing (Markdown, deck HTML with speaker notes), hostile files parsing quickly,
  and the microphone staying off after a pause.
- The built app runs in the App Sandbox with no network entitlement; the build fails if that changes.
- Secrets scan of the full history: none found.
- Independent security review (OpenAI Codex, read-only): no critical or high findings; every
  medium and low finding was fixed.
- GitHub: secret scanning, push protection, private vulnerability reporting and Dependabot alerts
  are on. CI runs the tests on every push; the first run passed on GitHub's Mac runners.
- Dependabot opened a pull request to update `actions/checkout` from 4.2.2 to 7.0.1. Merge it once
  its CI run passes, or close it.
