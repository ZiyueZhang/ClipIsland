# Changelog

All notable changes to ClipIsland are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

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
