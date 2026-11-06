# Build log

## 2026-11-05: version 0.2.0

Rebranded for Snowpine Code: the Snowpine Cue name, bundle id com.snowpinecode.cue, brand 2.0 colors (black, white, neutral
greys, Pine Blue for the next word), Inter and Plus Jakarta Sans shipped in the app, a new icon reviewed by Codex, copyright
Snowpine Code LLC, a web page in site/, a narrated video, and a download built by CI. The smoke test and launch check now fail
if the brand fonts don't load.

Voice following no longer stalls when the recognizer adds or drops a word, and three dots on the strip open the menu.

Checked by a person at the Mac: voice following keeps pace live, the three dots work, and the strip stayed out of a real Zoom
share and its recording (macOS 27). Other call apps and macOS versions may differ. Not yet checked: the Open Anyway steps on a
downloaded copy.

## 2026-11-05: version 0.1.0

First build. A menu bar app that shows a teleprompter strip under the MacBook notch, follows the
speaker's voice with on-device speech recognition, and is excluded from screen capture.

Why build it: the notch teleprompters on the market either scroll at a fixed speed while they hear
sound (NotchPrompter, whose license is also personal and non-commercial only) or are closed source
with analytics. This one tracks the actual words, has no network access at all, and is open.

Verified on a MacBook Pro (M5, macOS 27.0.1) with the Command Line Tools only:
- `swift test`: 15 tests pass (straight read, misheard words, skipped sentence, side talk ignored,
  far repeated phrase not jumped to, numbers spoken either way, Markdown and deck HTML parsing, layout).
- `scripts/check-no-network.sh` passes.
- `--smoke-test` renders the strip (docs/screenshot.png comes from it).
- `scripts/build-app.sh` builds and signs the sandboxed app; `--launch-check` reports `sandboxed=true`.
- `--check-script` reads a real slide deck's speaker notes slide by slide.

Not yet verified (needs a person at the Mac): live voice following with the microphone, and that the
strip stays out of a real Zoom screen share.

Notes for whoever picks this up:
- With only the Command Line Tools, `swift test` needs the Swift Testing macro plugin path;
  `scripts/test.sh` adds it.
- Owner decisions (Nov 5): copyright holder Kevin Cheek; no paid Developer ID for now, so people
  build from source.
