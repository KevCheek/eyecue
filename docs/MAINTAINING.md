# Maintaining Snowpine Cue

## Build and test
You need macOS 14 or later and the Xcode Command Line Tools.

```bash
scripts/test.sh                  # unit tests, the no-network check, a render check
scripts/build-app.sh --install   # builds the app and moves it to ~/Applications
```

## Where things live
| What | Where |
| --- | --- |
| App name | `Resources/Info.plist`, menu titles in `Sources/SnowpineCue/AppDelegate.swift` |
| App icon | `Resources/AppIcon.svg` and `Resources/AppIcon.png` (1024 x 1024, transparent corners) |
| Menu bar icon | `Sources/SnowpineCue/MenuBarIcon.swift` (drawn in code as a template image) |
| Strip colors | `Palette` in `Sources/SnowpineCue/PrompterView.swift` |
| Fonts | `Resources/Fonts`, loaded by `Sources/SnowpineCue/BrandFonts.swift` |
| Welcome guide | `WelcomeScript` in `Sources/SnowpineCue/ScriptLoader.swift` |
| README pictures | `SnowpineCue --render-docs docs` redraws them from the real strip, menu and icon |
| Web page | `site/`, published by `.github/workflows/pages.yml` |

## Publish a download
Set the version and push a tag, such as `v0.2.0`. `.github/workflows/release.yml` tests, builds and attaches the zip. The page links to `releases/latest/download/Snowpine-Cue.zip`, so it always gets the newest one.

## Check before every release
- Read a script aloud and check it keeps pace.
- Share the whole screen in a test call and check the strip doesn't show.
- Keep the privacy promises: no network access, no recording, on-device recognition only.
