// 生成《黄河记忆》10 分钟路演 PPT（12 页，简体中文）。
//
// 为什么要写成脚本而不是手工拖：这份稿子要和设计方案.md 的 §1/§4/§8 对账，
// 数字一改就得重出；盲评另有一条硬约束——包内正文不得出现院校与队名，
// 这条由 tools/make_submission_pkg.py 的出包自检断言（它会展开 pptx 读
// 嵌套 xml 部件与 docProps），不靠人眼。
//
// 出稿后必跑的一步：补东亚字体槽，否则中文在评审机掉成默认 CJK——
//   python -I tools/pptx_ea_font.py 路演PPT-提交稿.pptx "Microsoft YaHei"
// 且必须排在 applyTheme 之后（applyTheme 会重写 theme，把空槽写回去）。
//
// 完整复现命令（本机实测）：
//   NODE_PATH="$PWD/_scratch/deckbuild/node_modules" \
//   PPTX_APPLY_THEME="<pptx 技能目录>/scripts/apply_theme.js" \
//   node tools/make_roadshow_deck.cjs
//   python -I tools/pptx_ea_font.py 路演PPT-提交稿.pptx "Microsoft YaHei"
//
// 为什么 NODE_PATH 不能省，以及危险到底在哪（2026-11-01 实测纠正）：
// 缺 NODE_PATH 时 applyTheme 找不到 jszip，**它会 throw、退出码 1**，
// 并明写 "Nothing was changed"——所以不是静默降级。真正的坑是
// `writeFile` 排在 applyTheme 之前，坏稿已经落盘：实测留下一份 12 页齐全、
// 但 accent1 = 4472C4（Office 默认蓝）的 pptx。谁用 `| tail` /
// `| Out-String` 这类写法吞掉退出码，就把蓝稿当成品交了（本项目
// PITFALLS #65 批评过的正是这个）。出稿后请验一次配色再信它：
//   python -I tools/pptx_ea_font.py <deck> "Microsoft YaHei" "9C4A2F"
// 第三个参数会复验 theme 里 accent1 到位，缺位即失败退出。
//
// 配色与母题取自作品自身的设计令牌（common/DesignTokens.ets + EraTheme.ets）：
// 页面底近白 FBFAF8、卡片纯白、主墨 141210、强调赭红 9C4A2F，
// 六个年代层色构成贯穿全篇的「地层剖面」母题——它是内容（六年代），
// 不是装饰条。
const path = require("path");
// 依赖解析：先按 Node 常规路径找（仓库内、全局、或 NODE_PATH），
// 找不到才退到本机那个 gitignored 的临时安装位置。写死 _scratch 会让
// 新克隆直接跑不起来——这个脚本已经随交付包发给评委，必须可复现。
// 缺依赖时：npm install pptxgenjs --registry=https://registry.npmmirror.com
let pptxgen;
try {
  pptxgen = require("pptxgenjs");
} catch (_e) {
  pptxgen = require(path.join(__dirname, "..", "_scratch", "deckbuild",
                              "node_modules", "pptxgenjs"));
}

// ── 设计令牌（与代码同源，改色先改这里再改代码，两边对账）────────────────
const C = {
  page: "FBFAF8",   // SURFACE_PAGE 页面底（近白）
  card: "FFFFFF",   // SURFACE_CARD 卡片面
  raised: "F2F0EC", // SURFACE_RAISED 浮起面
  ink: "141210",    // INK 主墨
  body: "3D3833",   // BODY 正文
  sub: "6E675E",    // SUB 次级
  accent: "9C4A2F", // ACCENT 赭红
  hair: "DED8CC",   // LINE_HAIR 分隔
};
// 六年代层色 = EraTheme.ERA_COLORS，顺序即地层自上而下的年代序
const ERA = [
  { id: "song", name: "宋", label: "瓷青", color: "7F97A4", ink: "1F1B16" },
  { id: "hantang", name: "汉唐", label: "釉陶黄", color: "B98A44", ink: "1F1B16" },
  { id: "zhou", name: "周", label: "礼玉灰青", color: "75888F", ink: "1F1B16" },
  { id: "xiashang", name: "夏商", label: "青铜绿", color: "4E6B52", ink: "F5EFE2" },
  { id: "longshan", name: "龙山", label: "磨光黑", color: "332E29", ink: "F5EFE2" },
  { id: "yangshao", name: "仰韶", label: "彩陶红褐", color: "8E4028", ink: "F5EFE2" },
];
const HEAD = "Microsoft YaHei";
const BODY = "Microsoft YaHei";

const THEME = {
  name: "HuangHeMemory",
  headFontFace: HEAD,
  bodyFontFace: BODY,
  colors: {
    dk1: C.ink, lt1: C.page, dk2: C.body, lt2: C.card,
    accent1: C.accent, accent2: ERA[5].color, accent3: ERA[4].color,
    accent4: ERA[3].color, accent5: ERA[2].color, accent6: ERA[1].color,
    hlink: C.accent, folHlink: C.sub,
  },
};

// 画布：LAYOUT_WIDE = 13.333" × 7.5"
const W = 13.333, H = 7.5, M = 0.72;      // 边距 0.72" > 技能要求的 0.5"
const CW = W - M * 2;

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";
pres.theme = { headFontFace: HEAD, bodyFontFace: BODY };
pres.company = "黄河记忆";
pres.title = "黄河记忆 · 黄河文化分布式数字档案（赛题一）";
pres.subject = "第三届河南省高等学校信息技术应用创新大赛（开源鸿蒙）赛题一 路演";
pres.author = "";   // 盲评：作者字段留空

