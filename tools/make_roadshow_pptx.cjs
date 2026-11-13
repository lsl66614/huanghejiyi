// 路演 PPT 生成器：10 分钟口径，结构取 设计方案.md，讲稿取 docs/演示脚本.md。
//
// 为什么用脚本而不手工在 PowerPoint 里拼：这份稿子要跟着实测数据改
// （语料分布、门禁数、包体），手改的稿子每次都得重排一遍；脚本化之后
// 改数据就是改几个常量。
//
// 跑法（项目根，NODE_PATH 指向全局 node_modules）：
//   NODE_PATH="$APPDATA/npm/node_modules" node tools/make_roadshow_pptx.cjs
// 主题色由 skills/pptx/scripts/apply_theme.js 落进 theme part，路径可用
// HH_PPTX_APPLY_THEME 覆盖。
const path = require("path");
const pptxgen = require("pptxgenjs");

const APPLY_THEME = process.env.HH_PPTX_APPLY_THEME ||
  path.join(process.env.LOCALAPPDATA || "",
    "Claude-3p/local-agent-mode-sessions/skills-plugin/00000000-0000-4000-8000-000000000001/337218d2-eead-4fc1-9751-df69da5ff12f/skills/pptx/scripts/apply_theme.js");
const OUT = process.argv[2] || "路演PPT-初稿.pptx";

// ── 主题：全部取自工程自己的设计令牌与年代色（EraTheme.ets / DesignTokens.ets）
const ERA = {
  yangshao: "8E4028", longshan: "332E29", xiashang: "4E6B52",
  zhou: "75888F", hantang: "B98A44", song: "7F97A4",
};
const T = {
  name: "黄河记忆",
  headFontFace: "Microsoft YaHei",
  bodyFontFace: "Microsoft YaHei",
  colors: {
    dk1: "141210", lt1: "FBFAF8", dk2: "3D3833", lt2: "FFFFFF",
    lt3: "F2F0EC", dk3: "6E675E",
    accent1: "9C4A2F", accent2: "332E29", accent3: "4E6B52",
    accent4: "75888F", accent5: "B98A44", accent6: "7F97A4",
    hlink: "9C4A2F", folHlink: "6E675E",
  },
};
const C = T.colors;
const ON_DARK = "F5EFE2";

// ── 实测数据（2026-11-01 从 rawfile/sites/*.json 与构建产物量出，非估值）
const D = {
  sites: 42, relics: 104, pages: 19, photos: 76, aiImgs: 6, fonts: 2,
  routes: 7, stops: 40, gates: 13, unitTests: 96, hapMB: "19.19",
  eraSites: [10, 5, 7, 6, 8, 6],
  eraRelics: [25, 12, 19, 14, 20, 14],
  eraNames: ["仰韶", "龙山", "夏商", "周", "汉唐", "宋"],
  eraColors: [ERA.yangshao, ERA.longshan, ERA.xiashang, ERA.zhou, ERA.hantang, ERA.song],
  city: "郑州 11 · 洛阳 10 · 开封 9 · 三门峡 6 · 濮阳 6",
  type: "都邑 28 · 墓葬 7 · 窑址 4 · 古建筑 3",
  matrix: "6 年代 × 4 类型 × 5 城市 = 120 组合，非空 32（空组合走空态承接，单维与两维零空路）",
};

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";            // 13.333" × 7.5"，必须先设再建页
pres.author = "黄河记忆项目组";           // 盲评：不写院校与师生
pres.company = "赛题一参赛作品";
pres.title = "黄河记忆 · 黄河文化分布式数字档案";
pres.theme = T;

const W = 13.333, H = 7.5, M = 0.62;

// 分节要先声明再用：addSlide({sectionTitle}) 是按标题在已有分节里查，
// 查不到就只警告一句、把页丢进 Default 分节。
const SECTIONS = ["开篇", "合规与产品", "内容与数据", "技术核心", "质量与收尾"];
SECTIONS.forEach((t) => pres.addSection({ title: t }));

// ── 版式：一页一框架，正文用命名占位（改样式只改这里）
pres.defineSlideMaster({
  title: "COVER", background: { color: C.accent2 },
  objects: [{ rect: { x: 0, y: 0, w: 0.02, h: 0.02, fill: { color: C.accent2 } } }],
});
pres.defineSlideMaster({
  title: "DIVIDER", background: { color: C.accent2 },
});
pres.defineSlideMaster({
  title: "CONTENT", background: { color: C.lt1 },
  placeholders: {
    title: { x: M, y: 0.42, w: W - 2 * M, h: 0.72, fontSize: 30, bold: true,
      color: C.dk1, fontFace: T.headFontFace, align: "left", valign: "top" },
    kicker: { x: M, y: 1.16, w: W - 2 * M, h: 0.34, fontSize: 13,
      color: C.dk3, fontFace: T.bodyFontFace, align: "left" },
    body: { x: M, y: 1.72, w: W - 2 * M, h: H - 2.35, fontSize: 15,
      color: C.dk2, fontFace: T.bodyFontFace, valign: "top" },
  },
});

