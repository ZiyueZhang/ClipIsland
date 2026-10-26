# ClipIsland vs 参考项目：源码级对比评估

日期：2026-10-27 · 方法：克隆参考仓库逐文件研读（copyx / tendedero / Sapphire / shotx），
对照 ClipIsland 自身源码与验收记录。结论均标注代码证据位置。

| 项目 | 技术栈 | 规模 | 定位 |
|---|---|---|---|
| **ClipIsland**（本项目） | Swift/SwiftPM，零依赖 | ~5k 行 | 刘海效率岛：剪贴板+截图+编辑+OCR |
| copyx v0.1 | Rust/Tauri + Svelte 5 | ~3.2k 行，单 commit | 隐私加密剪贴板管理器 |
| tendedero | Swift/SwiftPM | 3.9k 行 | 截图"晾衣绳"（顶部悬停交互标杆）|
| Sapphire | Swift/AppKit+SwiftUI | **18.3 万行**，626 文件 | 刘海平台（功能宇宙）|
| shotx v1.9.10 | Swift/SwiftPM + Sparkle | 7.5k 行 | 菜单栏截图套件 |

## 总评

| 维度 | ClipIsland | copyx | tendedero | Sapphire | shotx |
|---|---|---|---|---|---|
| 美学 | B+ | B+ | A | **A+** | B |
| 交互逻辑 | **A-** | B | **A+**（鼠标）A-（键盘缺失）| A-（鼠标丰富/键盘弱）| B+ |
| 流程性 | **A-** | B- | A | A- | **A** |
| 功能可用性 | B+ | B-（宣传>实现）| B-（单一但扎实）| **A+**（广度）| B+ |
| 工程质量 | A-（有测试+CI+验收）| B+（文档极佳/壳层零测试）| A（细节注释典范）| B（巨石文件/私有API/内嵌遥测）| B（零测试零CI）|

---

## 1. 美学

**Sapphire（标杆）**：收起态纯黑贴合硬件刘海，几何按 2x 物理像素 even-pixel 对齐（`NotchDisplayMetrics.swift`）；macOS 26 用系统 Liquid Glass、降级 hud 材质、再降级纯色（`NotchSurfaceHostView.swift` 三档）；圆角随状态 morph（10→18→13→40）；**单一弹簧物理同时驱动窗口尺寸、CALayer mask 与 SwiftUI 内容**（`NotchMorphEngine.swift`，300Hz 解析积分，保证轮廓与内容零错位）；四档动画 profile + 自定义；触控板触觉反馈。短板：强制深色无浅色模式，大量私有 API。

**tendedero**：玻璃相片卡"晾"在细线上，展开 `spring(0.42/0.82)`、收起 `easeIn 0.22`（`LineView.swift:87-88`），卡片有物理摆动感；明暗双主题官网级视觉。小而精的美学范本。

**copyx**：对标 Spotlight/Raycast——hudWindow 毛玻璃 720×480、三层阴影（hairline+8/24+32/64）、统一缓动体系（入场 quintOut 220ms、开关 180ms iOS 曲线）。细节扣分：CSS 圆角 18px 与 vibrancy 14px 不一致有错位风险；每次召唤强制居中不记忆位置。

**shotx**：编辑器工具栏 `.ultraThinMaterial` + 渐变叠层、工具 chip 40×30 选中 accent 渐变；选区覆盖层极简（1px 白框、自绘带缺口十字光标、臂长 11pt）；**不做屏幕冻结**——实时暗化 + `.copy` 混合抠洞（`SelectionView.swift:179-196`），代价是选区外屏幕仍在动。

**ClipIsland 现状与差距**：黑条贴刘海 + hudWindow 面板 + 不对称圆角呼应刘海形状 + 悬挂缩略图动画，视觉语言成立；vibrancy 自动适配明暗（强于 Sapphire）。**差距**：① 窗口 frame 用自研插值、内容用 SwiftUI spring，两套动画没耦合（Sapphire 的 morph engine 思路：一套物理驱动全部）；② 无 even-pixel 对齐，Retina 上黑条与硬件刘海可能有半像素缝；③ 动画无 profile 档位；④ 悬挂缩略图不如 tendedero 的"线+摆动"有叙事感。

