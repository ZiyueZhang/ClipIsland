# Changelog

All notable changes to ClipIsland are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [1.1.0] - 2026-10-27

### Added
- Menu-bar hover trigger: rest the pointer anywhere in the menu bar to summon the island (tendedero-style dwell + click suppression), instead of only the notch area
- Post-capture quick-action bar: Copy / Edit / Reveal with 6s auto-dismiss (hover pauses); the editor becomes an explicit one-hop choice
- Screenshots pasteable as PNG + TIFF dual flavors (Electron-app friendly) with reveal-in-Finder flow

### Changed
- Even-pixel alignment for the island on Retina displays (no half-pixel seams against the hardware notch)
- Spring-driven window animation at 120Hz sharing one motion system with content springs; honors Reduce Motion
- Thumbnails decode at 136px via ImageIO — a 4000x2500 screenshot costs ~74KB resident instead of a ~38MB full decode
- Clipboard polling backs off (0.35s -> 1.2s) after two quiet minutes; removed per-row capsule layers in the expanded panel

## [1.0.0] - 2026-10-27

First public release.

### Added
- Notch island: real-notch wrapping + simulated pill, hover/click/hotkey expand, spring animation, hanging screenshot thumbnail
- Clipboard: text/link/file/image capture, SHA256 dedup, pin, delete, clear, LRU capacity, instant search, type filters, SQLite persistence, pause monitoring, sensitive-content filtering (nspasteboard concealed markers)
- Auto-paste: frontmost-app tracking + CGEvent ⌘V synthesis, accessibility fallback to copy-only
- Screenshot: full-screen freeze, region selection with size label and crosshair, live color picker (⌘C), full-screen capture (⏎), optional file save
- Image editor: rectangle/ellipse/arrow/pen/text/highlight/mosaic/crop, undo-redo, copy/save
- OCR: offline Vision-based Chinese/English recognition from editor or history
- Settings: launch-at-login (SMAppService), capacity, click behavior, hotkey presets, save directory, expand-on-hover
- Global hotkeys ⌘⇧V / ⌘⇧6 (Carbon), re-mappable via presets
- 68-check logic test suite (`swift run SelfTest`) + 28-point runtime acceptance (docs/ACCEPTANCE.md)