// 六年代地层：封面的母题元素，每格都是真实计数，不是装饰条
function strata(slide, x, y, w, h) {
  const total = D.eraSites.reduce((a, b) => a + b, 0);
  let cur = y;
  for (let i = 0; i < 6; i++) {
    const hh = (h * D.eraSites[i]) / total;
    slide.addShape(pres.shapes.RECTANGLE, {
      x, y: cur, w, h: hh, fill: { color: D.eraColors[i] }, line: { type: "none" },
      objectName: `strata-${D.eraNames[i]}`,
    });
    if (hh > 0.3) {
      slide.addText([
        { text: D.eraNames[i], options: { fontSize: 12, bold: true, breakLine: true } },
        { text: `${D.eraSites[i]} 址 / ${D.eraRelics[i]} 物`, options: { fontSize: 9 } },
      ], {
        x: x + 0.12, y: cur, w: w - 0.2, h: hh, margin: 0, valign: "middle",
        color: i === 0 || i === 1 || i === 2 ? ON_DARK : C.dk1,
        objectName: `strata-label-${i}`,
      });
    }
    cur += hh;
  }
}

function statCards(slide, items, y) {
  const gap = 0.28, w = (W - 2 * M - gap * (items.length - 1)) / items.length;
  items.forEach((it, i) => {
    const x = M + i * (w + gap);
    slide.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x, y, w, h: 1.62, fill: { color: C.lt2 }, rectRadius: 0.06,
      shadow: { type: "outer", color: "141210", opacity: 0.1, blur: 8, offset: 2, angle: 90 },
      line: { color: C.lt3, width: 1 }, objectName: `stat-card-${i}`,
    });
    slide.addText(it[0], {
      x: x + 0.2, y: y + 0.16, w: w - 0.4, h: 0.72, margin: 0,
      fontSize: 40, bold: true, color: it[2] || C.accent1,
      objectName: `stat-num-${i}`,
    });
    slide.addText(it[1], {
      x: x + 0.2, y: y + 0.96, w: w - 0.4, h: 0.5, margin: 0,
      fontSize: 12, color: C.dk3, objectName: `stat-label-${i}`,
    });
  });
}

function rowList(slide, rows, x, y, w) {
  rows.forEach((r, i) => {
    const yy = y + i * 0.78;
    slide.addShape(pres.shapes.RECTANGLE, {
      x, y: yy, w: 0.34, h: 0.34, fill: { color: r[2] || C.accent1 },
      line: { type: "none" }, objectName: `row-chip-${i}`,
    });
    slide.addText(String(i + 1), {
      x, y: yy, w: 0.34, h: 0.34, margin: 0, align: "center", valign: "middle",
      fontSize: 13, bold: true, color: ON_DARK, objectName: `row-chip-num-${i}`,
    });
    slide.addText([
      { text: r[0], options: { fontSize: 15, bold: true, color: C.dk1, breakLine: true } },
      { text: r[1], options: { fontSize: 12, color: C.dk3 } },
    ], { x: x + 0.52, y: yy - 0.06, w: w - 0.52, h: 0.68, margin: 0, valign: "top",
      objectName: `row-text-${i}` });
  });
}

// ═══ 1 封面 ═══
{
  const s = pres.addSlide({ masterName: "COVER", sectionTitle: "开篇" });
  strata(s, W - M - 3.0, 0, 3.0, H);
  s.addText("第三届河南省高等学校信息技术应用创新大赛 · 开源鸿蒙 · 赛题一", {
    x: M, y: 0.55, w: 9.1, h: 0.34, margin: 0, fontSize: 12, color: ON_DARK,
    transparency: 25, objectName: "cover-contest",
  });
  s.addText("黄河记忆", {
    x: M, y: 1.5, w: 9.1, h: 1.5, margin: 0, fontSize: 76, bold: true,
    color: ON_DARK, fontFace: T.headFontFace, objectName: "cover-title",
  });
  s.addText("黄河文化分布式数字档案", {
    x: M, y: 3.1, w: 9.1, h: 0.6, margin: 0, fontSize: 26, color: ERA.hantang,
    objectName: "cover-subtitle",
  });
  s.addText([
    { text: "完全离线可用 · 遗址与文物双实体 · 分布式同步可裁决", options: { breakLine: true } },
    { text: "HarmonyOS / OpenHarmony API 26 · ArkTS + ArkUI · Stage 模型", options: {} },
  ], {
    x: M, y: 3.95, w: 9.1, h: 1.0, margin: 0, fontSize: 15, color: ON_DARK,
    transparency: 12, paraSpaceAfter: 6, objectName: "cover-meta",
  });
  s.addText(`42 处遗址 · 104 件代表文物 · ${D.pages} 个页面 · ${D.photos} 张实拍逐条署名`, {
    x: M, y: 6.35, w: 9.1, h: 0.4, margin: 0, fontSize: 13, bold: true,
    color: ERA.song, objectName: "cover-foot",
  });
  s.addNotes("【0:00–0:30 开场】\n各位评委老师好，我们的作品叫《黄河记忆——黄河文化分布式数字档案》，" +
    "赛题一，开源鸿蒙 API 26。\n一句话定位：一个完全离线的个人文化遗产档案应用——42 处黄河中下游遗址、" +
    "104 件代表文物，按六年代 × 四类型 × 五城市整编；用户挖过的层、读过的条目都留在应用里，" +
    "并且能在手机与平板之间自动同步。\n（右侧地层柱按各年代遗址数量分层，不是装饰。）");
}

