<div align="center">

# ClipIsland

**把 MacBook 刘海变成效率岛：剪贴板历史 + 截图 + 图片标注 + OCR，一个 1.6MB 的原生应用。**

[English](README.md) · [简体中文](README.zh-CN.md)

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![swift](https://img.shields.io/badge/Swift-6-orange)
![size](https://img.shields.io/badge/app%20size-~1.6MB-blue)
![deps](https://img.shields.io/badge/dependencies-zero-success)
![license](https://img.shields.io/badge/license-MIT-green)

</div>

---

ClipIsland 常驻 MacBook 刘海区：鼠标悬停（或 ⌘⇧V）从顶部滑出毛玻璃剪贴板历史面板，⌘⇧6 区域截图并标注。纯 Swift 原生实现，完全离线，整个应用仅 ~1.6MB。

```
┌─────────────────────────────────────────┐
│  菜单栏   ▓▓ 10:26 剪贴板 12 ▓▓  菜单栏  │   ← 收起态：时间 + 剪贴板条数
├─────────────────────────────────────────┤
│         ┌──────────────────┐            │
│         │ 🔍 搜索剪贴板…    │            │   ← 悬停 / ⌘⇧V：毛玻璃面板
│         │ 1 hello      2分前 │            │
│         │ 2 https://…  5分前 │            │      ↑↓ 选择 · ⏎ 粘贴
│         │ 3 [图片]     8分前 │            │      1-9 直选
│         └──────────────────┘            │
└─────────────────────────────────────────┘
```

## 功能

**剪贴板（对齐 copyx 全功能）**
- 鼠标停在菜单栏任意位置即可唤出面板（250ms 防误触），不只限刘海区域
- 自动捕获文本 / 链接 / 文件路径 / 图片，内容去重、即时搜索
- 置顶（豁免容量淘汰）、单条删除、清空、容量上限（100–2000 条，LRU）
- 点击条目 = **复制并自动粘贴**回之前的应用（CGEvent 合成 ⌘V，可改仅复制）
- 密码管理器敏感内容自动跳过（nspasteboard.org 标记）
- SQLite 持久化，重启不丢；菜单栏可暂停监控

**截图**
- ⌘⇧6 区域截图：冻结全屏、拖框选区、实时尺寸标签、十字线
- **取色器**：选区时实时显示光标下像素 HEX，⌘C 复制
- ⏎ 整屏捕获，Esc / 单击取消
- 完成后缩略图在刘海下悬挂 2.5 秒，自动进入历史，可选存文件

**图片编辑器（ShotX 式）**
- 矩形 / 椭圆 / 箭头 / 画笔 / 文字 / 高亮 / **马赛克** / 裁剪 / 选择移动
- 8 种标注颜色、笔画粗细、字号，⌘Z / ⇧⌘Z 撤销重做
- 复制（入历史）/ 保存 PNG / 完成

**OCR**
- 系统 Vision 框架完全离线识别（中英文）
- 编辑器内一键识别，或对历史中任意图片条目识别

**刘海岛本身**
- 真刘海屏内容无缝贴合；无刘海 Mac 显示顶部居中模拟胶囊
- 收起态显示时间/日期 + 条数；悬停（250ms 防误触）或点击展开

## 环境要求

- macOS 14.0+
- Apple Silicon 或 Intel Mac

## 构建与运行

只需 Xcode Command Line Tools——无需完整 Xcode，零第三方依赖：

```bash
git clone https://github.com/ZiyueZhang/ClipIsland.git
cd ClipIsland
./scripts/build-app.sh          # → build/ClipIsland.app（release，adhoc 签名）
open build/ClipIsland.app
```

开发调试：

```bash
./scripts/dev-run.sh            # debug 构建 + 签名 + 运行（日志 /tmp/clipisland.log）
swift run SelfTest              # 68 项逻辑自测
./scripts/release.sh 1.0.1      # 构建 + 打包 + 发布 GitHub Release
```

不想编译？直接从 [Releases](https://github.com/ZiyueZhang/ClipIsland/releases) 下载打包好的 ClipIsland.app。

## 首次启动

应用为 adhoc 签名（无开发者证书）。从网上下载后 macOS Gatekeeper 可能拦截——右键应用 → **打开**，或：

```bash
xattr -cr /Applications/ClipIsland.app
```

两项权限（均可选、均有降级路径，首启向导会自动打开设置页引导）：

| 权限 | 用途 | 未授权时 |
|---|---|---|
| 辅助功能 | 自动粘贴（合成 ⌘V） | 降级为仅复制，面板内横幅引导 |
| 屏幕录制 | 屏幕捕获 | 截图不可用，自动跳转系统设置 |

## 快捷键

| 动作 | 默认 | 备选（设置中切换）|
|---|---|---|
| 剪贴板面板 | ⌘⇧V | ⌥⇧V / ⌃⇧V / ⌘⇧B |
| 区域截图 | ⌘⇧6 | ⌘⇧7 / ⌥⇧S / ⌃⇧6 |

面板内：输入即搜 · ↑↓ 选择 · ⏎ 粘贴 · 1-9 直选 · Esc 依次清除搜索 → 筛选 → 收起。

## 数据与隐私

- 100% 离线：无网络、无遥测、无账号。
- 历史数据在 `~/Library/Application Support/ClipIsland/`（v1 明文，加密在路线图）。
- 截图默认存到 `~/Pictures/ClipIsland/`（可改）。
- 密码管理器带隐藏标记的剪贴板内容永不落盘。

## 架构

纯 Swift（AppKit + SwiftUI），仅用 Swift Package Manager 构建——.app 由脚本组装，因此全应用只有 1.6MB。技术要点：

- 刘海几何：`NSScreen.safeAreaInsets` + `auxiliaryTopLeft/RightArea` 检测
- 全局热键：Carbon `RegisterEventHotKey`；捕获：`CGWindowListCreateImage`（带 `screencapture` CLI 兜底）
- UI 完全避开 SwiftUI 属性包装宏（状态全在 `@Observable` 模型）——保证裸 Command Line Tools 可编译；完整技术笔记见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)
- 28 项运行时验收，通过分布式通知测试钩子驱动

```
Sources/
├── ClipIsland/          # 入口（LSUIElement 菜单栏应用）
├── ClipIslandCore/
│   ├── Notch/           # 刘海几何 / 窗口动画 / 状态机 / 视图
│   ├── Clipboard/       # 监控（敏感过滤）+ 自动粘贴（CGEvent）
│   ├── Screenshot/      # 冻结裁剪取色 / 选区 UI / OCR（Vision）
│   ├── Editor/          # 标注模型 / CoreGraphics 渲染器 / 编辑器窗口
│   ├── ClipStore.swift  # SQLite 封装：去重 / LRU / 搜索 / 持久化
│   └── …
└── SelfTest/            # 68 项逻辑自测
```

## 路线图

- [ ] 录屏与 GIF 导出
- [ ] 端到端加密（主密码 + Touch ID 解锁）
- [ ] 可插拔"岛"模块（天气 / 番茄钟 / 正在播放）
- [ ] 富内容粘贴预览

完整验收矩阵与设计笔记见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)。灵感来自 [copyx](https://github.com/yuuuuuuanhua/copyx)、[ShotX](https://github.com/aimen08/shotx)、[Sapphire](https://github.com/cshariq/Sapphire) 与 [tendedero](https://github.com/alejandrobujan/tendedero)。

## 许可证

[MIT](LICENSE)
