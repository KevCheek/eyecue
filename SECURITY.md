# Security and privacy

EyeCue handles microphone audio, so its controls are about keeping that audio, and your scripts,
on your Mac. Each control below names where it is implemented, so it can be checked.

## Controls in place

| Control | Where |
| --- | --- |
| App Sandbox on, with no network entitlement: macOS blocks all network access | `Resources/EyeCue.entitlements` |
| Only the microphone and user-chosen files (read only) are granted | `Resources/EyeCue.entitlements` |
| Speech recognition is on-device only; no server fallback | `Sources/EyeCue/SpeechFollower.swift` (`requiresOnDeviceRecognition = true`, `supportsOnDeviceRecognition` check) |
| Audio buffers go straight to the recognizer and are never written to disk | `Sources/EyeCue/SpeechFollower.swift` |
| The microphone runs only while the prompter is running | `PrompterModel.start()` and `pause()` |
| No networking APIs in the code, checked in CI | `scripts/check-no-network.sh`, `.github/workflows/ci.yml` |
| Hardened runtime on the app signature | `scripts/build-app.sh` |
| No accounts, analytics, crash reporting or telemetry | the whole of `Sources/` |
| The strip is excluded from screen capture by default | `Sources/EyeCue/PrompterPanel.swift` (`sharingType = .none`) |

## What is stored

Only display settings (text size, width, lines, speed and toggles) in the app's sandboxed
preferences. Scripts are read when you open them and kept in memory; nothing is copied.

## Limits

Screen-capture exclusion depends on macOS and on the capturing app honoring it. Test with your own
call app before relying on it.

## Reporting a problem

Please open an issue for anything that is not sensitive. For a vulnerability, use the repository's
private vulnerability reporting (GitHub: Security > Report a vulnerability) instead of a public issue.