// ═══ 2 结论前置 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "开篇" });
  s.addText("先把结论说在前面", { placeholder: "title" });
  s.addText("赛题要的不是一个文旅导览，是一份「个人专属」的文化遗产档案——所以三件事必须成立",
    { placeholder: "kicker" });
  s.addText([
    { text: "结构化：内容不是网页堆，是可筛选可校验的数据集", options: { bold: true, fontSize: 16, color: C.dk1, breakLine: true } },
    { text: "双实体：遗址与文物都能被收藏、被笔记、被推荐", options: { fontSize: 16, color: C.dk1, breakLine: true } },
    { text: "可裁决：冲突不是「覆盖掉」，是有规则、有留痕、可回看", options: { fontSize: 16, color: C.dk1 } },
  ], { x: M, y: 1.75, w: 7.2, h: 1.5, margin: 0, paraSpaceAfter: 10, objectName: "claim-list" });
  statCards(s, [
    [String(D.sites), "黄河中下游遗址", ERA.yangshao],
    [String(D.relics), "代表文物（可独立收藏）", ERA.xiashang],
    [String(D.pages), "页面（全部实机走查过）", ERA.zhou],
    [String(D.photos), "实拍逐条署名", ERA.hantang],
  ], 3.55);
  s.addText("本页每个数字都可从仓库里量出来：语料读 rawfile/sites/*.json，页面数读 pages/*.ets，署名读 rawfile/attribution.json。",
    { x: M, y: 5.5, w: W - 2 * M, h: 0.7, margin: 0, fontSize: 12, color: C.dk3,
      objectName: "claim-note" });
  s.addNotes("【0:30–1:30 结论与规模】\n先把结论说在前面。我们把它当成一份「个人专属档案」来做，不是文旅导览，" +
    "所以三件事必须成立：内容结构化、遗址与文物双实体、同步冲突可裁决。\n" +
    "屏幕上四个数字全部可以从仓库量出来，不是估计值——语料条数读 rawfile/sites 的 JSON，" +
    "页面数读 pages 目录，署名数读 attribution.json。\n衔接：接下来对着赛题条款逐条说落点。");
}

// ═══ 3 赛题条款 → 落点 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "合规与产品" });
  s.addText("赛题条款 → 实现落点", { placeholder: "title" });
  s.addText("逐条对照，不做「大概都实现了」的表述", { placeholder: "kicker" });
  const rows = [
    [{ text: "赛题原文要求", options: { bold: true, color: ON_DARK, fill: { color: C.accent2 } } },
     { text: "实现落点", options: { bold: true, color: ON_DARK, fill: { color: C.accent2 } } },
     { text: "证据", options: { bold: true, color: ON_DARK, fill: { color: C.accent2 } } }],
    ["三维组织：六年代 × 四类型 × 五城市", "schema 锁死枚举；组内并集、组间交集", "120 组合遍历，非空 32，单/两维零空路"],
    ["多层级详情：图文/考古/历史/诗词/文旅", "五层级 Tabs + 自增「代表文物」第六区", "42/42 遗址诗词非空，真句真作者真出处"],
    ["收藏「遗址、文物条目」双实体", "favorite 表 target_key 支持 site/relic", "文物页可独立收藏、独立笔记"],
    ["笔记 + 标签分类（含默认三标签）", "note/tag 字典 + 预置 3 标签 + 自建", "标签随笔记进同步域"],
    ["同步收藏、笔记、学习进度三类", "六表统一进 MergeEngine 同步域", "进度用 done=0/1 落库，可表达「改回未读」"],
    ["最新时间戳为准的冲突裁决", "LWW-Element-Set + 墓碑删除", "同一冲突可反复演示，败方版本留快照"],
    ["面板：进度/最后同步时间/冲突记录数", "SyncPage 三要素齐 + 方向动效", "双轨：单机仿真与真机分布式同一引擎"],
    ["全部预置本地、离线可编辑、恢复后自动同步", "rawfile 资产 + RDB 事务 + 网络事件自动合并", "不声明 INTERNET 权限，系统层发不出请求"],
  ];
  s.addTable(rows, {
    x: M, y: 1.72, w: W - 2 * M, colW: [3.5, 3.9, 4.7],
    fontFace: T.bodyFontFace, fontSize: 11.5, color: C.dk2, valign: "middle",
    border: { type: "solid", color: "E2DED4", pt: 0.75 },
    fill: { color: C.lt2 }, rowH: 0.46, margin: 0.08, objectName: "compliance-table",
  });
  s.addNotes("【1:30–2:45 合规对照】\n这一页是逐条对照，我不说「大概都实现了」。\n" +
    "左边是赛题原文，中间是落点，右边是可复查的证据。\n" +
    "两处我们多做了一步：一是详情页在赛题要求的五层之外加了「代表文物」第六区，" +
    "因为赛题写明要收藏「遗址、文物条目」，只做遗址单实体就漏了半句；" +
    "二是学习进度——赛题点名了但很多实现会跳过，我们把它做成显式勾选并进同步域。\n" +
    "最后一条请留意：应用没有申请 INTERNET 权限，离线不是「测试时没网」，是系统层就发不出请求。");
}

