const pptxgen = require("pptxgenjs");

// ---------- palette (content-informed: notch black + macOS system blue) ----------
const BG = "0B0B10";        // near-black, the notch
const CARD = "17171E";      // graphite panel
const NOTCH = "22222C";     // motif fill
const LINE = "34343E";      // hairlines
const TEXT = "F5F5F7";      // apple white
const MUTED = "98989F";     // apple gray
const ACCENT = "0A84FF";    // macOS system blue
const FONT = "PingFang SC";

const W = 13.33, H = 7.5, M = 0.55;

let p = new pptxgen();
p.layout = "LAYOUT_WIDE";
p.author = "Ziyue Zhang";
p.title = "ClipIsland 产品介绍";

// ---------- helpers ----------
function baseSlide(sectionLabel, num) {
  const s = p.addSlide();
  s.background = { color: BG };
  // notch motif: top-center, graphite, with section label
  s.addShape(p.shapes.ROUNDED_RECTANGLE, {
    x: W / 2 - 0.85, y: 0, w: 1.7, h: 0.3, rectRadius: 0.06,
    fill: { color: NOTCH }, line: { color: LINE, width: 0.75 },
  });
  s.addText(sectionLabel, {
    x: W / 2 - 0.85, y: 0, w: 1.7, h: 0.3, align: "center", valign: "middle",
    fontSize: 11, fontFace: FONT, color: MUTED, margin: 0,
  });
  return s;
}

function title(s, t, sub) {
  s.addText(t, { x: M, y: 0.55, w: W - 2 * M, h: 0.75, fontSize: 30, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
  if (sub) s.addText(sub, { x: M, y: 1.28, w: W - 2 * M, h: 0.4, fontSize: 14, fontFace: FONT, color: MUTED, margin: 0 });
}

const frame = () => ({ type: "outer", color: "000000", blur: 8, offset: 3, angle: 90, opacity: 0.35 });
const bu = () => ({ code: "2013", indent: 10 });

function framedImage(s, path, x, y, w, h) {
  s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: x - 0.06, y: y - 0.06, w: w + 0.12, h: h + 0.12, rectRadius: 0.07, fill: { color: CARD }, line: { color: LINE, width: 1 }, shadow: frame() });
  s.addImage({ path, x, y, w, h });
}

function chip(s, x, y, w, text, big) {
  s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y, w, h: big ? 0.46 : 0.4, rectRadius: 0.2, fill: { color: CARD }, line: { color: LINE, width: 0.75 } });
  s.addText(text, { x, y, w, h: big ? 0.46 : 0.4, align: "center", valign: "middle", fontSize: big ? 14 : 12, fontFace: FONT, color: TEXT, margin: 0 });
}