// ── 版式（layout = 画框，卡片内容仍逐页排）──────────────────────────────
// 占位符必须写成 { placeholder: { text, options: { name, type, ... } } }：
// pptxgenjs 在 createSlideMaster 里把 options.name 改写成内部 placeholder 键
// （dist/pptxgen.cjs.js:1602），slide 侧按名匹配（同文件 2535 行）。
// 少写一层 options 就是 TypeError；名字打错则是静默错位到 0,0。
function ph(name, type, o) {
  return { placeholder: { text: "", options: Object.assign({ name: name, type: type,
                                                              fontFace: BODY }, o) } };
}
// 深色封面/收尾：米墨反白 + 地层母题
// 标题一律左对齐：占位符若不写 align，PowerPoint/LibreOffice 会按 title
// 占位默认居中，而标题框又为右上角小标让了宽度，结果就是「看着偏左的居中」，
// 且与左对齐的副题、正文不在一条起版线上。
pres.defineSlideMaster({
  title: "cover", background: { color: C.ink },
  objects: [ph("title", "title", { x: M, y: 2.05, w: CW, h: 1.05, color: "F5EFE2",
                                   fontFace: HEAD, fontSize: 40, bold: true,
                                   valign: "middle", align: "left" }),
            ph("sub", "body", { x: M, y: 3.16, w: CW, h: 0.5, color: "C9BFAF",
                                 fontSize: 16, valign: "middle", align: "left" })],
});
// 浅色内容页：标题固定在页顶
pres.defineSlideMaster({
  title: "content", background: { color: C.page },
  objects: [ph("title", "title", { x: M, y: 0.5, w: CW - 2.2, h: 0.72, color: C.ink,
                                   fontFace: HEAD, fontSize: 26, bold: true,
                                   valign: "middle", align: "left" })],
});

// 页脚与页码留在版式上，不逐页手写
function strata(slide, x, y, w, h, opts) {
  // 六条年代层带：自上而下 宋→仰韶（与首页剖面同口径）。
  // 它承载的是「六个年代档」这个内容事实，不是装饰色条。
  const o = opts || {};
  const bh = h / ERA.length;
  ERA.forEach((e, i) => {
    slide.addShape("rect", { x: x, y: y + i * bh, w: w, h: bh * (o.gap ? 0.82 : 1),
                             fill: { color: e.color },
                             transparency: o.dim ? 45 : 0 });
    if (o.labels) {
      slide.addText(e.name, { x: x + 0.12, y: y + i * bh, w: 0.9, h: bh,
                              fontSize: 10.5, color: e.ink, valign: "middle",
                              fontFace: BODY, margin: 0, isTextBox: true });
    }
  });
}
function card(slide, x, y, w, h, fill) {
  slide.addShape("roundRect", { x: x, y: y, w: w, h: h, fill: { color: fill || C.card },
                                line: { color: C.hair, width: 0.75 }, rectRadius: 0.09 });
}
function badge(slide, x, y, d, color, ch, fs) {
  slide.addShape("ellipse", { x: x, y: y, w: d, h: d, fill: { color: color } });
  slide.addText(ch, { x: x, y: y, w: d, h: d, fontSize: fs || 13, bold: true,
                      color: "FFFDF8", align: "center", valign: "middle",
                      fontFace: BODY, margin: 0, isTextBox: true });
}
function kicker(slide, text) {
  // 内容页右上角的年代小标：既补母题一致性，也交代「六年代」这件事
  slide.addText(text, { x: W - M - 2.9, y: 0.6, w: 2.9, h: 0.4, fontSize: 11,
                       color: C.sub, align: "right", fontFace: BODY,
                       margin: 0, isTextBox: true });
}

// ── S1 封面 ────────────────────────────────────────────────────────────
pres.addSection({ title: "开场" });
let s = pres.addSlide({ masterName: "cover", sectionTitle: "开场" });
strata(s, W - M - 1.15, 0, 1.15, H, { dim: false });
s.addText("黄河记忆", { placeholder: "title" });
s.addText("黄河文化分布式数字档案 · 开源鸿蒙赛题一路演", { placeholder: "sub" });
s.addText("完全离线  ·  42 处遗址 / 104 件文物  ·  六年代 × 四类型 × 五城市  ·  双轨分布式同步",
  { x: M, y: 4.62, w: CW - 1.6, h: 0.5, fontSize: 13.5, color: "9E9586",
    fontFace: BODY, margin: 0, isTextBox: true });
s.addText("版本 v1.3 ｜ 与代码实测数据对账至 2026-11-01",
  { x: M, y: 6.72, w: 8, h: 0.34, fontSize: 11, color: "7E7669",
    fontFace: BODY, margin: 0, isTextBox: true });
s.addNotes("开场 30 秒。口播：各位评委老师好，我们的作品叫《黄河记忆——黄河文化分布式数字档案》。"
  + "右侧这六条色带就是产品的骨架：仰韶到宋，六个年代一层一层压下来，用户挖过的层、读过的条目都会留在这部手机里，并且能在手机与平板之间自动同步。");

// ── S2 主张与差异化 ─────────────────────────────────────────────────────
pres.addSection({ title: "定位与合规" });
s = pres.addSlide({ masterName: "content", sectionTitle: "定位与合规" });
kicker(s, "§1.1 / §1.3");
s.addText("一句话：个人专属的文化遗产数字档案，不是文旅导览", { placeholder: "title" });
s.addText("赛题要求的三类个人数据——收藏、笔记、学习进度——全部做成可持久、可同步、可回看的显性产物；"
  + "内容以「遗址 + 文物」双实体组织，断网可读。",
  { x: M, y: 1.42, w: CW, h: 0.62, fontSize: 15, color: C.body, fontFace: BODY, margin: 0, isTextBox: true });