// ═══ 4 产品结构 + 年代分布 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "合规与产品" });
  s.addText("产品结构：从地表到展柜", { placeholder: "title" });
  s.addText("六个年代是导航轴，不是筛选条件的装饰", { placeholder: "kicker" });
  s.addChart(pres.ChartType.bar, [{
    name: "遗址数", labels: D.eraNames, values: D.eraSites,
  }], {
    x: M, y: 1.8, w: 6.1, h: 4.6, barDir: "col", varyColor: true,
    chartColors: D.eraColors,
    showLegend: false, showTitle: true, title: "各年代遗址数量（42 处）",
    titleFontSize: 13, titleColor: C.dk1,
    catAxisLabelColor: C.dk2, catAxisLabelFontSize: 11,
    valAxisLabelColor: C.dk3, valAxisLabelFontSize: 10,
    valGridLine: { color: "E2DED4", size: 0.5 }, catGridLine: { style: "none" },
    showValue: true, dataLabelPosition: "outEnd", dataLabelColor: C.dk1,
    dataLabelFontSize: 11, dataLabelFontFace: T.bodyFontFace,
    valAxisMaxVal: 12, chartColorsOpacity: 100,
    objectName: "era-chart",
  });
  s.addText("三条主线", {
    x: 7.1, y: 1.8, w: 5.6, h: 0.34, margin: 0, fontSize: 14, bold: true,
    color: C.dk1, objectName: "lines-head",
  });
  rowList(s, [
    ["年代剖面 · 首页", "六层纵向时间流，研读完成度直接长在这一排格子上", ERA.yangshao],
    ["文物图录 · 104 件总目", "文物脱离「挂在遗址下面」的从属位置，可按年代与材质独立检索", ERA.xiashang],
    ["主题路线 · 7 条 / 40 站", "按站排序的走访清单带完成度，数据不一致时进明确失效态而非半渲染", ERA.song],
  ], 7.1, 2.25, 5.6);
  s.addText("19 个页面分两类语法：频道页只认底部导航（清栈替换），子页只认 push + 返回——两套语法不在同屏并存。",
    { x: 7.1, y: 5.05, w: 5.6, h: 1.1, margin: 0, fontSize: 12, color: C.dk3,
      objectName: "nav-note" });
  s.addNotes("【2:45–4:00 产品结构】\n左边这张图是真数据：42 处遗址落在六个年代上，" +
    "仰韶 10、龙山 5、夏商 7、周 6、汉唐 8、宋 6。\n" +
    "首页的六层年代卡就是应用的导航轴：用户读到哪一层，完成度直接长在格子上。\n" +
    "右边三条主线：年代剖面、文物图录、主题路线。图录和路线是我们自己加的两条功能线，" +
    "因为「收藏文物条目」要有地方能整体浏览，读史的人也想知道这些点怎么串起来走。\n" +
    "补一句工程上的收敛：底部导航是全站唯一一套，频道页不挂返回键，子页不挂底栏——" +
    "这两套语法混在一屏里时，返回会直接把应用退出，我们把它拆开了。");
}

