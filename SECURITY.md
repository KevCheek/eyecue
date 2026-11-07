# Security and privacy

Snowpine Cue handles microphone audio, so its controls are about keeping that audio, and your scripts,
on your Mac. Each control below names where it is implemented, so it can be checked.

## Controls in place

| Control | Where |
| --- | --- |
| App Sandbox on, with no network entitlement: macOS blocks the app's own network access | `Resources/SnowpineCue.entitlements` |
| In-app updates (Sparkle 2.10.1, pinned): the only network use. Sparkle's separate Downloader helper fetches the update feed and the update from GitHub, over https. Speech, audio and scripts are never part of it | `Sources/SnowpineCue/Updater.swift`, `Resources/Info.plist` |
| Turning off Check for Updates Automatically means no check starts unless you ask. While it is off, the app refuses background checks, including one already scheduled | `Sources/SnowpineCue/Updater.swift` |
| Every update must be signed with the EdDSA key matching `SUPublicEDKey`, checked before it is unpacked. Nothing installs without your click | `Resources/Info.plist`, `scripts/make-appcast.sh` |
| Sparkle's helpers (Downloader, Installer, Updater) ship exactly as Sparkle ships them, with no extra entitlements. They are not sandboxed: the Installer has to replace the app, and giving the shared Downloader its own sandbox can clash with other apps that use Sparkle | `scripts/embed-sparkle.sh` |
| Two extra entitlements, both for Sparkle: `cs.disable-library-validation` (to load its bundled framework without an Apple Team ID) and a mach-lookup exception for its two local services (`-spks`, `-spki`), which are connections between processes on the Mac, not network access | `Resources/SnowpineCue.entitlements` |
| Only the microphone and user-chosen files (read only) are granted | `Resources/SnowpineCue.entitlements` |
| Speech recognition is on-device only; no server fallback | `Sources/SnowpineCue/SpeechFollower.swift` (`requiresOnDeviceRecognition = true`, `supportsOnDeviceRecognition` check) |
| Audio buffers go straight to the recognizer and are never written to disk | `Sources/SnowpineCue/SpeechFollower.swift` |
| The microphone runs only while the prompter is running | `PrompterModel.start()` and `pause()` |
| No networking APIs in the app's code, Sparkle imported in one file only, and exactly this set of entitlements, checked in CI | `scripts/check-no-network.sh`, `.github/workflows/ci.yml` |
| The build checks the entitlements actually signed into the app are exactly that set on every architecture, and that Sparkle's helpers carry none | `scripts/build-app.sh` |
| Script files have limits on size, length and sections, and packages are refused | `Sources/SnowpineCue/ScriptLoader.swift` |
| Hardened runtime on the app signature. Releases are signed in CI with one certificate from repository secrets, in a throwaway keychain | `scripts/build-app.sh`, `scripts/import-signing-cert.sh`, `.github/workflows/release.yml` |
| Secret scan of the full history on every push (pinned gitleaks) | `.github/workflows/secret-scan.yml` |
| No accounts, analytics, crash reporting or telemetry. The update check sends GitHub only what any download does, and can be turned off | the whole of `Sources/` |
| The strip is excluded from screen capture by default | `Sources/SnowpineCue/PrompterPanel.swift` (`sharingType = .none`) |

The web page in `site/` is static: no scripts, cookies, analytics or forms, with a strict Content Security Policy.

## What is stored

Only display settings (text size, width, lines, speed and toggles) in the app's sandboxed
preferences. Scripts are read when you open them and kept in memory; nothing is copied.

## Limits

Screen-capture exclusion depends on macOS and on the capturing app honoring it. Test with your own
call app before relying on it. Update checks are on by default (at launch and once a day); turn them off in the menu. Without a paid Apple Developer ID, a downloaded copy shows a macOS warning the first time it opens (see the README).

## Reporting a problem

Please open an issue for anything that is not sensitive. For a vulnerability, use the repository's
private vulnerability reporting (GitHub: Security > Report a vulnerability) instead of a public issue.