## 2. 交互逻辑

**触发方式对比**：

| | ClipIsland | copyx | tendedero | Sapphire | shotx |
|---|---|---|---|---|---|
| 悬停 | 岛本体 250ms | ✗ | **整个菜单栏热区** 250ms | 探针窗 8px 进/60px 出，1.10× 窥视 | ✗ |
| 点击 | ✓ | ✗ | ✓（右键菜单/双击/长按/力按五层）| ✓ ⌘点击直达模块 | ✗ |
| 热键 | ⌘⇧V + 3 备选 ✓ | ⌘⇧V 写死 | ✓（可开关悬停）| ✓ | 4 热键可录制 ✓ |
| 触控板手势 | ✗ | ✗ | 滚轮沿线移动 | 双指下滑开/上滑隐藏/横滑切模块 | 捏合缩放 |
| 失焦收起 | 移出 300ms | ✓ | 菜单栏点击抑制 ✓ | 宽限期+保护窗+pin | ✗ |

**键盘**（ClipIsland 的强项）：我们支持输入即搜（IME 安全）、↑↓、⏎、**1-9 直选即粘贴**、Esc 三级渐进。copyx 有 ↑↓/⏎/⇧⏎ 仅复制/⌘P 置顶/⌫删除但**无数字直选**；Sapphire 展开面板内几乎无键盘体系；**tendedero 面板 `canBecomeKey=false` 纯鼠标产品**；shotx 仅热键。

**关键发现——悬停触发面**：tendedero 用 `NSEvent.mouseLocation` 定时轮询"菜单栏带状区"（`AppDelegate.swift:460-520`，0.25s 延迟+0.5s 收回+菜单栏点击抑制），鼠标停在菜单栏**任意位置**都触发；Sapphire 用独立透明探针窗+分区边距。ClipIsland 只响应岛本体（220pt 宽）——**这是最值得抄的差距**。

**粘贴回写**：ClipIsland CGEvent 合成 ⌘V（100+140ms）；copyx 走 osascript 子进程（150ms settle，多一跳进程）；Sapphire 干脆只 copy-back 不代按。我们默认自动粘贴、设置可改仅复制，是覆盖面最全的。

**选区**：shotx mouseUp 即成交（<3px 视为取消）、无调整手柄、无事后移动、跨屏选区受限；ClipIsland 支持 Esc/单击取消、⏎ 整屏、跨屏 ghost 镜像、冻结帧保证取色像素一致。双方都无"事后调整手柄"（共同迭代项）。

## 3. 流程性

- **shotx 的"浮窗先行"最流畅**：松手即弹 250×160 浮窗（Copy/Save/Edit/钉住/拖出），PNG 编码走后台队列，6s 自动消失 hover 暂停（`PostCapturePopup.swift`）；且把自身窗口号注册进排除表，无需"隐藏窗口再截图"的延迟。ClipIsland 目前是"截图→自动开编辑器"，重用户路径多一步——应把浮窗快捷条作为默认或选项。
- **tendedero 的拖放语义**最省步骤：拖到 App=复制且留在线上、拖到文件夹=移动保存、拖到废纸篓=删除、拖空=飞回（`GrabArea.swift` 头注释）。剪贴板图片条目支持拖出 = 少一次"保存→Finder"。
- **copyx 的摩擦点**：每次召唤重新居中；每键全量 IPC+后端解密；**锁定期间复制内容被静默丢弃**；明文 preview ≤200 字符且 LIKE 未转义 `_`。
- **ClipIsland 链路**（复制→⌘⇧V→筛选→⏎→自动粘贴）无多余步骤，数字直选把"搜索+回车"压成一次按键；Esc 三级渐进可回退。**缺**：截图后无快捷操作浮条；历史图片条目无 Quick Look（空格预览）与拖出；无"上次区域"重拍（shotx 有）；无窗口捕获模式（shotx 有窗口取景高亮）。

## 4. 功能可用性