// ═══ 5 内容工程与诚实性 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "内容与数据" });
  s.addText("内容是一份数据集，不是一堆网页", { placeholder: "title" });
  s.addText(D.matrix, { placeholder: "kicker" });
  const cards = [
    ["五层级文本", "介绍 / 考古 / 历史事件 / 诗词 / 文旅，考古层按公开发掘简报口径；intro 与 arch 中位 481 / 536 字", ERA.yangshao],
    ["真句真作者", "诗词层 42 处遗址全部非空，出处逐条登记，不写「佚名古诗」糊过去", ERA.xiashang],
    ["影像不冒充", "22 处遗址有实拍头图、33 件文物有实拍；其余走「按材质分类的单色线稿」并标明待入藏", ERA.zhou],
    ["署名成工程", "76 张在包实拍逐条登记作者/来源/许可/改动，6 张自有 AI 示意图单独披露，双向差集由门禁硬卡", ERA.hantang],
  ];
  const gap = 0.28, w = (W - 2 * M - gap) / 2;
  cards.forEach((cd, i) => {
    const x = M + (i % 2) * (w + gap), y = 1.85 + Math.floor(i / 2) * 1.85;
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x, y, w, h: 1.6, fill: { color: C.lt2 }, rectRadius: 0.05,
      line: { color: C.lt3, width: 1 }, objectName: `card-${i}`,
    });
    s.addShape(pres.shapes.RECTANGLE, {
      x: x + 0.24, y: y + 0.26, w: 0.3, h: 0.3, fill: { color: cd[2] },
      line: { type: "none" }, objectName: `card-chip-${i}`,
    });
    s.addText(cd[0], {
      x: x + 0.66, y: y + 0.2, w: w - 0.9, h: 0.4, margin: 0, fontSize: 15,
      bold: true, color: C.dk1, objectName: `card-title-${i}`,
    });
    s.addText(cd[1], {
      x: x + 0.24, y: y + 0.68, w: w - 0.48, h: 0.82, margin: 0, fontSize: 12,
      color: C.dk2, objectName: `card-body-${i}`,
    });
  });
  s.addText("覆盖口径：城市 郑州 11 / 洛阳 10 / 开封 9 / 三门峡 6 / 濮阳 6　·　类型 都邑 28 / 墓葬 7 / 窑址 4 / 古建筑 3",
    { x: M, y: 5.65, w: W - 2 * M, h: 0.4, margin: 0, fontSize: 12, color: C.dk3,
      objectName: "coverage-foot" });
  s.addNotes("【4:00–5:15 内容与诚实】\n这一页想说两件事：内容是工程出来的，以及我们对影像的态度。\n" +
    "内容侧：42 份 JSON 走同一套 schema 校验 + 配额矩阵，任何一组筛选组合都不会翻出空页——" +
    "非空组合有 32 个，这个数字被单测钉住下限，防止以后回填数据把矩阵搞塌。诗词层 42 处全部非空，" +
    "真句真作者真出处，比如西水坡引的是王之涣《登鹳雀楼》。\n" +
    "影像侧是我们最较真的地方：考古与文物影像必须实拍，缺图就走单色线稿并标明「待入藏」，" +
    "不用生成图冒充实物照片。现在 76 张实拍每张都能回答「谁拍的、哪来的、什么许可、我改了什么」，" +
    "而且这件事有门禁脚本双向对账——不是写在文档里的承诺，是出包前会拦的闸。\n" +
    "6 张自有示意图（首页年代卡封面）也单独披露了。");
}