const diffs = [
  ["双", "文物子实体", "多数实现只做遗址单实体，漏掉赛题原文的「收藏遗址、文物条目」。本作每遗址挂 2–4 件代表文物，可独立收藏、笔记、被推荐。", ERA[5].color],
  ["进", "学习进度显性化", "赛题在功能 3 点名「学习进度」，多数实现跳过。本作做成五节研读勾选 + 六年代完成度，并纳入同步域。", ERA[3].color],
  ["离", "同步引擎与传输解耦", "合并算法是纯函数；单机双档案 Loopback 仿真可完整演示冲突裁决，真机走分布式 RDB，两轨共用同一份 MergeEngine。", ERA[2].color],
];
diffs.forEach((d, i) => {
  const cw = (CW - 0.6) / 3, x = M + i * (cw + 0.3), y = 2.3;
  card(s, x, y, cw, 3.6);
  badge(s, x + 0.32, y + 0.34, 0.58, d[3], d[0], 14);
  s.addText(d[1], { x: x + 0.32, y: y + 1.06, w: cw - 0.64, h: 0.5, fontSize: 16.5,
                    bold: true, color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(d[2], { x: x + 0.32, y: y + 1.62, w: cw - 0.64, h: 1.8, fontSize: 12.5,
                    color: C.body, fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 19, valign: "top" });
});
s.addNotes("1 分钟。这一页回答「凭什么是我们」：三处都是赛题条款里被多数实现漏掉的点，不是自我发挥。"
  + "第三条尤其关键——合并逻辑只有一份，仿真和真机共用，不存在演示专用的一套代码。");

// ── S3 赛题条款 → 功能映射 ──────────────────────────────────────────────
s = pres.addSlide({ masterName: "content", sectionTitle: "定位与合规" });
kicker(s, "§1.2 逐条合规清单");
s.addText("赛题条款 → 落点实现（逐条对账）", { placeholder: "title" });
// 表头用逐格选项，不用 addTable().updateRow()——后者在 v4 不是稳定返回类型
const hd = t => ({ text: t, options: { bold: true, color: C.ink, fill: { color: "EDE6D6" },
                                        fontSize: 12 } });
const rows = [[hd("赛题原文要求"), hd("本方案落点"), hd("章节")]];
[
  ["三维度组织：六年代 × 四类型 × 五城市", "内容 schema 锁死枚举；组内并集、组间交集", "§4.1"],
  ["详情多层级：图文/考古/历史/诗词/文旅", "五层级 + 自增「代表文物」第六区", "§4.1"],
  ["收藏遗址、文物条目（双实体）", "favorite 表 target_key 支持 site/relic", "§4.2"],
  ["笔记（文字+时间戳）+ 标签分类", "note 表 + tag 字典 + 预置三标签 + 自建", "§4.2"],
  ["同步收藏、笔记、学习进度三类数据", "六表统一纳入 MergeEngine 同步域", "§4.3 / §6"],
  ["冲突策略：最新时间戳为准、最终一致", "LWW-Element-Set + 墓碑删除 + 冲突历史可回看", "§6"],
  ["面板三要素：进度/最后同步/冲突数", "SyncPanel 全要素 + 方向动效", "§4.3"],
  ["全部预置本地、离线可编辑、恢复后自动同步", "rawfile 资产包 + 本地事务 + 网络恢复自动合并", "§4.3/§4.4"],
  ["相似度推荐（同期/同区域）", "本地评分：年代0.4+类型0.3+城市0.2+标签0.1+行为加权", "§4.5"],
  ["拓展：个人知识节点网络", "Canvas 力导向主题网络，节点可点击进详情", "§4.6"],
].forEach(r => rows.push(r));
s.addTable(rows, {
  x: M, y: 1.42, w: CW, colW: [4.35, 5.5, 1.3],
  rowH: 0.42, fontFace: BODY, fontSize: 11.5, color: C.body, valign: "middle",
  border: { type: "solid", color: C.hair, pt: 0.6 },
  fill: { color: C.card }, margin: 0.06,
  alternateRow: { fill: { color: C.raised } },
});
s.addText("超出赛题最低要求的自建增量：文物图录 104 件总目、全局检索、主题路线 7 条 40 站、笔记中心与最近删除、档案导出、版权溯源页（§4.7 / §4.8）。",
  { x: M, y: 6.32, w: CW, h: 0.56, fontSize: 12, italic: true, color: C.sub,
    fontFace: BODY, margin: 0, isTextBox: true });
s.addNotes("1.5 分钟，逐条快速念过即可，重点是「一条不漏」。"
  + "评委拿着赛题打分表，我们直接给他映射表。最后一行是加分项：图录、检索、路线、笔记中心、导出、版权页都是自建的。");

// ── S4 内容资产规模 ─────────────────────────────────────────────────────
pres.addSection({ title: "内容与架构" });
s = pres.addSlide({ masterName: "content", sectionTitle: "内容与架构" });
kicker(s, "§7.1 / §7.3");
s.addText("内容不是凑数：42 × 104 与一张配额矩阵", { placeholder: "title" });
const stats = [["42", "遗址", ERA[5].color], ["104", "代表文物", ERA[3].color],
               ["5", "段落/条", ERA[2].color], ["101", "张实拍 · 全覆盖", C.accent]];
stats.forEach((t, i) => {
  const cw = 2.05, x = M + i * (cw + 0.24);
  card(s, x, 1.5, cw, 1.42, C.card);
  s.addText([{ text: t[0], options: { fontSize: 36, bold: true, color: t[2] } }],
    { x: x, y: 1.62, w: cw, h: 0.72, align: "center", fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(t[1], { x: x, y: 2.36, w: cw, h: 0.4, align: "center", fontSize: 12,
                    color: C.sub, fontFace: BODY, margin: 0, isTextBox: true });
});
// 实拍已全覆盖（遗址头图 42/42、文物卡 104/104），旧的「已有 vs 待入藏」堆叠图
// 会变成 100%/0% 的空图，故改为**按许可分布**——它同时证明「逐条可溯」这件事，
// 与右下角的署名门禁互相印证（实测 CC BY-SA 4.0×83 + 3.0×1 + CC0×17 = 101）。
// 条形图第一个分类落在**底部**，所以最想让人先看见的那档要写在数组最后。
s.addChart(pres.charts.BAR, [
  { name: "署名张数", labels: ["CC0", "CC BY-SA 3.0", "CC BY-SA 4.0"], values: [17, 1, 83] },
], {
  x: M, y: 3.22, w: 6.5, h: 2.9, barDir: "bar",
  showTitle: true, title: "101 张实拍：逐条可溯（按许可）", titleFontSize: 12,
  titleColor: C.ink, chartColors: [C.accent],
  showValue: true, dataLabelPosition: "outEnd", dataLabelColor: C.ink, dataLabelFontSize: 10,
  showLegend: false,
  catAxisLabelColor: C.body, catAxisLabelFontSize: 11,
  valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" },
});
s.addText([
  { text: "五段落口径", options: { bold: true, color: C.ink, fontSize: 13 } },
  { text: "\n考古 / 历史 / 诗词 / 文旅 / 介绍，intro 与 arch 中位 481 / 536 字；诗词 42 处全部非空，真句真作者。", options: { fontSize: 12, color: C.body, breakLine: true } },
  { text: "\n版权工程化", options: { bold: true, color: C.ink, fontSize: 13, breakLine: true } },
  { text: "\nCC BY-SA 4.0×83 + 3.0×1 + CC0×17，101 张逐条登记作者 / 来源 / 许可 / 改动；遗址头图 42/42、文物卡 104/104 全覆盖（101 张去重，组合照与图集共用）。", options: { fontSize: 12, color: C.body, breakLine: true } },
], { x: 7.35, y: 3.3, w: CW - 6.63, h: 2.8, fontFace: BODY, margin: 0, isTextBox: true, paraSpaceAfter: 6, valign: "top" });
// 底部这条把 §7.1 的配额矩阵讲完：光有总数说明不了「不是凑数」。
s.addText("配额矩阵：每市 ≥6（三门峡 6 / 洛阳 10 / 郑州 11 / 开封 9 / 濮阳 6）· 六年代档每档 ≥4（实测 5–10）· 每遗址 2–4 件代表文物 · 诗词 42 处全部非空",
  { x: M, y: 6.42, w: CW, h: 0.4, fontSize: 11.5, color: C.sub, fontFace: BODY,
    margin: 0, isTextBox: true, valign: "top" });
s.addNotes("1 分钟。右图是版权工程：101 张实拍逐条登记作者、来源、许可、改动，遗址头图 42/42、"
  + "文物卡 104/104 全覆盖，去重后 101 个文件（组合照与图集共用）。被追问图源就答：全部来自维基共享，"
  + "「在包文件 ↔ 署名记录 ↔ 代码引用」三向对账由门禁硬卡；缺图仍走按材质分类的单色线稿并标明待入藏，"
  + "6 张自有示意图单独披露——绝不用生成图冒充实物影像。");

// ── S5 技术架构分层 ─────────────────────────────────────────────────────
s = pres.addSlide({ masterName: "content", sectionTitle: "内容与架构" });
kicker(s, "§3.1 / §3.2");
s.addText("六层架构：合并算法是纯函数，传输可替换", { placeholder: "title" });
const layers = [
  ["表现层", "ArkUI 页面 19 页", ERA[5].color, "F5EFE2"],
  ["状态层", "AppStorageV2 / 各页 @State", ERA[4].color, "F5EFE2"],
  ["领域层", "ContentParse · RecommendService · MergeEngine（纯函数）· SyncScheduler · AutoSync", ERA[3].color, "F5EFE2"],
  ["仓储层", "ContentRepo（只读）· UserDataRepo → LocalRdbImpl（分布式表注册 / PUSH / remoteQuery）", ERA[2].color, "1F1B16"],
  ["传输层", "LoopbackAdapter（单机双档案仿真）｜ SoftBusRdbTransport（真机分布式）", ERA[1].color, "1F1B16"],
  ["资产层", "rawfile/sites/*.json + webp + 子集化字体", ERA[0].color, "1F1B16"],
];
layers.forEach((l, i) => {
  const y = 1.5 + i * 0.79, h = 0.7;
  s.addShape("roundRect", { x: M, y: y, w: 2.1, h: h, fill: { color: l[2] }, rectRadius: 0.06 });
  s.addText(l[0], { x: M, y: y, w: 2.1, h: h, align: "center", valign: "middle",
                    fontSize: 13.5, bold: true, color: l[3], fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(l[1], { x: M + 2.28, y: y, w: CW - 2.28, h: h, valign: "middle",
                    fontSize: 12.5, color: C.body, fontFace: BODY, margin: 0, isTextBox: true });
});
s.addText("单 HAP，运行时不依赖第三方库；仅测试用 @ohos/hypium 与 @ohos/hamock。",
  { x: M, y: 6.42, w: CW, h: 0.34, fontSize: 11.5, color: C.sub, italic: true,
    fontFace: BODY, margin: 0, isTextBox: true });
s.addNotes("45 秒。指到传输层那一行说：这一层是两个实现——单机仿真和真机软总线。"
  + "上面五层完全共用，所以现场无论走哪条路，裁决逻辑都是同一份代码。");

// ── S6 合并算法与冲突裁决 ───────────────────────────────────────────────
pres.addSection({ title: "同步与冲突" });
s = pres.addSlide({ masterName: "content", sectionTitle: "同步与冲突" });
kicker(s, "§6.2 / T3 / T10");
s.addText("LWW 裁决：时间戳定胜负，败方版本还能回看", { placeholder: "title" });
const rules = [
  ["1", "双方都有同一条", "取 updateTime 大者为终态；完全平局时按 deviceId 字典序决胜（确定性，不靠运气）。"],
  ["2", "只有一方有", "直接纳入。一方是墓碑（isDeleted=1）而对方存活时，仍按时间戳裁决——删除本身就是一次编辑。"],
  ["3", "输出", "终态回写当前设备库；时间戳不同即记入冲突历史（保留败方版本快照，上限 50 条滚动）；刷新 lastSyncTime。"],
];
rules.forEach((r, i) => {
  const y = 1.5 + i * 1.14;
  badge(s, M, y, 0.5, C.accent, r[0], 15);
  s.addText(r[1], { x: M + 0.68, y: y - 0.03, w: 3.0, h: 0.44, fontSize: 14, bold: true,
                    color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(r[2], { x: M + 0.68, y: y + 0.4, w: 6.0, h: 0.7, fontSize: 12, color: C.body,
                    fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 17, valign: "top" });
});
card(s, 7.5, 1.5, CW - 6.9, 3.4, C.raised);
s.addText("模拟器端到端实测读数", { x: 7.72, y: 1.68, w: 5.0, h: 0.34, fontSize: 12.5,
    bold: true, color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
s.addText([
  { text: "采信 deviceB 10:46:14", options: { color: C.accent, bold: true, fontSize: 14, breakLine: true } },
  { text: "落选 deviceA 10:45:30", options: { color: C.sub, fontSize: 13, breakLine: true } },
  { text: " ", options: { fontSize: 6, breakLine: true } },
  { text: "两份档案是两个独立 RDBStore，快照袋只由「对方带来的档案」播种，因此同一条冲突可以在后续轮次反复演示——不会出现第二次同步就没冲突可记的假象。", options: { fontSize: 11.5, color: C.body } },
], { x: 7.72, y: 2.1, w: CW - 7.34, h: 2.6, fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 16, valign: "top" });
s.addText("复杂度 O(n)，n 为个人数据量（百级），单帧即可完成；分批 yield 只用于进度可视化。六张同步表全部持有 deviceId 列（关联表曾缺列导致「恒判远端赢」，2026-10-24 已原位迁移补齐）。",
  { x: M, y: 5.06, w: CW, h: 0.86, fontSize: 12, color: C.body, fontFace: BODY,
    margin: 0, isTextBox: true, lineSpacing: 17 });
s.addNotes("1.5 分钟。这里要主动交代那次翻车：note_tag / favorite_tag / tag 三张关联表原本没有 deviceId 列，"
  + "平局时两个空串比较恒为假，规则名不副实；补列并原位迁移后，三张表与其它表走同一套决胜。"
  + "评委问「这算分布式吗」——答：传输层是可替换适配器，真机走官方分布式 RDB 六表注册与软总线，代码在包里可查。");

// ── S7 双轨演示 ─────────────────────────────────────────────────────────
s = pres.addSlide({ masterName: "content", sectionTitle: "同步与冲突" });
kicker(s, "§4.3 双轨实现");
s.addText("同一份合并引擎，两种演示条件", { placeholder: "title" });
const cols = [
  ["单机双档案仿真", ERA[5].color, [
    "设备 A（手机）/ 设备 B（平板）两个身份各持一个独立 RDBStore",
    "在 A 身份下写的笔记，B 身份看不到——是真分离，不是同一个库贴标签",
    "点「组网同步」→ 分批次 yield 驱动进度 → 方向连线、百分比、最后同步时间、冲突数逐屏出现",
    "不依赖第二台设备，现场断网、丢设备照样能完整演示裁决",
  ]],
  ["真机分布式", ERA[3].color, [
    "六张同步表整体注册为分布式表，软总线发现可信组网设备",
    "先 remoteQuery 拉对端快照，交同一 MergeEngine 裁决落库，最后 SYNC_MODE_PUSH 推终态",
    "顺序不能反：先推会让本机旧值覆盖对端较新的行，再拉时冲突已被抹平",
    "监听网络可用事件，恢复后自动跑一次合并（30 秒冷却去抖、失败只记日志不打断用户）",
  ]],
];
cols.forEach((c, i) => {
  const cw = (CW - 0.4) / 2, x = M + i * (cw + 0.4), y = 1.46;
  card(s, x, y, cw, 3.44);
  s.addShape("ellipse", { x: x + 0.3, y: y + 0.28, w: 0.34, h: 0.34, fill: { color: c[1] } });
  s.addText(c[0], { x: x + 0.76, y: y + 0.24, w: cw - 1.06, h: 0.44, fontSize: 16, bold: true,
                    color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(c[2].map((t, k) => ({ text: t, options: { bullet: true, breakLine: k < c[2].length - 1 } })),
    { x: x + 0.32, y: y + 0.86, w: cw - 0.64, h: 2.4, fontSize: 12.5, color: C.body,
      fontFace: BODY, paraSpaceAfter: 9, lineSpacing: 17.5, margin: 0, isTextBox: true, valign: "top" });
});
// 这一页两卡只到 4.9"，底下整条空着——把 §4.3 的关键结论提成强调带：
// 评委最容易追问的就是「仿真和真机是不是两套逻辑」。
card(s, M, 5.14, CW, 1.06, C.raised);
s.addText([
  { text: "两轨共用同一个 MergeEngine，也共用同一个 SyncPanel。", options: { bold: true, fontSize: 14.5, color: C.ink, breakLine: true } },
  { text: "裁决逻辑只有一份——不存在「仿真一套、真机一套」的分叉；换的只是传输层实现。", options: { fontSize: 12.5, color: C.body } },
], { x: M + 0.3, y: 5.32, w: CW - 0.6, h: 0.74, fontFace: BODY, margin: 0,
     isTextBox: true, valign: "top", paraSpaceAfter: 4 });
s.addNotes("1 分钟。先讲左列：单机就能演完冲突全过程，这是给现场环境兜底的。"
  + "右列是真机口径，顺序那句是重点——先拉后推，反过来冲突就被抹平了。");

// ── S8 功能线一览 ───────────────────────────────────────────────────────
pres.addSection({ title: "功能与证据" });
s = pres.addSlide({ masterName: "content", sectionTitle: "功能与证据" });
kicker(s, "§4.1 – §4.8 · 19 页");
s.addText("功能线一览：五条必做 + 一条拓展 + 两处自建", { placeholder: "title" });
// 第 5 项是徽章字。原先取 f[0] 首字，F1–F5 全渲染成同一个「F」，
// 八个圈里五个长得一样等于没有信息量——改成每格一个可辨的意符。
const feats = [
  ["F1", "展示与检索", "六年代剖面首页、三维筛选（组内并集/组间交集）、五层级详情 + 代表文物横滑", ERA[5].color, "索"],
  ["F2", "收藏 · 笔记 · 标签", "任意条目收藏；笔记可挂 site/relic/section 三级；预置三标签 + 自建；左滑即墓碑删除", ERA[4].color, "藏"],
  ["F3", "分布式同步与面板", "双轨传输；进度 / 最后同步 / 冲突数三要素；败方快照可回看", ERA[3].color, "同"],
  ["F4", "离线", "全功能离线；恢复后自动合并", ERA[2].color, "线"],
  ["F5", "关联推荐", "年代0.4+类型0.3+城市0.2+标签0.1+行为加权，每条最多两条理由、可负反馈", ERA[1].color, "荐"],
  ["E1", "主题知识网络", "Canvas 力导向；节点点击进详情，返回后随收藏变化重算", ERA[0].color, "网"],
  ["自建", "图录 · 路线 · 检索", "104 件文物总目、7 条主题路线 40 站带完成度、跨实体全局检索命中高亮", C.accent, "录"],
  ["自建", "数据自治", "笔记中心与改关联、30 天最近删除可恢复、Markdown/JSON 档案导出、101 张实拍逐条署名页", C.accent, "治"],
];
feats.forEach((f, i) => {
  const col = i % 2, row = Math.floor(i / 2);
  const cw = (CW - 0.3) / 2, ch = 1.22, x = M + col * (cw + 0.3), y = 1.46 + row * (ch + 0.16);
  card(s, x, y, cw, ch);
  badge(s, x + 0.26, y + 0.3, 0.56, f[3], f[4], 14);
  s.addText(f[0] + " · " + f[1], { x: x + 0.96, y: y + 0.16, w: cw - 1.2, h: 0.36,
                    fontSize: 13, bold: true, color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(f[2], { x: x + 0.96, y: y + 0.54, w: cw - 1.2, h: 0.62, fontSize: 11.5,
                    color: C.body, fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 15.5, valign: "top" });
});
s.addNotes("1.5 分钟，两列各扫一遍。右下两条自建是差异化加分位：图录让文物脱离「挂在遗址下面」的从属位置，"
  + "数据自治那一格回答「用户的数据是不是真的归用户」——能导出、能恢复、能追溯署名。");

// ── S9 测试证据：单测分布 ───────────────────────────────────────────────
s = pres.addSlide({ masterName: "content", sectionTitle: "功能与证据" });
kicker(s, "§8 T1 / T8");
s.addText("158 条纯函数单测，全绿", { placeholder: "title" });
s.addChart(pres.charts.BAR, [{
  name: "用例数",
  // 21 套，逐文件实跑（2026-11-10）。条形图首个分类落在**顶部**（实测导出 PNG 确认），
  // 故按升序写、渲染出来才是「大到小自上而下」；写成降序会把最大的那根压到最底部。
  labels: ["条目目标", "路线", "筛选矩阵", "内容解析", "导出排版", "材质索引", "推荐",
           "档案导出", "自动同步", "导入裁决", "逻辑时钟", "调度器",
           "灯箱缩放", "文物推荐", "署名对账", "年代双轴", "力导向布局", "笔记回顾",
           "合并引擎", "网络图", "冲突标签"],
  values: [4, 4, 4, 6, 6, 6, 6, 7, 7, 7, 7, 7, 8, 8, 8, 9, 9, 9, 10, 11, 15],
}], {
  x: M, y: 1.42, w: 7.9, h: 5.05, barDir: "bar",
  showTitle: false, showLegend: false, showValue: true,
  dataLabelPosition: "outEnd", dataLabelColor: C.ink, dataLabelFontSize: 9,
  chartColors: [C.accent], catAxisLabelColor: C.body, catAxisLabelFontSize: 9.5,
  valAxisHidden: true, valGridLine: { style: "none" }, catGridLine: { style: "none" },
});
s.addText([
  { text: "158 / 158 通过，0 失败", options: { bold: true, fontSize: 19, color: C.accent, breakLine: true } },
  { text: "逐文件实跑于 2026-11-10，21 套；Node 侧执行，.ets 纯函数经 tsbuild 转译。", options: { fontSize: 12, color: C.body, breakLine: true } },
  { text: " ", options: { fontSize: 8, breakLine: true } },
  { text: "筛选矩阵 T1", options: { bold: true, fontSize: 13, color: C.ink, breakLine: true } },
  { text: "6 × 4 × 5 = 120 个三维组合全枚举，与独立朴素实现逐条对齐：非空 32 个（单测把下限钉在 30，防数据回填后矩阵塌缩无人察觉），空组合由 UI 空态承接。单维与两维筛选均无空路。", options: { fontSize: 12, color: C.body, breakLine: true } },
], { x: 8.85, y: 1.5, w: CW - 8.13, h: 4.4, fontFace: BODY, margin: 0, isTextBox: true, paraSpaceAfter: 5 });
s.addNotes("45 秒。强调这不是快照测试：合并引擎、推荐评分、筛选矩阵、导出排版、力导向布局都是纯函数，"
  + "可以脱离设备跑。矩阵那条要念——非空 32 / 下限 30 是防退化的护栏。");

// ── S10 工程治理与实机走查 ──────────────────────────────────────────────
s = pres.addSlide({ masterName: "content", sectionTitle: "功能与证据" });
kicker(s, "§8 · T5/T6/T9/T24/T25");
s.addText("十三道门禁挡在出包之前，屏上读数另有人复核", { placeholder: "title" });
const gov = [
  ["13 / 13", "门禁全绿", "schema 与图片引用对账、署名完整性、对比度 58 项、字号适老化、读屏标签、动效、令牌裸值、跨页间距、字重字族、tsbuild、单测——build-oh.bat 在 assembleHap 前调用，任一非 0 直接阻断出包", C.accent],
  ["23.62", "MiB signed HAP", "限 40MB；构成 rawfile 20.34 + modules.abc 2.16 + debug 符号表 0.85；从签名包内清点，脏条目 0", ERA[3].color],
  ["零", "INTERNET 权限", "离线不是「飞一次行模式」：module.json5 只声明 DISTRIBUTED_DATASYNC，系统层就发不出 HTTP；网络 API 仅用于订阅恢复事件", ERA[4].color],
];
gov.forEach((g, i) => {
  const cw = (CW - 0.6) / 3, x = M + i * (cw + 0.3);
  card(s, x, 1.44, cw, 2.5);
  s.addText(g[0], { x: x, y: 1.6, w: cw, h: 0.62, align: "center", fontSize: 30,
                    bold: true, color: g[3], fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(g[1], { x: x + 0.2, y: 2.24, w: cw - 0.4, h: 0.34, align: "center", fontSize: 12.5,
                    bold: true, color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(g[2], { x: x + 0.22, y: 2.62, w: cw - 0.44, h: 1.24, fontSize: 10.5,
                    color: C.body, fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 14, valign: "top" });
});
s.addText("屏上另有一轮人眼复核（T9–T15、T24、T25）", { x: M, y: 4.16, w: CW, h: 0.34,
  fontSize: 13.5, bold: true, color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
const probe = [
  "T9 按压反馈逐像素比对：几何型 chip 变化 20.8%、透明度型「‹ 返回」15.2%；期间修掉 60 处按压态因两套动画互斥而不显形的全量缺陷",
  "T11 网络图节点跳转：点遗址节点进详情、点文物节点进文物页，取消收藏后返回，图由「遗址 3 · 年代 2」自动变为「遗址 2 · 年代 1」",
  "T24 首轮真机构建：此前 P0–P3 代码从未通过 hvigor，本轮修掉 28 处 ArkTS 编译错误，逐屏走查 19 屏；查出「我的」页两个入口被顶出屏底完全不可达（阻断级）",
  "T25 导航制式统一：频道页只认底栏、子页只认 push + 返回，消除「在频道页点返回直接退出 App」与栈内频道页残影",
];
s.addText(probe.map((t, i) => ({ text: t, options: { bullet: true, breakLine: i < probe.length - 1 } })),
  { x: M, y: 4.56, w: CW, h: 1.9, fontSize: 11.5, color: C.body, fontFace: BODY,
    paraSpaceAfter: 7, lineSpacing: 16, margin: 0, isTextBox: true, valign: "top" });
s.addNotes("1 分钟。左二是包体、左三是离线的硬证据——零 INTERNET 权限比「我试过飞行模式」强得多。"
  + "下面四条要说得坦率：门禁只能证明写法合法，证明不了屏上真有反应，所以交互类另有实测脚本兜底。");

// ── S11 尚未闭合 ────────────────────────────────────────────────────────
pres.addSection({ title: "边界与展望" });
s = pres.addSlide({ masterName: "content", sectionTitle: "边界与展望" });
kicker(s, "§8 T4 / §10");
s.addText("我们没验的事，写在同一页上", { placeholder: "title" });
const open_ = [
  ["⏳", "T4 冷启动耗时 ≤2s", "读数尚未取到。BOOT 锚点已埋在 ContentRepo.load 前后（corpus ready: N sites in M ms），模拟器在线时一条 hilog 即可填数。取到之前，这一项不计入「已验证」。", ERA[1].color],
  ["⏳", "双真机可信组网", "分布式适配器与六表注册已实现并经端到端仿真验证，但两台真机同局域网的现场收敛仍需线下复核；现场以单机仿真演示裁决过程。", ERA[3].color],
  ["✅", "模拟器镜像口径", "已闭合：主 SDK 为 OpenHarmony API 26（满足 API≥12、模拟器免商用签名）；ArkTS 与 HarmonyOS 同源，同代码改 build-profile 即可切换复验。", ERA[5].color],
];
open_.forEach((o, i) => {
  const y = 1.5 + i * 1.56;
  card(s, M, y, CW, 1.4);
  badge(s, M + 0.3, y + 0.44, 0.52, o[3], o[0] === "✅" ? "✓" : "待", 13);
  s.addText(o[1], { x: M + 1.0, y: y + 0.2, w: 3.3, h: 0.5, fontSize: 14, bold: true,
                    color: C.ink, fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(o[2], { x: M + 1.0, y: y + 0.62, w: CW - 1.5, h: 0.68, fontSize: 11.5,
                    color: C.body, fontFace: BODY, margin: 0, isTextBox: true, lineSpacing: 16, valign: "top" });
  s.addText(o[0], { x: W - M - 1.0, y: y + 0.2, w: 0.8, h: 0.4, fontSize: 13, bold: true,
                    color: o[0] === "✅" ? ERA[5].color : C.accent, align: "right",
                    fontFace: BODY, margin: 0, isTextBox: true });
});
s.addText("原则：宁可留一个明确的「未验证」，也不填一个看起来像结论的估计值。",
  { x: M, y: 6.26, w: CW, h: 0.36, fontSize: 12.5, italic: true, bold: true,
    color: C.accent, fontFace: BODY, margin: 0, isTextBox: true });
s.addNotes("40 秒，主动讲。这页是加分项而不是扣分项：T4 我们只写了锚点没写读数，"
  + "真机组网我们标注了「待线下复核」并准备了单机兜底。盲评最怕的就是文档与代码对不上。");

// ── S12 现场演示路线 + 收尾 ─────────────────────────────────────────────
pres.addSection({ title: "收尾" });
s = pres.addSlide({ masterName: "cover", sectionTitle: "收尾" });
strata(s, 0, 0, 1.15, H, {});
s.addText("接下来 5 分钟，按这条动线走", { placeholder: "title" });
const steps = [
  ["0:00", "首页 · 六年代剖面", "缓慢上滑一次，露出六张年代卡"],
  ["0:25", "检索筛选", "选「龙山 + 洛阳」，组间交集，翻出非空结果"],
  ["1:00", "详情五层级", "考古 / 历史 / 诗词 / 文旅 / 介绍 + 代表文物"],
  ["2:00", "收藏 · 笔记 · 研读", "收藏彩陶残片，写一条笔记打标签，勾「已研读」"],
  ["2:45", "同步与冲突", "切设备 B 改同一条笔记 → 组网同步 → 冲突历史可回看败版本"],
  ["3:45", "智能推荐", "点「脉络」看理由与负反馈"],
  ["4:20", "知识网络", "点节点进详情，返回后图随收藏重算"],
];
// 4 行 × 2 列 = 8 槽 ≥ 7 步。护栏必须按「本行正文底边」算，且留出的余量要
// 真能容下第 4 行：上一版 y=3.62+row*0.72 配 `y+0.76>6.5` 时，第 7 步
// （4:20 知识网络）被 return 静默丢掉——丢内容比重叠更糟。
steps.forEach((st, i) => {
  const col = i % 2, row = Math.floor(i / 2);
  const cw = (CW - 1.15 - 0.3) / 2, y = 3.58 + row * 0.70;
  const x = 1.45 + col * (cw + 0.3);
  if (y + 0.76 > 6.55) {
    throw new Error("动线第 " + (i + 1) + " 步放不下：请调小行距或减少步骤");
  }
  s.addText(st[0], { x: x, y: y, w: 0.86, h: 0.34, fontSize: 11.5, bold: true,
                     color: C.accent, fontFace: BODY, margin: 0, isTextBox: true });
  s.addText(st[1], { x: x + 0.92, y: y, w: cw - 1.0, h: 0.34, fontSize: 13, bold: true,
                     color: "F5EFE2", fontFace: HEAD, margin: 0, isTextBox: true });
  s.addText(st[2], { x: x + 0.92, y: y + 0.34, w: cw - 1.0, h: 0.42, fontSize: 10.5,
                     color: "A29A8C", fontFace: BODY, margin: 0, isTextBox: true });
});
s.addText("黄河记忆 · 谢谢各位老师", { x: 1.45, y: 6.62, w: 8, h: 0.5, fontSize: 17,
  bold: true, color: "F5EFE2", fontFace: HEAD, margin: 0, isTextBox: true });
s.addNotes("收尾 + 交棒演示。兜底话术两条：真机没组上——「合并裁决算法是同一份，我用单机双档案仿真完整跑一遍给您看」；"
  + "模拟器卡顿——「这是模拟器性能问题，我这边有实机截图可以辅助说明」（design/verify/ 已备）。");

(async () => {
  // 默认输出就是交付件 `路演PPT-提交稿.pptx`（用户 2026-11-01 定为交付稿，
  // 打包脚本 INCLUDE_TOP 指向它）。重跑即原地覆盖——历史副本在
  // _scratch/deckbackups/。要出到别处用 --out= 显式指定。
  const argOut = (process.argv.find(a => a.startsWith("--out=")) || "").slice(6);
  const out = argOut ? path.resolve(__dirname, "..", argOut)
                     : path.join(__dirname, "..", "路演PPT-提交稿.pptx");
  require("fs").mkdirSync(path.dirname(out), { recursive: true });
  await pres.writeFile({ fileName: out });
  // applyTheme 由 pptx 技能提供，安装位置因人而异：只从环境变量取，
  // 不把任何人的绝对路径写进这份会随源码分发的脚本。
  // 不提供也能出稿——本篇配色全部是字面 hex，不依赖 scheme color，
  // 差别仅在 theme part 里少了主题名与主题字体字段。
  const mod = process.env.PPTX_APPLY_THEME;
  if (mod) {
    const { applyTheme } = require(mod);
    await applyTheme(out, THEME);
    console.log("theme applied");
  } else {
    console.log("warn: 未设 PPTX_APPLY_THEME，跳过主题写入（配色为字面色值，不受影响）");
  }
  console.log("saved", out);
  // pptxgenjs 只写 latin 字体槽，主题里 `<a:ea typeface=""/>` 留空，而母版按
  // `+mn-ea` 引用——空槽等于中文没指定字体，到评审机就落到默认 CJK（多为宋体），
  // 行宽与换行点全变，本地量好的版式不可复现。必须在 applyTheme **之后**补槽，
  // 否则主题重写会把空槽又写回去。
  console.log('下一步（必跑）：python -I tools/pptx_ea_font.py "' +
              path.relative(path.join(__dirname, ".."), out) + '" "Microsoft YaHei"');
})();