**copyx：宣传 > 实现（源码证据）**
- 加密是真的且设计讲究：XChaCha20-Poly1305 + Argon2id（m=64MB/t=3/p=4）、信封格式、zeroize；Touch ID 用"Keychain 存数据钥匙 + LAContext 触发"的拆分设计规避 adhoc 签名 entitlement 问题——**我们 v2 加密应抄这份方案**。
- 但：nspasteboard 敏感过滤（filter.rs 8 个标记）**在真实管线里是死代码**——monitor 从不填 format_hints，密码管理器内容照样入库且加密前明文进 preview 列；"来源 App"同样永远为空；paste 走 `recent(1000)` 线性扫描，第 1000 条后无法粘贴；无清空全部；暂停藏在设置页；自动锁只被自家窗口按键重置（鼠标活动不重置）。
- ClipIsland 对位优势：敏感过滤真实生效（验收过）、来源 App 有值、有清空/暂停入口/容量设置/热键预设、CGEvent 比 osascript 快且无子进程开销。

**Sapphire：功能宇宙，工程债同样巨大**
- 剪贴板监控是事件驱动（全局监听 ⌘C/⌘X 键盘事件 + 自适应轮询 1s/10s/30s 三档）——比纯轮询省电且更快；密码管理器默认忽略 12 家；每条独立文件加密存储。
- 但 `NotchController.swift` 3,619 行、`SettingsModel.swift` 4,144 行；私有 API（CGSSpace、HTK 触觉、swizzle）；**内嵌 Firebase/Google Analytics 默认开启**；设置 44 分区 ~680 字段；自带 gap map 承认 30+ bug；无构建 CI。
- 对 ClipIsland：功能广度不做对标（定位不同），要抄的是事件驱动监控与探针窗。

**shotx：捕获工艺高，标注刻意最小**
- 窗口捕获排除表、popup 先行后台编码、剪贴板同时写 PNG+TIFF（兼容挑剔的 Electron 应用）、窗口取景高亮、定时截图、GIF/录屏、Sparkle 自动更新。
- 标注仅 4 工具（箭头/矩形/文字/序号），**画完不可选中/移动/改色，无 redo**；历史 README 宣称可搜索实际没有；保存无 SavePanel 直写桌面；OCR 硬编码 6 种欧洲语言（无中文）且无结果预览。
- ClipIsland 编辑器 9 工具 + 选中回改 + 撤销重做 + 马赛克/裁剪/高亮 + OCR 中文 + 结果面板，全面占优；差距在捕获周边（窗口模式/上次区域/浮条）。

**tendedero**：功能单一（截图晾晒）但完成度极高；10 国语言 README、浏览器 Demo、Quick Look/Markup 集成。启示：本地化骨架与"少而精"的产品纪律。

## 5. 迭代清单（按价值/成本排序）

**P0**
1. **悬停触发面扩到菜单栏带**（tendedero 模式：`NSEvent.mouseLocation` 轮询 + 250ms 延迟 + 菜单栏点击抑制），或 Sapphire 式探针窗——当前 220pt 小窗口太难点中
2. **截图后浮条**（Copy/Save/Edit/钉住，hover 暂停倒计时），`openEditorAfterCapture` 默认改关
3. **窗口捕获模式**：光标下窗口高亮取景（shotx `WindowCapture.swift` 模式）
4. **历史条目空格 Quick Look + 拖出保存**（tendedero 拖放语义）
5. 剪贴板写入图片时同时写 PNG+TIFF（兼容 Electron 应用）

**P1**
6. "上次区域"重拍热键；多屏：捕获指针所在屏（tendedero `screenUnderPointer`）
7. v2 加密：抄 copyx 的 Keychain+生物识别拆分方案，KDF 用 PBKDF2(600k)（无依赖约束下）并补 AutoLock 用 `NSEvent` 全局监听重置
8. 事件驱动剪贴板监控（⌘C 键盘事件 + 自适应轮询），降功耗提速捕获
9. even-pixel 对齐 + 肩部圆角 shape + 动画 profile（Snappy/Fluid/Calm）
10. 本地化骨架（L() helper，zh-Hans/en 起）

**P2**
11. Sparkle 自动更新（shotx 路线）或应用内检查更新
12. Developer ID 签名 + 公证（当前 adhoc，所有参考项目同病）
13. 编辑器：选区调整手柄、序号步骤标注（shotx 的 step 圆号）