// ═══ 6 技术核心：可裁决的同步 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "技术核心" });
  s.addText("技术核心：冲突可裁决、可回看", { placeholder: "title" });
  s.addText("合并算法是纯函数，传输层可替换——所以「仿真」和「真机」不是两套逻辑",
    { placeholder: "kicker" });
  const boxes = [
    ["设备 A 档案", "收藏 / 笔记 / 进度 / 标签\n六表带 updateTime + deviceId", ERA.xiashang, M],
    ["设备 B 档案", "同一结构，各自独立落库\n（单机双档案可反复演示同一冲突）", ERA.song, 3.72],
    ["传输层（可换）", "LoopbackAdapter 单机仿真\nSoftBusRdbTransport 真机分布式\n先拉对端快照，再推合并终态", ERA.zhou, 6.84],
    ["MergeEngine 纯函数", "输入双方全量带版本记录\n输出终态 + 冲突报告", ERA.yangshao, 9.96],
  ];
  boxes.forEach((b, i) => {
    s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
      x: b[3], y: 1.9, w: 2.76, h: 1.85, fill: { color: C.lt2 }, rectRadius: 0.06,
      line: { color: b[2], width: 1.5 }, objectName: `flow-box-${i}`,
    });
    s.addText(b[0], {
      x: b[3] + 0.16, y: 2.02, w: 2.44, h: 0.36, margin: 0, fontSize: 13, bold: true,
      color: b[2], objectName: `flow-title-${i}`,
    });
    s.addText(b[1], {
      x: b[3] + 0.16, y: 2.42, w: 2.44, h: 1.2, margin: 0, fontSize: 11,
      color: C.dk2, objectName: `flow-body-${i}`,
    });
    if (i < 3) {
      s.addText("→", {
        x: b[3] + 2.76, y: 2.5, w: 0.2, h: 0.5, margin: 0, align: "center",
        fontSize: 16, bold: true, color: C.dk3, objectName: `flow-arrow-${i}`,
      });
    }
  });
  s.addText("裁决规则（确定性，不靠运气）", {
    x: M, y: 4.05, w: 6.1, h: 0.34, margin: 0, fontSize: 14, bold: true,
    color: C.dk1, objectName: "rule-head",
  });
  s.addText([
    { text: "双方都有 → 取 updateTime 大者为终态", options: { bullet: true, breakLine: true } },
    { text: "时间戳相同 → 按 deviceId 字典序决胜，这次 A 赢下次还是 A 赢", options: { bullet: true, breakLine: true } },
    { text: "删除是墓碑更新（isDeleted=1 + 刷新时间），不是删行——否则对端只能当成「从未存在」", options: { bullet: true, breakLine: true } },
    { text: "败方版本留快照进冲突历史，可展开回看「两个版本 + 采信依据」", options: { bullet: true } },
  ], { x: M, y: 4.45, w: 6.1, h: 2.0, margin: 0, fontSize: 13, color: C.dk2,
    paraSpaceAfter: 7, objectName: "rule-list" });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x: 7.1, y: 4.1, w: 5.6, h: 2.35, fill: { color: "F7F3EA" }, rectRadius: 0.06,
    line: { color: ERA.hantang, width: 1 }, objectName: "proof-card",
  });
  s.addText("现场演示读数", {
    x: 7.34, y: 4.22, w: 5.1, h: 0.36, margin: 0, fontSize: 14, bold: true,
    color: ERA.hantang, objectName: "proof-head",
  });
  s.addText([
    { text: "A/B 各改同一条笔记 → 同步 → 面板出现「采信 deviceB 10:46:14 / 落选 deviceA 10:45:30」", options: { bullet: true, breakLine: true } },
    { text: "面板三要素齐：同步进度、最后同步时间、冲突记录数（含方向动效）", options: { bullet: true, breakLine: true } },
    { text: "真机侧：六张同步表注册进分布式 RDB，经软总线组网，先 remoteQuery 拉取再 PUSH 合并终态", options: { bullet: true, breakLine: true } },
    { text: "掉线恢复后自动触发一次合并（30 秒冷却去抖，失败只记日志不打断用户）", options: { bullet: true } },
  ], { x: 7.34, y: 4.62, w: 5.1, h: 1.75, margin: 0, fontSize: 11.5, color: C.dk2,
    paraSpaceAfter: 5, objectName: "proof-list" });
  s.addNotes("【5:15–7:15 技术高点，全场最重要的一页】\n这是本项目的核心，我讲慢一点。\n" +
    "架构上关键的一步：合并算法是纯函数，输入两边全量带版本记录，输出终态加冲突报告；" +
    "传输层是可替换的适配器。左边两档身份各自一个独立数据库文件，A 上编辑的笔记 B 看不到，" +
    "点「组网同步」才走合并——所以演示不需要两台真机也能完整跑通冲突过程。" +
    "真机上跑的是同一个 MergeEngine，只是把传输层换成分布式 RDB 经软总线组网。裁决逻辑只有一份。\n" +
    "规则四条，请重点看第二和第四条：时间戳相同就按设备号字典序决胜，这是确定性的，" +
    "不会出现这次 A 赢下次 B 赢；删除走墓碑更新而不是删行，否则同步时无法表达" +
    "「我刚刚把它删了」；败方版本留快照，评委可以点开看到两个版本和采信依据。\n" +
    "（若现场两台真机组不上：不慌，切单机仿真，说「两台设备今天没组上网络，" +
    "但合并裁决算法是同一份，我用双档案仿真把冲突过程完整跑一遍」，评委看到的是裁决本身。" +
    "千万不要在台上点不出冲突。）");
}

