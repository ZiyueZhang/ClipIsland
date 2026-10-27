# Changelog

All notable changes to ClipIsland are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/), versioning: [SemVer](https://semver.org/).

## [1.3.0] - 2026-10-28

### Added — animation & aesthetics pass (source review: Sapphire morph engine, boring.notch NotchShape, tendedero springs)
- Notch silhouette adopted from boring.notch: top radius 6 (fuses with the screen top), bottom radius 14 — replaces the uniform rounded rect
- **Motion profiles** in Settings (利落/灵动/沉稳), parameters after Sapphire's Snappy/Bouncy/Calm
- **Velocity-carrying interruptible springs**: redirecting mid-animation keeps momentum instead of restarting from rest (Sapphire morph-engine behavior)
- Hover peek: the collapsed strip scales 1.02× under the pointer; expanded panel content breathes (scale+opacity) with the phase spring
- Reduce Motion now gates every SwiftUI animation as well as window frame motion

### Changed
- **Hover trigger narrowed to directly below the notch** (user request): the dwell zone is the strip's own footprint padded 18pt down — no longer the whole menu bar; clicks in the zone still suppress triggering
- Settings label updated accordingly

## [1.2.1] - 2026-10-28

### Fixed (first visual audit — offscreen render harness added)
- **Collapsed strip was invisible in production**: the 216pt strip window sat entirely behind the opaque hardware notch, hiding the clock and clip count. The strip now extends into the menu-bar areas on both sides (clock left, count right) and fuses with the notch in the middle; its window doubles as a much larger hover/click target
- Date format rendered as "(周: 43)" — now "10月28日 周三"
- Expanded panel corners were square: the clip shape only covered the background, not the content — now the whole island clips and the shadow follows
- Search field had no visible container — now a rounded field with a magnifier icon
- Post-capture bar thumbnail now has inner padding

### Added
- `RenderTool`: offscreen snapshot harness that renders every island surface (panel dark/light, empty, locked, strip, popup) to PNG without screen-recording permission — the visual regression loop for future iterations

## [1.2.0] - 2026-10-27

### Added
- **Window capture mode** (⌘⇧7, re-mappable): live accent highlight of the window under the cursor with an app-name chip, click captures it occlusion-safe via its window number — no screen freeze needed
- **Quick Look** (space in the panel): full previews for images, files, text and links
- **Drag out of history**: image/file rows drag as real files into Finder, editors and mail; text/link rows drag their string
- **Encryption at rest (v2)**: AES-256-GCM under a random data key wrapped by PBKDF2-HMAC-SHA256 (600k iterations, RFC-vector tested) — text payloads and image files are sealed in the database and on disk; dedup uses keyed HMACs so duplicate-equality never leaks
- Lock screen in the panel with Touch ID unlock; auto-lock (1–60 min); "立即锁定" menu item; captures made while locked are buffered in RAM and merge into encrypted history on unlock (fixes the silent-drop flaw copyx ships with)
- Migration: enabling/disabling encryption rewrites all existing items in place

### Changed
- SQLite metadata now public to the test harness; image reads route through the vault everywhere (pasteboard, editor, Quick Look, thumbnails, drag)

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
