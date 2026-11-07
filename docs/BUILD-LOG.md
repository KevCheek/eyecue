# Build log

## 2026-11-06: version 0.3.0

- Resize by dragging: the strip's sides move together so it stays centered under the camera, and its bottom edge snaps to whole lines.
- Floating Window (menu, or Control Option F): a larger window that can be dragged to any screen and resized from any edge or corner. It remembers its place and size and is hidden from screen sharing like the strip.
- Scroll speed: Control Option Right and Left change it by 10 words a minute, the Scroll Speed menu has a slider (60 to 300), and the speed shows in the strip when Follow My Voice is off.
- In-app updates with Sparkle 2.10.1 (pinned, the one third-party dependency). It checks GitHub at launch and once a day, says when a new version is out, and one click installs it. Check for Updates and Check for Updates Automatically are in the menu; with automatic checks off, background checks are refused.
- The app still has no network entitlement. Sparkle's separate Downloader helper fetches the feed and the update. Every update must carry a valid EdDSA signature. New entitlements, for Sparkle only: `cs.disable-library-validation` and a mach-lookup exception for its two local services.
- Releases are signed with one self-signed certificate instead of ad hoc, so macOS keeps the microphone and speech permissions across updates.
- Builds go to `build/Products.noindex`, so Spotlight doesn't list a second copy.
- Script loader limits: headings count toward the length limit, a limit on sections, packages and rtfd refused.
- `SnowpineCue --window-check` drives the real panel with simulated presses and drags, and `--update-check` reads the feed with no window.
- An independent review (Codex) found one medium problem, fixed with a test: dragging a floating window's edge near the side of the screen pushed the opposite edge.

Checked here on an M5 MacBook Pro, macOS 27: 38 unit tests, the no-network, smoke and window checks, a signed universal build, and `--update-check` reaching GitHub through Sparkle's helper.

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