// ---------- 1 cover ----------
{
  const s = baseSlide("CLIPISLAND", "01");
  // product strip image across the top, under the notch motif
  s.addImage({ path: "/tmp/ci-render/strip-extended.png", x: W / 2 - 2.85, y: 0.62, w: 5.7, h: 0.455 });
  s.addText("ClipIsland", { x: M, y: 1.5, w: 7.4, h: 1.1, fontSize: 60, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
  s.addText("把 MacBook 的刘海，变成一台随叫随到的效率岛", {
    x: M, y: 2.72, w: 7.2, h: 0.5, fontSize: 20, fontFace: FONT, color: ACCENT, margin: 0,
  });
  s.addText("剪贴板历史 · 区域/窗口截图 · 图片标注 · 离线 OCR", {
    x: M, y: 3.3, w: 7.2, h: 0.4, fontSize: 15, fontFace: FONT, color: MUTED, margin: 0,
  });
  chip(s, M, 4.05, 1.55, "1.6MB 安装包", true);
  chip(s, M + 1.75, 4.05, 1.55, "0 第三方依赖", true);
  chip(s, M + 3.5, 4.05, 1.55, "113 项自测", true);
  s.addText([
    { text: "原生 Swift · SwiftPM 构建 · 完全离线 · 开源 MIT", options: { breakLine: true } },
    { text: "github.com/ZiyueZhang/ClipIsland", options: { color: ACCENT } },
  ], { x: M, y: 4.85, w: 7.0, h: 0.7, fontSize: 13, fontFace: FONT, color: MUTED, margin: 0, paraSpaceAfter: 6 });
  framedImage(s, "/tmp/ci-render/panel-lived-dark.png", 8.35, 1.75, 4.35, 2.84);
  s.addText("展开面板 · 真实渲染", { x: 8.35, y: 4.72, w: 4.35, h: 0.3, align: "center", fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
  s.addText("2026 · v1.2.1", { x: M, y: 6.9, w: 3, h: 0.3, fontSize: 12, fontFace: FONT, color: MUTED, margin: 0 });
}

// ---------- 2 problem ----------
{
  const s = baseSlide("问题与机会", "02");
  title(s, "剪贴板这个 40 年的老问题，工具却各缺一半", "对 4 个开源竞品的源码级调研结论（docs/COMPARISON.md）");
  const rows = [
    ["召唤即遮挡", "copyx 召唤后底部大面板盖住工作区，且不可调尺寸、不记忆位置"],
    ["刘海在浪费", "刘海屏 Mac 的默认状态是“一条黑洞”，Nook X 等闭源工具功能杂而重"],
    ["工具箱太散", "截图、标注、OCR、取色通常要 3–4 个常驻应用，菜单栏挤满图标"],
    ["隐私是宣传语", "copyx 的敏感内容过滤在源码里是死代码：密码管理器内容照样明文入库"],
  ];
  rows.forEach((r, i) => {
    const y = 1.95 + i * 1.08;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y, w: 0.62, h: 0.62, rectRadius: 0.09, fill: { color: CARD }, line: { color: LINE, width: 0.75 } });
    s.addText(String(i + 1), { x: M, y, w: 0.62, h: 0.62, align: "center", valign: "middle", fontSize: 22, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
    s.addText(r[0], { x: M + 0.9, y: y - 0.02, w: 10.5, h: 0.4, fontSize: 17, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
    s.addText(r[1], { x: M + 0.9, y: y + 0.36, w: 10.9, h: 0.4, fontSize: 13, fontFace: FONT, color: MUTED, margin: 0 });
    if (i < rows.length - 1) s.addShape(p.shapes.LINE, { x: M + 0.9, y: y + 0.92, w: 10.9, h: 0, line: { color: LINE, width: 0.75 } });
  });
  s.addNotes("痛点来自对 copyx/tendedero/Sapphire/shotx 四个开源项目源码的逐文件阅读，每条都能指出具体文件位置。");
}

// ---------- 3 solution ----------
{
  const s = baseSlide("方案", "03");
  title(s, "一个常驻刘海的原生效率岛，四个工具合一", "鼠标停在菜单栏任意位置即滑出面板，Esc 即收起——平时零占用");
  framedImage(s, "/tmp/ci-render/panel-lived-dark.png", M, 1.95, 6.6, 4.3);
  s.addText("展开面板：搜索、类型筛选、直选、预览、置顶", { x: M, y: 6.4, w: 6.6, h: 0.3, align: "center", fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
  const feats = [
    ["剪贴板历史", "文本/链接/文件/图片全捕获，SHA256 去重，置顶与容量 LRU，即时搜索 + 类型筛选"],
    ["截图套件", "⌘⇧6 区域（冻结帧+取色）与 ⌘⇧7 窗口（遮挡无关）两条链路，完成后浮条直达动作"],
    ["图片标注", "9 种工具含马赛克/裁剪/高亮，撤销重做，所见即所得导出"],
    ["离线 OCR", "系统 Vision 框架中英文识别，不联网、零成本"],
  ];
  feats.forEach((f, i) => {
    const y = 2.0 + i * 1.18;
    s.addText(f[0], { x: 7.6, y, w: 5.2, h: 0.35, fontSize: 16, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
    s.addText(f[1], { x: 7.6, y: y + 0.38, w: 5.2, h: 0.62, fontSize: 12.5, fontFace: FONT, color: MUTED, margin: 0 });
  });
}

// ---------- 4 interaction: clipboard loop ----------
{
  const s = baseSlide("交互逻辑 ①", "04");
  title(s, "剪贴板主循环：四次按键完成“复制→召回→粘贴”", "键盘全程不离位；数字直选把「搜索+回车」压成一次按键");
  const steps = [
    ["⌘C", "照常复制", "0.35s 内捕获入库，重复内容自动置顶"],
    ["⌘⇧V", "唤出面板", "或鼠标停在菜单栏任意位置 0.25s"],
    ["输入/1-9", "定位内容", "输入即搜（中文输入法安全），↑↓ 微调"],
    ["⏎", "自动粘贴", "写回剪贴板并合成 ⌘V 到原应用；Esc 三级渐进退出"],
  ];
  steps.forEach((st, i) => {
    const x = M + i * 3.13;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y: 2.15, w: 2.75, h: 1.9, rectRadius: 0.1, fill: { color: CARD }, line: { color: LINE, width: 0.75 } });
    s.addText(st[0], { x, y: 2.3, w: 2.75, h: 0.55, align: "center", fontSize: 24, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
    s.addText(st[1], { x, y: 2.9, w: 2.75, h: 0.35, align: "center", fontSize: 15, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
    s.addText(st[2], { x: x + 0.18, y: 3.28, w: 2.4, h: 0.72, align: "center", fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
    if (i < steps.length - 1) s.addText("→", { x: x + 2.72, y: 2.75, w: 0.45, h: 0.5, align: "center", fontSize: 22, fontFace: FONT, color: MUTED, margin: 0 });
  });
  s.addText("面板内的完整键盘体系", { x: M, y: 4.5, w: 6, h: 0.35, fontSize: 15, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "输入即搜：来源应用名也可检索，类型 chips 一键筛选", options: { bullet: bu(), breakLine: true } },
    { text: "1-9 直选即粘贴 · 空格 Quick Look 预览 · 悬停行出现 置顶/编辑/OCR/删除", options: { bullet: bu(), breakLine: true } },
    { text: "Esc 三级渐进：清搜索 → 清筛选 → 收面板，随时不迷路", options: { bullet: bu(), breakLine: true } },
    { text: "条目可拖出：图片拖到 Finder/邮件即文件，文本拖出即字符串", options: { bullet: bu() } },
  ], { x: M, y: 4.9, w: 11.9, h: 1.6, fontSize: 13.5, fontFace: FONT, color: MUTED, margin: 0, paraSpaceAfter: 7 });
}

// ---------- 5 interaction: screenshot flow ----------
{
  const s = baseSlide("交互逻辑 ②", "05");
  title(s, "截图工作流：从按键到可用内容，最少两步", "两条捕获链路共用同一套交付管线：历史、浮条、编辑器");
  const lanes = [
    ["⌘⇧6 区域截图", "冻结全屏 → 拖框（实时尺寸 + 光标取色 ⌘C）→ 松手", "跨屏选区 · ⏎ 整屏 · Esc 取消"],
    ["⌘⇧7 窗口截图", "光标下窗口高亮取景（应用名标签）→ 点击", "按窗口号合成，被遮挡也完整；自身窗口自动排除"],
  ];
  lanes.forEach((l, i) => {
    const y = 1.95 + i * 1.3;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x: M, y, w: 6.9, h: 1.12, rectRadius: 0.1, fill: { color: CARD }, line: { color: LINE, width: 0.75 } });
    s.addText(l[0], { x: M + 0.25, y: y + 0.12, w: 6.4, h: 0.35, fontSize: 15, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
    s.addText(l[1], { x: M + 0.25, y: y + 0.5, w: 6.4, h: 0.32, fontSize: 12.5, fontFace: FONT, color: TEXT, margin: 0 });
    s.addText(l[2], { x: M + 0.25, y: y + 0.82, w: 6.4, h: 0.28, fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
  });
  s.addText("完成后：缩略图悬挂刘海 2.5s → 底部浮条三连", { x: M, y: 4.72, w: 6.9, h: 0.35, fontSize: 14, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
  s.addText([
    { text: "复制（PNG+TIFF 双格式，兼容 Electron 应用）", options: { bullet: bu(), breakLine: true } },
    { text: "编辑（9 工具标注器：矩形/椭圆/箭头/画笔/文字/高亮/马赛克/裁剪/选择）", options: { bullet: bu(), breakLine: true } },
    { text: "在 Finder 中显示（按设置自动存档到 ~/Pictures/ClipIsland）", options: { bullet: bu() } },
  ], { x: M, y: 5.12, w: 6.9, h: 1.3, fontSize: 12.5, fontFace: FONT, color: MUTED, margin: 0, paraSpaceAfter: 6 });
  framedImage(s, "/tmp/ci-render/popup-bar-dark.png", 8.6, 2.4, 3.7, 2.48);
  s.addText("截图浮条 · 6s 自动消失，悬停暂停", { x: 8.6, y: 5.0, w: 3.7, h: 0.3, align: "center", fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
}

// ---------- 6 interaction: security ----------
{
  const s = baseSlide("交互逻辑 ③", "06");
  title(s, "安全：加密不是开关，是一套完整的状态机", "对标并修复 copyx：锁定期间的内容不再被静默丢弃");
  framedImage(s, "/tmp/ci-render/panel-locked-dark.png", M, 2.0, 5.6, 3.65);
  s.addText("面板内锁定屏：密码 / 触控 ID 解锁", { x: M, y: 5.8, w: 5.6, h: 0.3, align: "center", fontSize: 11, fontFace: FONT, color: MUTED, margin: 0 });
  const steps = [
    ["启用", "AES-256-GCM + PBKDF2（600k 迭代）派生密钥，既有条目原地加密迁移"],
    ["锁定", "密钥仅存内存；文本与图片在 SQLite 和磁盘上都是密文，去重哈希换成 HMAC（连“内容相等”都不泄漏）"],
    ["锁定期复制", "缓存在内存，绝不落盘——解锁后自动合并入加密历史"],
    ["解锁", "主密码或触控 ID（Keychain 拆分设计）；自动锁定 1–60 分钟可调"],
  ];
  steps.forEach((st, i) => {
    const y = 1.95 + i * 1.15;
    s.addShape(p.shapes.OVAL, { x: 6.85, y: y + 0.04, w: 0.5, h: 0.5, fill: { color: ACCENT } });
    s.addText(String(i + 1), { x: 6.85, y: y + 0.04, w: 0.5, h: 0.5, align: "center", valign: "middle", fontSize: 16, fontFace: FONT, bold: true, color: "FFFFFF", margin: 0 });
    s.addText(st[0], { x: 7.55, y, w: 5.2, h: 0.32, fontSize: 14.5, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
    s.addText(st[1], { x: 7.55, y: y + 0.34, w: 5.25, h: 0.66, fontSize: 11.5, fontFace: FONT, color: MUTED, margin: 0 });
  });
  s.addText("密码管理器带隐藏标记的内容永不入库 · 全程 0 网络请求", {
    x: 6.85, y: 6.6, w: 6.0, h: 0.32, fontSize: 12, fontFace: FONT, color: ACCENT, margin: 0,
  });
}

// ---------- 7 engineering ----------
{
  const s = baseSlide("工程与性能", "07");
  title(s, "性能不是口号，是八组实测数字", "全部来自自测与运行时探针，可复现（docs/ACCEPTANCE.md）");
  const stats = [
    ["1.6MB", "安装包体积", "纯 SwiftPM 组装，零第三方依赖"],
    ["74KB", "单张缩略图驻留", "ImageIO 降采样，替代 38MB 全量解码"],
    ["+0.7MB", "大图捕获后 RSS", "4000×2500 只读压缩数据"],
    ["<0.3MB", "面板开合循环增量", "重复开合不增长的平坦曲线"],
    ["113/113", "逻辑自测通过", "含 PBKDF2 RFC 向量与加密往返"],
    ["28 项", "运行时验收矩阵", "分布式通知钩子驱动全 UI 状态机"],
    ["600k", "PBKDF2 迭代次数", "RFC 向量校验的密钥派生"],
    ["0", "网络请求", "监控/截图/OCR 全部本机完成"],
  ];
  stats.forEach((st, i) => {
    const col = i % 4, row = Math.floor(i / 4);
    const x = M + col * 3.13, y = 2.0 + row * 2.35;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y, w: 2.85, h: 2.05, rectRadius: 0.1, fill: { color: CARD }, line: { color: LINE, width: 0.75 } });
    s.addText(st[0], { x, y: y + 0.22, w: 2.85, h: 0.75, align: "center", fontSize: 34, fontFace: FONT, bold: true, color: i === 0 ? ACCENT : TEXT, margin: 0 });
    s.addText(st[1], { x, y: y + 1.02, w: 2.85, h: 0.34, align: "center", fontSize: 13, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
    s.addText(st[2], { x: x + 0.15, y: y + 1.38, w: 2.55, h: 0.6, align: "center", fontSize: 10.5, fontFace: FONT, color: MUTED, margin: 0 });
  });
  s.addNotes("全部数字可复现：RenderTool 离屏渲染、ps RSS 探针、SelfTest 断言。113 项自测覆盖去重/LRU/加密往返/锁定缓冲/热键解析/弹簧收敛。");
}

// ---------- 8 comparison ----------
{
  const s = baseSlide("竞品对比", "08");
  title(s, "与四个开源竞品的源码级对比", "证据级结论，非功能清单打勾——完整矩阵见 docs/COMPARISON.md");
  const header = ["维度", "ClipIsland", "copyx", "Sapphire", "tendedero", "shotx"].map((t, i) => ({
    text: t, options: { fill: { color: CARD }, color: i === 1 ? ACCENT : TEXT, bold: true, fontSize: 12.5, fontFace: FONT, align: "center", valign: "middle" },
  }));
  const mk = (v, hot) => ({ text: v, options: { color: hot ? ACCENT : MUTED, fontSize: 11.5, fontFace: FONT, align: "center", valign: "middle" } });
  const rows = [
    ["形态", mk("刘海岛+浮条", 1), mk("底部大面板"), mk("刘海平台"), mk("顶部晾衣绳"), mk("菜单栏")],
    ["剪贴板历史", mk("全类型+置顶", 1), mk("有"), mk("有"), mk("—"), mk("—")],
    ["自动粘贴", mk("CGEvent", 1), mk("osascript"), mk("仅复制"), mk("—"), mk("—")],
    ["截图+标注", mk("9 工具+撤销", 1), mk("—"), mk("—"), mk("截图晾晒"), mk("4 工具不可回改")],
    ["离线 OCR", mk("中文+预览", 1), mk("—"), mk("圈选搜索"), mk("—"), mk("无中文")],
    ["静态加密", mk("AES-GCM", 1), mk("Argon2"), mk("分文件加密"), mk("—"), mk("—")],
    ["敏感过滤", mk("实测生效", 1), mk("死代码"), mk("12 家清单"), mk("—"), mk("—")],
    ["测试", mk("113 项", 1), mk("26 项"), mk("54 文件"), mk("0"), mk("0")],
  ];
  s.addTable(
    [header, ...rows.map(r => [mk(r[0], 0).text ? { text: r[0], options: { color: TEXT, bold: true, fontSize: 11.5, fontFace: FONT, align: "left", valign: "middle", fill: { color: CARD } } } : r[0], ...r.slice(1)])],
    { x: M, y: 1.9, w: W - 2 * M, colW: [1.7, 2.35, 2.2, 2.2, 2.2, 2.15], rowH: 0.52, border: { pt: 0.5, color: LINE }, fill: { color: BG }, margin: 0.06 }
  );
  s.addText("Sapphire 功能最广（18 万行、含遥测与私有 API）；ClipIsland 的差异化 = 刘海原生 + 全链路整合 + 可验证的工程纪律。", {
    x: M, y: 6.75, w: W - 2 * M, h: 0.35, fontSize: 12, fontFace: FONT, color: MUTED, margin: 0,
  });
}

// ---------- 9 roadmap ----------
{
  const s = baseSlide("路线图", "09");
  title(s, "下一步：把打磨层补齐到 A 级", "每一项都来自源码级对比的可量化差距");
  const items = [
    ["动画档位", "Sapphire 式 Snappy/Fluid/Calm 三档 + 肩部圆角形状，内容与窗口单一物理驱动"],
    ["事件驱动监控", "全局 ⌘C 键盘事件 + 自适应轮询，功耗再降、捕获更快"],
    ["本地化", "L() 骨架先落 zh-Hans/en，对齐 tendedero 的 10 语言实践"],
    ["Developer ID", "签名 + 公证，告别右键打开和 xattr"],
    ["岛模块扩展", "天气/番茄钟等插件位（架构已留模块化接口）"],
  ];
  items.forEach((it, i) => {
    const x = M + i * 2.51;
    s.addShape(p.shapes.ROUNDED_RECTANGLE, { x, y: 2.3, w: 2.25, h: 0.62, rectRadius: 0.09, fill: { color: CARD }, line: { color: ACCENT, width: 1 } });
    s.addText("P" + (i < 2 ? 0 : 1), { x, y: 2.3, w: 2.25, h: 0.62, align: "center", valign: "middle", fontSize: 18, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
    if (i < items.length - 1) s.addText("→", { x: x + 2.24, y: 2.38, w: 0.28, h: 0.5, align: "center", fontSize: 16, fontFace: FONT, color: MUTED, margin: 0 });
    s.addText(it[0], { x: x - 0.05, y: 3.1, w: 2.35, h: 0.35, align: "center", fontSize: 14.5, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
    s.addText(it[1], { x: x - 0.08, y: 3.5, w: 2.42, h: 1.5, align: "center", fontSize: 10.5, fontFace: FONT, color: MUTED, margin: 0 });
  });
  s.addText("已有基础：刘海几何/弹簧动画/加密/截图管线均已模块化，扩展不推倒重来。", {
    x: M, y: 5.35, w: W - 2 * M, h: 0.35, fontSize: 13, fontFace: FONT, color: MUTED, margin: 0, align: "center",
  });
}

// ---------- 10 closing ----------
{
  const s = baseSlide("立即体验", "10");
  s.addText("少装三个常驻工具，", { x: M, y: 2.3, w: W - 2 * M, h: 0.8, align: "center", fontSize: 40, fontFace: FONT, bold: true, color: TEXT, margin: 0 });
  s.addText("把刘海还给效率。", { x: M, y: 3.15, w: W - 2 * M, h: 0.8, align: "center", fontSize: 40, fontFace: FONT, bold: true, color: ACCENT, margin: 0 });
  s.addImage({ path: "/tmp/ci-render/strip-extended.png", x: W / 2 - 2.85, y: 4.35, w: 5.7, h: 0.455 });
  s.addText("github.com/ZiyueZhang/ClipIsland · Releases 下载 ClipIsland.app", {
    x: M, y: 5.3, w: W - 2 * M, h: 0.4, align: "center", fontSize: 16, fontFace: FONT, color: MUTED, margin: 0,
  });
  s.addText("或从源码构建：git clone && ./scripts/build-app.sh", {
    x: M, y: 5.8, w: W - 2 * M, h: 0.35, align: "center", fontSize: 13, fontFace: FONT, color: MUTED, margin: 0,
  });
}

p.writeFile({ fileName: "/Users/zzy/Desktop/Zcodetest/ClipIsland/docs/ClipIsland-产品介绍.pptx" }).then(() => console.log("deck written"));