// ═══ 7 可解释推荐与知识网络 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "技术核心" });
  s.addText("推荐可解释，网络不新增负担", { placeholder: "title" });
  s.addText("赛题要「相似度推荐」，我们把它做成能被用户反驳的样子", { placeholder: "kicker" });
  s.addChart(pres.ChartType.bar, [{
    name: "评分权重", labels: ["同年代", "同类型", "同城市", "共享标签"],
    values: [0.4, 0.3, 0.2, 0.1],
  }], {
    x: M, y: 1.85, w: 6.0, h: 3.6, barDir: "bar",
    chartColors: [C.accent1], showLegend: false,
    showTitle: true, title: "本地规则评分（每条最多显示两条理由）",
    titleFontSize: 13, titleColor: C.dk1,
    catAxisLabelColor: C.dk2, catAxisLabelFontSize: 12,
    valAxisLabelColor: C.dk3, valAxisLabelFontSize: 10,
    valGridLine: { color: "E2DED4", size: 0.5 }, catGridLine: { style: "none" },
    showValue: true, dataLabelPosition: "outEnd", dataLabelColor: C.dk1,
    dataLabelFontSize: 11, dataLabelFontFace: T.bodyFontFace,
    valAxisMaxVal: 0.5, valAxisMinVal: 0,
    objectName: "reco-chart",
  });
  s.addText("同年代 0.4 · 同类型 0.3 · 同城市 0.2 · 共享标签 Jaccard 0.1\n另加近期行为加权（≤0.15，浏览优先于收藏），排除已收藏条目。",
    { x: M, y: 5.6, w: 6.0, h: 0.8, margin: 0, fontSize: 12, color: C.dk3,
      objectName: "reco-note" });
  rowList(s, [
    ["理由写在卡上", "每条最多两条理由，点开看全部——看到「同城」发现自己其实想换一座城，可以点「不感兴趣」", ERA.xiashang],
    ["冷启动不硬凑", "没有行为时先给兴趣选择器，而不是塞一串陌生条目", ERA.zhou],
    ["负反馈只留本机", "「我今天不想看这条」是临时态度，不该跟着笔记同步到另一台设备", ERA.hantang],
    ["知识网络零新增同步域", "Canvas 力导向图直接复用收藏与标签表；节点可点进详情，返回时随收藏变化重算", ERA.song],
  ], 7.0, 1.95, 5.7);
  s.addNotes("【7:15–8:15 推荐与拓展】\n推荐是纯本地的，规则写在屏幕上：同年代 0.4、同类型 0.3、" +
    "同城市 0.2、共享标签 Jaccard 0.1，再加近期行为加权、上限 0.15，浏览优先于收藏。\n" +
    "为什么强调「可解释」：理由不是装饰，是让用户能反驳。看到「同城」才意识到自己其实想换一座城，" +
    "于是点不感兴趣——而这条负反馈只存本机，它是临时态度，不该随笔记同步到另一台设备。\n" +
    "知识网络是拓展项，我只用一句说明它的工程价值：图完全复用收藏和标签两张表，没有新增同步域。" +
    "30 秒带过即可，不占主场时间。");
}

// ═══ 8 质量与实测 ═══
{
  const s = pres.addSlide({ masterName: "CONTENT", sectionTitle: "质量与收尾" });
  s.addText("质量不是形容词，是可复跑的读数", { placeholder: "title" });
  s.addText("出包前先过十三道闸；闸只管「写法合法」，屏上反应另有实测脚本兜底",
    { placeholder: "kicker" });
  statCards(s, [
    [String(D.gates), "构建前门禁（非 0 即阻断出包）", ERA.xiashang],
    [String(D.unitTests), "Node 纯函数单测全绿", ERA.zhou],
    [String(D.pages), "页面逐屏走查", ERA.yangshao],
    [D.hapMB, "MB，签名包（限 40）", ERA.song],
  ], 1.9);
  s.addText([
    { text: "门禁管的事：语料 schema 与图片引用双向差集、署名完整性、诗词完备性、对比度 58 项、字号适老化、读屏标签、动效时长、设计令牌裸值、跨页间距一致性、字重×字族配对", options: { breakLine: true } },
    { text: "实测脚本兜底的事：按压反馈逐像素比对（几何型 chip 变化 20.8%、透明度型 15.2%）、双档案冲突端到端七步读数、19 屏逐屏走查", options: {} },
  ], {
    x: M, y: 3.85, w: W - 2 * M, h: 1.5, margin: 0, fontSize: 12.5, color: C.dk2,
    paraSpaceAfter: 8, objectName: "quality-list",
  });
  s.addShape(pres.shapes.ROUNDED_RECTANGLE, {
    x: M, y: 5.35, w: W - 2 * M, h: 1.2, fill: { color: "FBF3EC" }, rectRadius: 0.06,
    line: { color: C.accent1, width: 1 }, objectName: "honest-card",
  });
  s.addText("我们没做的 / 还没闭合的（如实列）", {
    x: M + 0.24, y: 5.45, w: 12.4, h: 0.34, margin: 0, fontSize: 13, bold: true,
    color: C.accent1, objectName: "honest-head",
  });
  s.addText("账号体系、云服务、地图导航、AR/3D、社区分享、音频讲解——超出赛题要求，为工期让路；" +
    "冷启动耗时读数（T4）仍未取到，只埋了 BOOT 锚点、没填数，因此不写「已优化启动」；" +
    "演示视频与路演 PPT 仍在交付清单里标为待补。", {
    x: M + 0.24, y: 5.82, w: 12.4, h: 0.66, margin: 0, fontSize: 11.5, color: C.dk2,
    objectName: "honest-body",
  });
  s.addNotes("【8:15–9:15 质量】\n这一页是给评委看「这些结论凭什么」的。\n" +
    "十三道门禁全部在出包前执行，任一非 0 退出码就阻断打包——我们做过证伪：" +
    "往包里塞一张没有署名记录的图，门禁确实 exit 1，日志里一条 hvigor 输出都没有，" +
    "所以「阻断」这两个字是真的。\n" +
    "但门禁只能证明写法合法，证明不了屏上真的有反应，所以交互类另有实测脚本：" +
    "按压反馈是逐像素比对的，同步冲突是七步端到端带读数的。\n" +
    "最后这栏是我们有意留下的：没做的事、没闭合的读数，我直接写在稿子上——" +
    "冷启动耗时我们只埋了锚点、没拿到读数，那就不能说「已优化启动」。");
}

