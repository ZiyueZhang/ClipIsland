<div align="center">

# ClipIsland

**Turn your MacBook notch into a productivity island: clipboard history, screenshots, image annotation and OCR — in one tiny native app.**

[English](README.md) · [简体中文](README.zh-CN.md)

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![swift](https://img.shields.io/badge/Swift-6-orange)
![size](https://img.shields.io/badge/app%20size-~1.6MB-blue)
![deps](https://img.shields.io/badge/dependencies-zero-success)
![license](https://img.shields.io/badge/license-MIT-green)

</div>

---

ClipIsland lives in your MacBook's notch. Hover over it (or press ⌘⇧V) and a glass panel slides down with your clipboard history. Press ⌘⇧6 to take an annotated screenshot. Everything is native Swift, fully offline, and the whole app is ~1.6 MB.

```
┌─────────────────────────────────────────┐
│  menu bar  ▓▓ 10:26  ⎘ 12 ▓▓  menu bar  │   ← collapsed: clock + clip count
├─────────────────────────────────────────┤
│         ┌──────────────────┐            │
│         │ 🔍 Search…        │            │   ← hover / ⌘⇧V: glass panel
│         │ 1 hello      2m   │            │
│         │ 2 https://…  5m   │            │      ↑↓ select · ⏎ paste
│         │ 3 [image]    8m   │            │      1-9 direct paste
│         └──────────────────┘            │
└─────────────────────────────────────────┘
```

## Features

**Clipboard (full copyx-class feature set)**
- Summon by resting the pointer just below the notch (250ms dwell, click-suppression)
- Auto-captures text, links, file paths and images — deduplicated, searchable
- Pin entries (exempt from eviction), delete, clear, capacity limit (100–2000, LRU)
- Click = **copy + auto-paste** back into the app you came from (CGEvent ⌘V, can be set to copy-only)
- Password-manager content is skipped (nspasteboard.org concealed markers)
- Persisted in SQLite — survives restarts; pause monitoring from the menu bar
- **Optional encryption at rest**: AES-256-GCM + PBKDF2 (600k iterations), lock screen with Touch ID, auto-lock; copies made while locked buffer in RAM and merge on unlock

**Screenshot**
- ⌘⇧6 region capture: screen freeze, drag-select, live size label, crosshair
- ⌘⇧7 window capture: live highlight of the window under the cursor, click to capture occlusion-free
- **Color picker**: live hex under the cursor while selecting, ⌘C to copy
- ⏎ captures the full screen, Esc cancels, click cancels
- Thumbnail "hangs" under the notch for 2.5s, auto-enters history (instantly pasteable), optional file save
- Quick-action bar pops bottom-left: Copy / Edit / Reveal in Finder, 6s auto-dismiss (hover pauses)

**Image editor (ShotX-style)**
- Rectangle / ellipse / arrow / pen / text / highlight / **mosaic** / crop / move
- 8 annotation colors, stroke widths, font sizes, ⌘Z / ⇧⌘Z undo-redo
- Copy (into history) / save PNG / done

**OCR**
- Fully offline via the system Vision framework (Chinese + English)
- One click from the editor or from any image in history

**The island itself**
- Wraps a real notch seamlessly; shows a simulated pill on notch-less Macs
- Collapsed strip shows clock/date + clip count; hover (debounced) or click to expand

## Requirements

- macOS 14.0+
- Apple Silicon or Intel Mac

## Build & Run

Only Xcode Command Line Tools are required — no full Xcode, no third-party packages:

```bash
git clone https://github.com/ZiyueZhang/ClipIsland.git
cd ClipIsland
./scripts/build-app.sh          # → build/ClipIsland.app (release, adhoc-signed)
open build/ClipIsland.app
```

Development:

```bash
./scripts/dev-run.sh            # debug build + sign + run (log: /tmp/clipisland.log)
swift run SelfTest              # 68 logic checks
./scripts/release.sh 1.0.1      # build + zip + GitHub release
```

Prefer not to build? Grab a packaged app from [Releases](https://github.com/ZiyueZhang/ClipIsland/releases).

## First Launch

The app is adhoc-signed (no Apple Developer certificate). macOS Gatekeeper may block it after download — right-click the app → **Open**, or:

```bash
xattr -cr /Applications/ClipIsland.app
```

Two permissions (both optional, with graceful fallbacks — a first-run wizard opens Settings for you):

| Permission | Used for | Without it |
|---|---|---|
| Accessibility | auto-paste (synthesized ⌘V) | falls back to copy-only, banner guides you |
| Screen Recording | screen capture | capture disabled, jumps to System Settings |

## Hotkeys

| Action | Default | Alternatives (Settings) |
|---|---|---|
| Clipboard panel | ⌘⇧V | ⌥⇧V / ⌃⇧V / ⌘⇧B |
| Window capture | ⌘⇧7 | ⌘⇧8 / ⌥⇧W / ⌃⇧7 |
| Region screenshot | ⌘⇧6 | ⌘⇧7 / ⌥⇧S / ⌃⇧6 |

In the panel: type to search · ↑↓ select · ⏎ paste · 1-9 direct paste · Esc clears search → filter → closes.

## Data & Privacy

- 100% offline. No network, no telemetry, no accounts.
- History lives in `~/Library/Application Support/ClipIsland/` (plaintext in v1; encryption on the roadmap).
- Screenshots save to `~/Pictures/ClipIsland/` by default (configurable).
- Password-manager clipboard content (concealed markers) is never stored.

## Architecture

Pure Swift (AppKit + SwiftUI) built with Swift Package Manager alone — the app bundle is assembled by a shell script, which is why the whole thing is 1.6 MB. Highlights:

- Notch geometry via `NSScreen.safeAreaInsets` + `auxiliaryTopLeft/RightArea`
- Global hotkeys via Carbon `RegisterEventHotKey`; capture via `CGWindowListCreateImage` with a `screencapture` CLI fallback
- The UI avoids SwiftUI property-wrapper macros entirely (all state in `@Observable` models) — this keeps it buildable with bare Command Line Tools; see [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the full technical notes
- 28-point runtime acceptance suite driven by distributed-notification hooks

```
Sources/
├── ClipIsland/          # entry point (LSUIElement accessory app)
├── ClipIslandCore/
│   ├── Notch/           # island geometry, window animation, state machine, views
│   ├── Clipboard/       # monitor (sensitive filter) + auto-paste (CGEvent)
│   ├── Screenshot/      # freeze/crop/color sampling, selection UI, OCR (Vision)
│   ├── Editor/          # annotation model, CoreGraphics renderer, editor window
│   ├── ClipStore.swift  # SQLite wrapper: dedup / LRU / search / persistence
│   └── …
└── SelfTest/            # 68-check logic test runner
```

## Roadmap

- [ ] Screen recording & GIF export
- [x] ~~End-to-end encryption~~ (shipped in v1.2.0: AES-GCM + PBKDF2 + Touch ID + auto-lock)
- [x] ~~Rich content capture~~ (shipped in v1.7.0: HTML/RTF captured per entry, format-preserving paste-back)
- [ ] In-panel rich preview (HTML/RTF is captured; rendering pending)
- [ ] Pluggable island modules (weather, pomodoro, now-playing)

See [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md) for the full acceptance matrix and design notes. Inspired by [copyx](https://github.com/yuuuuuuanhua/copyx), [ShotX](https://github.com/aimen08/shotx), [Sapphire](https://github.com/cshariq/Sapphire) and [tendedero](https://github.com/alejandrobujan/tendedero).

## License

[MIT](LICENSE)
