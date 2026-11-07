# Maintaining Snowpine Cue

## Build and test
You need macOS 14 or later and the Xcode Command Line Tools.

```bash
scripts/test.sh                  # unit tests, the no-network check, a render check, the window check
scripts/build-app.sh --install   # builds the app and moves it to ~/Applications
```

Without a signing identity, `build-app.sh` signs the app ad hoc. That is fine for testing, but macOS
treats each ad-hoc build as a new app, so it asks for the microphone and speech permissions again.

### A build signed with the release certificate
Import the certificate (a .p12 file and a file holding its password) into a throwaway keychain, then
build with it. Your login keychain is not touched.

```bash
export SIGN_KEYCHAIN=$(scripts/import-signing-cert.sh cert.p12 cert-password.txt)
export SIGN_IDENTITY="Snowpine Code App Signing"
scripts/build-app.sh
security delete-keychain "$SIGN_KEYCHAIN"   # when you're done
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
| README pictures | `SnowpineCue --render-docs docs` redraws them from the real strip, menu, icon and floating window |
| Strip frames for the page and video | `SnowpineCue --render-frames <folder>` draws the strip once per word of a demo talk, plus `strip-900.png` scrolling at a set speed |
| Resize and move math | `PanelGeometry` in `Sources/SnowpineCueCore/PanelGeometry.swift` (unit tested); the mouse handling is `PrompterHostingView` |
| In-app updates | `Sources/SnowpineCue/Updater.swift` (the only file that imports Sparkle); feed URL, public key and check settings in `Resources/Info.plist` |
| Sparkle in the app bundle | `scripts/embed-sparkle.sh` copies the framework in and signs its parts. Sparkle's helpers keep Sparkle's own setup with no entitlements, and `scripts/build-app.sh` fails if any carries entitlements, on any architecture. Don't give the Downloader its own sandbox: that needs a Sparkle build with an app-specific service id, or it can clash with other apps that use Sparkle |
| The update feed | `scripts/make-appcast.sh` signs the zip with the EdDSA key and writes `build/appcast.xml` |
| Sparkle version | `Package.swift` (exact) and `scripts/sparkle-tools.sh` (`VERSION` and `SHA256` of the tools download). Change them together |
| Web page | `site/`, published by `.github/workflows/pages.yml` |

Builds go to `build/Products.noindex`, because Spotlight skips folders with that ending, so a build never shows up as a second copy of the app.

## Publish a download
Releasing needs three repository secrets (Settings > Secrets and variables > Actions):

| Secret | What it is |
| --- | --- |
| `CODESIGN_P12_BASE64` | The release certificate ("Snowpine Code App Signing") and its private key, as a base64 .p12 |
| `CODESIGN_P12_PASSWORD` | The .p12 password |
| `SPARKLE_ED_PRIVATE_KEY` | The EdDSA private key that signs updates. Its public half is `SUPublicEDKey` in `Resources/Info.plist` |

Set the version in `scripts/build-app.sh` and `scripts/package-release.sh` (the default for local
builds), then push a tag such as `v0.3.0`. `.github/workflows/release.yml` then:
1. runs the tests,
2. imports the certificate into a throwaway keychain,
3. builds a universal app signed with it (the build number is the UTC date and time, so each release counts as newer),
4. signs `Snowpine-Cue.zip` with the EdDSA key and writes `appcast.xml`,
5. attaches `Snowpine-Cue.zip`, `Snowpine-Cue.zip.sha256` and `appcast.xml` to the release, and deletes the keychain.

`https://github.com/snowpinecode/snowpine-cue/releases/latest/download/Snowpine-Cue.zip` always gets the newest
download, and installed copies read `.../releases/latest/download/appcast.xml` to find updates. So:
- Every release marked Latest must have `appcast.xml` attached, or update checks stop finding anything.
- Keep the same certificate and the same EdDSA key. A new certificate makes macOS ask for the microphone
  and speech permissions again; a new EdDSA key means installed copies refuse every update.
- Back up the .p12, its password and the EdDSA private key somewhere safe outside the repository.

## Check before every release
- Read a script aloud and check it keeps pace.
- Drag the strip's edges, then switch to the floating window, move it and resize it from a corner.
- Share the whole screen in a test call and check the strip doesn't show.
- Run `"build/Products.noindex/Snowpine Cue.app/Contents/MacOS/SnowpineCue" --update-check` on the packaged app: it reads the feed
  through Sparkle's Downloader helper, with no window, and reports what it found.
- After publishing, open the previous version, choose Check for Updates, install, and check that it
  relaunches as the new version with its settings and without asking for permissions again.
- Keep the privacy promises: no network access in the app itself (only Sparkle's Downloader, for
  updates), no recording, on-device recognition only.