// ═══ 9 收尾 ═══
{
  const s = pres.addSlide({ masterName: "DIVIDER", sectionTitle: "质量与收尾" });
  strata(s, 0, 0, 0.65, H);
  s.addText("一句话总结", {
    x: 1.25, y: 1.35, w: 11.4, h: 0.5, margin: 0, fontSize: 15, color: ERA.song,
    objectName: "close-kicker",
  });
  s.addText("42 处遗址、104 件文物、三维筛选、五层级详情；\n双实体收藏与笔记、可裁决的分布式合并、可解释的本地推荐。", {
    x: 1.25, y: 1.95, w: 11.4, h: 1.9, margin: 0, fontSize: 26, bold: true,
    color: ON_DARK, fontFace: T.headFontFace, paraSpaceAfter: 8,
    objectName: "close-title",
  });
  s.addText("全部离线可用，真机之间自动同步。", {
    x: 1.25, y: 3.9, w: 11.4, h: 0.5, margin: 0, fontSize: 18, color: ERA.hantang,
    objectName: "close-line",
  });
  s.addText([
    { text: "演示路线：P1 首页全景 → P2 三维筛选出结果 → P3 详情五层（停诗词页）→ 收藏与笔记 → P8 双身份改同一条笔记 → 同步 → 冲突展开 → P9 网络图", options: { breakLine: true } },
    { text: "兜底：组网失败即切单机仿真；模拟器卡顿则出示 design/verify 实机截图", options: {} },
  ], {
    x: 1.25, y: 4.9, w: 11.4, h: 1.2, margin: 0, fontSize: 12.5, color: ON_DARK,
    transparency: 8, paraSpaceAfter: 6, objectName: "close-demo",
  });
  s.addText("谢谢各位老师", {
    x: 1.25, y: 6.3, w: 11.4, h: 0.5, margin: 0, fontSize: 16, bold: true,
    color: ERA.hantang, objectName: "close-thanks",
  });
  s.addNotes("【9:15–10:00 收尾】\n总结一句：42 处遗址、104 件文物、三维筛选、五层级详情，" +
    "双实体收藏与笔记，可裁决的分布式合并，可解释的本地推荐——全部离线可用，真机之间自动同步。\n" +
    "然后是演示。屏幕下方这条路线就是录屏/现场走查的顺序，请评委对着这一页看。\n" +
    "（心里记住两条兜底：组网失败切单机仿真，模拟器卡顿出示实机截图；附录 B 有话术。）\n" +
    "谢谢各位老师，请批评指正。");
}

(async () => {
  await pres.writeFile({ fileName: OUT });
  const { applyTheme } = require(APPLY_THEME);
  await applyTheme(OUT, T);
  // pptxgenjs 只把字体名写进 latin 槽；东亚槽留空时，母版的 +mn-ea/+mj-ea
  // 会解析成「未指定」，中文就交给对方机器的 Office 默认字体（常见是宋体），
  // 行宽一变，我这边量好的版式就不可复现。这里把主题两个 ea/cs 槽补实。
  // 这一步必须排在 applyTheme 之后：applyTheme 会重写 theme，先补槽会被写回空值。
  // 同时让它复验 accent1 是否真写进 theme —— applyTheme 失败时它会 throw 且不写文件，
  // 但 writeFile 已经把未上色的 pptx 留在盘上，漏看退出码就会交付 Office 默认配色稿。
  const { spawnSync } = require("child_process");
  const r = spawnSync(process.env.PYTHON || "python",
    ["-I", path.join(__dirname, "pptx_ea_font.py"), OUT, T.bodyFontFace, T.colors.accent1],
    { encoding: "utf8" });
  if (r.status !== 0) throw new Error("字体槽/主题复验失败: " + (r.stderr || r.stdout));
  console.log(`saved ${OUT} — ${(r.stdout || "").trim()}`);
})().catch((e) => { console.error("BUILD FAILED:", e.stack || e.message); process.exit(1); });
