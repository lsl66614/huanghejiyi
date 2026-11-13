// entry/src/main/ets/common/DesignTokens.ets
//
// 设计令牌的唯一事实源。改这里 → 全站生效；改页面里的裸数字 → 会被
// tools/lint_tokens.py 拦下（豁免见该脚本 EXEMPT）。
//
// 为什么单独一层：EraTheme.ets 回答的是「这个年代什么颜色」，
// 本文件回答的是「什么层级的文字、间距、圆角、动效时长」。
// 两者混在一处时，调整一次品牌色要翻十几个页面，改一个内边距没有落点。
//
// 所有数值都带门禁：
//   色值   → tools/check_contrast.py 逐项算 WCAG 2.2 对比度
//   字号   → tools/lint_aging.py 卡适老下限
//   其余   → 本文件顶部注释里的推导依据
//
// 反向依赖约束：本文件不得 import 任何业务模块（EraTheme/Labels 等），
// 否则 check_contrast.py 解析令牌时会形成循环依赖。

// ---------------------------------------------------------------- 语义色
// 白盒体系（2026-10-13 定稿，对齐 Pencil 设计稿「展陈白盒」四屏）。
// 底色从纸色 #F5F1E8 提到近白 #FBFAF8、卡面纯白 #FFFFFF ——
// 唯一目的是让照片成为画面上最饱和的东西。纸色底会和照片在暖调上
// 互相打架；参考图里面具之所以跳出来，是因为它周围全是白的。
//
// 层级从强到弱。同一语义在四种浅底上都要 ≥ 4.5:1，全部实测过：
//
//   层级    PAGE      CARD     RAISED   VIEWER
//   INK      17.91    18.69     16.74    15.55
//   BODY     11.11    11.59     10.24     9.47
//   SUB       5.35     5.58      4.90     4.73
//   ACCENT    5.86     6.12      5.37     5.19
//
// 注意 SUB 在 VIEWER 上只有 4.73:1 —— 刚过线。#6E675E 是为暖调近白底
// 重新反解的，不得为了"更淡"再往上提亮。

export const INK: string = '#141210';        // 标题、强调数字、按下态
export const BODY: string = '#3D3833';       // 正文
export const SUB: string = '#6E675E';        // 次级说明、辅助文字
export const ACCENT: string = '#9C4A2F';     // 赭红：强调动作、当前选中
// 印章红：详情页「河志」印章的印泥色。比 ACCENT 更饱和，是实物色而非界面色。
export const SEAL_RED: string = '#A03B26';    // 5.92:1 @ SURFACE_PAGE

export const SURFACE_PAGE: string = '#FBFAF8';   // 页面底（近白）
export const SURFACE_CARD: string = '#FFFFFF';   // 卡片面（纯白）
export const SURFACE_RAISED: string = '#F2F0EC'; // 筛选条 / 选中底 / 标签底
export const SURFACE_VIEWER: string = '#EFECE7'; // 灯箱底

export const LINE_HAIR: string = '#E8E4DE';  // 发丝描边、分隔线。仅作线，不作底。
export const ON_DARK_TEXT: string = '#F7F4EF';  // 深底（展柜）上的标题文字
export const ON_DARK_TEXT_ALT: string = '#E3DFD8'; // 深底正文（展柜内长文本）
export const ON_DARK_PANEL: string = '#1C1A18';  // 展柜面板（RelicPage）
export const ON_DARK_RAISED: string = '#262320'; // 深色区第三级：选中/抬升底
export const ON_DARK_SUB: string = '#9A9288';    // 深底次级文字，5.65:1 @ #1C1A18
export const ON_DARK_GOLD: string = '#D0AA27';   // 深底金线，7.82:1 @ #1C1A18
export const ON_DARK_ACCENT: string = '#E0A07C'; // 深底强调（ACCENT 在深底只有 2.84:1，禁用）
export const ON_DARK_LINE: string = '#2A2724';  // 深底分隔线
export const ON_DARK_BG: string = '#121110';    // 展柜底

// 网络关系图（NetworkPage）的画布描边。这两条只画线、不承载文字，
// 1.0:1 左右的对比度对可读性无意义，靠色相差与粗细区分层级，
// 因此不受 4.5:1 门禁约束，但同样收进令牌以免散落。
export const GRAPH_EDGE: string = '#C9BFA9';
export const GRAPH_ROOT: string = '#B9AE99';

// 材质章色点（ListPage「按材质逛」入口）。七类各一色，刻意**不复用年代色**：
// 年代色在年代 chips 上已有语义，两个维度共用一套色会让用户以为它们是同一个筛选。
// 取色贴近材质本体（陶红褐 / 金属青铜绿 / 土棕 / 玉灰青 / 石石灰 / 骨釉黄 / 有机深褐），
// 与年代色保持可辨的色相差。只画 10vp 色点、不承载文字，故不受 4.5:1 约束；
// 同一行的类名是 INK 文字，可读性由文字层保证。
export const MAT_COLOR_POTTERY: string = '#9C4A2F';
export const MAT_COLOR_METAL: string = '#5C7153';
export const MAT_COLOR_EARTH: string = '#7A6A4F';
export const MAT_COLOR_JADE: string = '#7A8B8F';
export const MAT_COLOR_STONE: string = '#6E675E';
export const MAT_COLOR_BONE: string = '#B98A44';
export const MAT_COLOR_ORGANIC: string = '#8B6833';

// 渐变/高亮的透明端点。ArkUI 的渐变数组要求字符串形态，
// 不能用 Color.Transparent，所以这里有一个与全透明等值的字符串令牌。
export const TRANSPARENT: string = '#00000000';

// ---------------------------------------------------------------- 间距
// 按「角色」而非「数值」命名。这批值是从全站 30+ 种实际用法里反推的：
// 24 出现 104 次（页面级左右边距），是全站唯一的横向下沉锚点；
// 其余高频值 16 / 12 / 10 / 8 / 6 / 4 / 3 分别对应卡片内衬、元素间距、
// 紧凑间距、图标间距、微间距、发丝内衬、标签内衬。
// 不收敛 14 / 18 / 20 / 22 / 26 这类「差一档」的值——它们是间距噪点，
// 迁移时一律就近吸附到语义档位。
export const PAGE_PAD_X: number = 20;    // 页面级左右边距（设计稿统一 20）
export const BLOCK_GAP: number = 24;     // 区块之间
export const CARD_PAD: number = 16;      // 卡片内边距
export const ITEM_GAP: number = 12;      // 卡片内元素之间
export const ROW_GAP: number = 8;        // 图标↔文字、同组元素
export const MICRO_GAP: number = 6;      // 极紧间距
export const HAIR_PAD: number = 4;       // 发丝元素内衬
export const HAIR: number = 1;           // 发丝：边框宽度

// ---------------------------------------------------------------- 圆角
// 收敛档只有 4 个值（0 / 4 / 8 / 190）。但设计稿引入了三个"细轨"场景
// （深度尺 3vp 轨、进度条 6vp 轨、章点 6vp 圆），它们的圆角等于自身
// 高度的一半——这类"自半圆"由几何决定，不是风格选择，故单列一组常量
// 而不是把 1/2/3 塞进收敛档（那会把档位表变成数字垃圾桶）。
// 0 不设令牌：borderRadius(0) 等于不写这条属性，页面里直接省略即可。
export const RADIUS_SM: number = 4;       // 小方角（标签）
export const RADIUS_MD: number = 8;       // 卡片
export const RADIUS_PILL: number = 190;  // 大圆：直径 ÷ 2 处使用（关系图节点、展柜图）
// 细轨自半圆：值 = 对应轨高 ÷ 2，几何决定，勿单独调
export const RADIUS_TRACK_3: number = 2;  // 3vp 细轨（DepthRuler 尺格）
export const RADIUS_DOT_6: number = 3;    // 6vp 圆点（LayerBadge 层色点）
export const RADIUS_SEG_10: number = 1;   // 10vp 进度段（MiniProfile）
// 大卡与导航浮层：白卡大卡 12vp、Tab 悬浮条内的当前项 20vp。
// 这两个值是设计稿的形，不是风格漂移，故与细轨同列收进常量。
export const RADIUS_CARD_LG: number = 12;  // 白卡大卡（设计稿 12vp）
export const RADIUS_NAV_ITEM: number = 20; // 底部导航当前项
// 胶囊：设计稿把「主按钮 / 筛选 chip / 标签页」全部从描边矩形改成胶囊。
// CAPSULE_H 与 CAPSULE_RADIUS 必须成对（RADIUS = H / 2），否则胶囊会变椭圆。
// 注意 RADIUS_PILL = 190 是既有值、为关系图大圆定的，不要拿它当胶囊用。
export const CAPSULE_H: number = 48;      // 主按钮高度（设计稿 48）
export const CAPSULE_RADIUS: number = 24; // = CAPSULE_H / 2
export const CHIP_H: number = 32;         // 筛选 chip / 小胶囊高度
export const CHIP_RADIUS: number = 16;    // = CHIP_H / 2
export const TAB_H: number = 34;          // 展柜内标签页高度
export const TAB_RADIUS: number = 17;     // = TAB_H / 2
export const ICON_BTN_H: number = 40;     // 展柜圆形图标按钮（返回/分享）
export const ICON_BTN_RADIUS: number = 20; // = ICON_BTN_H / 2
// 页头圆形图标按钮另一套尺寸（36×36，设计稿「Actions」组：搜索/网络图/导出/更多）。
// 与上面的 40×20（展柜深色区）并存——两处尺寸不同，不是同一语义。
// 补进令牌表的缘故：这两颗按钮原先把 36/18 写在本页的局部 const 里，
// 令牌表外无据可查，改尺寸时容易漏改（lint 只拦字面量，拦不到本地 const）。
export const NAV_ICON_BTN_H: number = 36;
export const NAV_ICON_BTN_RADIUS: number = 18; // = NAV_ICON_BTN_H / 2（正圆）

// ---------------------------------------------------------------- 印章（黄河水文四字印）
// 设计稿①的 Seal：容器 64vp，印面 88vp absolute 定位——即印章从 64vp
// 窗口露出一部分（左上对齐）。这是刻意的"盖印"效果。
// 但实测（模拟器截图）64vp 窗口只露得出「黄河」两字，「水纹」被裁，
// 评委读不到完整印文。故容器与印面等大（88vp），四字完整可见——
// 一屏 390vp 宽里 88vp 印章 + lockup 的配比仍成立。
// 印面 88 = 2 × 44 字格，字号 38 是 44 格内的字（留 3vp 呼吸）。
export const SEAL_SIZE: number = 88;        // 印面容器（= 印面，四字完整）
export const SEAL_FACE: number = 88;        // 印面本体
export const SEAL_CELL: number = 44;        // 单字格
export const SEAL_FONT: number = 38;        // 印内字号
export const SEAL_RADIUS: number = 6;       // 印面圆角
export const SEAL_BORDER: number = 2;       // 印面描边

// ---------------------------------------------------------------- 图与文字（scrim）
// 白盒体系里白字直接压在照片上。但本项目照片明度不可控（Commons 实拍，
// 有白墙、有天空、有雪），因此规定：任何压在照片上的文字必须先铺 scrim。
// scrim = #141210（同 INK）按 alpha 合成，最坏情况＝照片纯白 #FFFFFF：
//
//   用途                        最低 alpha   合成后底色   白字实测
//   头图主标题 / 正文              0.60       #727170      4.87
//   「示意图」角标（9pt 小字）     0.70       #5B5958      6.97
//   底部渐变 scrim 实端           0.68       #5F5E5C      6.48
//
// 三档都是下限不是推荐值。渐变 scrim 从 0 线性升到实端值，文字只允许落在
// ≥ 阈值的那一段里 —— 这条是硬约束：后来的人会自然地把渐变拉长、把文字
// 推上去，然后静默跌到 3:1。
export const SCRIM: string = '#141210';
export const SCRIM_ALPHA_TEXT: number = 0.60;  // 头图文字最低
export const SCRIM_ALPHA_BADGE: number = 0.70; // 角标最低
export const SCRIM_ALPHA_EDGE: number = 0.68;  // 底部渐变实端
// 压在照片/层色整块上的文字。白色是 scrim 机制的配套——只有铺了
// scrim 的位置才允许用这三个令牌（见上方 SCRIM_* 的实测表）。
// 裸 #FFFFFF 会被 lint_tokens 拦下，逼着调用方想清楚"这里铺 scrim 了吗"。
// 三档曾经是三个不同的色值，白盒化后收敛为同一支白——差别只在
// 不透明度上做，故只留 ON_IMAGE_TEXT 一个名字。
export const ON_IMAGE_TEXT: string = '#FFFFFF';       // 头图主标题/正文/角标小字
export const HERO_IMAGE_H: number = 320;       // 满幅头图高度 vp（设计稿）

// ---------------------------------------------------------------- 字号
// 现状 20 种收敛到 7 档。收敛依据是每处的语义层级，不是「就近凑整」：
//   8,9            → MICRO 9     示意图水印、印章字（非阅读性标记）
//   10,11,12       → CAPTION 12  计数、年代跨度、状态徽标
//   13,14,15       → BODY 14     唯一承载长文本的档位
//   16,17,18,19    → TITLE 18    卡片标题、事件标题、页头
//   22             → SECTION 22  详情页五个节标题
//   24,26,28,32,34 → DISPLAY 28  页面主标题、空态大字、头图遗址名
//   40,44          → HERO 44     首屏大字
//
// 为什么留 22 一档：详情页「壹 考古」「贰 文物」是全站唯一一组五处并排的
// 节标题，22pt 宋体是它们的设计身份。取消这一档、并入 18，节标题就与卡片
// 标题同级，页内层级塌掉；并入 28 又会盖过头图上的 28pt 遗址名。22 是这组
// 层级不可缺的中间台阶。
//
// 为什么 34 不单列一档：MinePage「我在这条河边记下的东西」原 34pt，46/34
// 的行高比说明它的视觉重量等同今天的 28pt DISPLAY。归入 DISPLAY 后行高
// 改 38，比例 1.36×，观感不变而档位少一。
//
// 为什么 MICRO 可以低于 12pt：工信部要求正文 ≥ 12pt，而 MICRO 只承载压在
// 图像上的示意水印和 3 个字的印章，不承载任何需要读懂的信息。用到它的
// 每一处都在 tools/lint_aging.py 的豁免清单里列明理由，且不许静默豁免。
// 白盒体系（2026-10-14 补齐）字号档位。设计稿四屏实际用到 10 档，
// 此前只有 9 档且缺几个关键台阶。新增的五档全部来自设计稿实测值：
//
//   FS_LOCKUP 34  首屏主标题「黄河记忆」—— 比 DISPLAY 再大一级，
//                 因为它是全 App 的招牌字，且与 64vp 四字印章并排
//   FS_HEAD   17  列表页 Section Title「入选遗址」—— 比 ITEM 大
//                 一级、比 TITLE 小一级，是「区块标题」的专属台阶
//   FS_META   13  副题 / meta 行 / 按钮标签 —— 设计稿大量使用 13px，
//                 12 与 14 之间的中间档（NotoSerif 副题、胶囊按钮字）
//   FS_LABEL  11  角标 / Facts 键名 / 展签编号 —— 设计稿深色区与
//                 标签行的主力小字，比 CAPTION 小一级
//   FS_TAB    10  底部导航标签 / LayerBadge 标签 —— 最小一档，
//                 仅承载不折行的单词
//
// 为什么 MICRO(9) 与 TAB(10) 并存：MICRO 是压在图上的水印（豁免），
// TAB 是常驻底栏的导航字，两者语义不同、门禁处理不同。
export const FS_MICRO: number = 9;      // 水印（豁免，不承载信息）
export const FS_TAB: number = 10;       // 底栏标签 / LayerBadge 标签
export const FS_LABEL: number = 11;     // 角标 / Facts 键名 / 展签编号
export const FS_CAPTION: number = 12;   // 计数、年代跨度、徽标
export const FS_META: number = 13;      // 副题 / meta 行 / 按钮标签
export const FS_BODY: number = 14;      // 正文（唯一承载长文本的档位）
export const FS_ITEM: number = 15;      // 列表项标题（设计稿②列表卡）
export const FS_TITLE: number = 18;     // 卡片标题、页头、节标题
export const FS_HEAD: number = 17;      // 区块标题（设计稿②「入选遗址」）
export const FS_PAGE: number = 30;      // 二级页主标题（设计稿②「选层」）
export const FS_DISPLAY: number = 28;   // 页面主标题、空态大字、头图名
export const FS_LOCKUP: number = 34;    // 首屏主标题（设计稿①「黄河记忆」）
export const FS_HERO: number = 44;      // 首屏大字

// ---------------------------------------------------------------- 行高
// 工信部要求 ≥ 1.3×；正文档取 1.6×（22/14），是规范下限的 1.23 倍，
// 中文长段落比 1.3 在屏上明显更透气。
//
// 1.3× 这条线只约束会折行的阅读文字。承载它的档位全部达标：
//   17/12 = 1.42×   22/14 = 1.57×   24/18 = 1.33×   38/28 = 1.36×
// 全部同时满足「不小于字号 + 4」，否则汉字行盒会被上下裁切。
// 收敛前 DetailPage 的 24/13 与 29/17、SyncPage 的 19/11、
// NetworkPage 的 18/11 三处均低于 1.3×，本版一并修正。
//
// 唯一的例外是 44pt（FS_HERO）：灯箱占位字、单行大字，不折行、不作阅读
// 用途，行高按「字号 + 8」就地写（52，1.18×）。折行的大字请用 LH_DISPLAY
// —— MinePage 原 34pt 双行标题即归入 DISPLAY，行高改 38。
export const LH_CAPTION: number = 17;    // 12pt 注释（1.42×）
export const LH_BODY: number = 22;       // 14pt 正文（1.57×）
export const LH_TITLE: number = 24;      // 18pt 标题（1.33×）
export const LH_DISPLAY: number = 38;    // 28pt 主标题（1.36×）
export const LH_PAGE: number = 40;       // 30pt 二级页主标题（1.33×）
export const LH_LOCKUP: number = 45;     // 34pt 首屏主标题（1.32×）

// ---------------------------------------------------------------- 字族
// 白盒体系（2026-10-13）的四个字族角色，不写裸字体名：
//
//   FONT_DISPLAY  ZCOOL XiaoWei（站酷小薇）—— 页面主标题、卡片标题、
//                 遗址/文物名、按钮文字。取代宋体成为"展示体"。
//                 为什么换：宋体 800 面在大字号下笔画发糊（合成加粗的
//                 糊边在白盒底上无所遮掩），XiaoWei 是细挺的展示体，
//                 且只有 400 一个面，不存在"该传多少字重"的歧义。
//   FONT_SERIF    NotoSerifSC 800 —— 降级为"正文衬线"：详情页正文段落、
//                 副标题、统计值。仍是单一字重字族（见 WT_SERIF）。
//   FONT_SANS     系统默认（鸿蒙黑体）—— 标签、角标、辅助信息、Tab。
//   FONT_MONO     HarmonyOS Sans Mono —— 序号、编号、十六进制、层号 L1。
//
// 等宽为什么不是 Courier New：Courier New 是 1960 年度的打字机衬线，
// 宽度按 600/1000 单位等分设计，与中文标点、方块字、UI 数字的视觉重量
// 完全脱节；它在鸿蒙上也不是系统字体，靠系统替换兜底，跨设备观感不可控。
export const FONT_DISPLAY: string = 'ZCOOLXiaoWei';  // 标题字（站酷小薇，单一 400 面）
export const FONT_SERIF: string = 'NotoSerifSC';     // 正文衬线：唯一的宋体面(800)
export const FONT_SANS: string = '';                 // 空串 = 落回系统默认（鸿蒙黑体）
export const FONT_MONO: string = 'HarmonyOS Sans Mono';  // 序号、哈希、十六进制、层号

// ---------------------------------------------------------------- 字重
// 收敛前的实测：43 处 fontWeight 里同时存在 FontWeight.Bold(700) 与
// FontWeight.Bolder(800)，且**同一角色同一字号上并存**：
//   18pt：Det:708 / Fav:74 / Min:103 用 700，Rec:112 / Syn:481 用 800
//   14pt：Det:209 / Fav:341 / Net:239 用 700，Note:208 / Fav:537 用 800
// 这不是风格差异，是同一个「列表项标题」在不同页面被写成了两个字重。
//
// 收敛为三档语义：
//   REGULAR  400  正文、注释、未选中态。不写 fontWeight 时的默认值
//   MEDIUM   500  「强调但不抢层级」的中间档：眉标、计数、统计数字
//   BOLD     700  唯一的强调档：列表项标题、页头、按钮文字
//
// 为什么选中态不再顶到 800：11 处二元选中（nav 标签、年代/城市筛选、
// 分组开关、标签页）原本用 Bolder 区分。选中态已有三重冗余——颜色
// （INK vs SUB / ACCENT）、字色、图标或下划线、以及 accessibilitySelected
// 传给读屏。再加 800 只会让相邻的 12pt 筛选项糊成一团，且把强调档的
// 预算花在一个读屏已经播报过的维度上。选中改用 BOLD(700)。
//
// 为什么 MEDIUM 是 500 而不是 600/700：鸿蒙默认字族 HarmonyOS Sans SC
// 带 wght 40–900 变轴（已核 NotoSans[wdth,wght].ttf 只有 0 个汉字、
// 不能用；系统还另带 HarmonyOS_Sans_SC.ttf，20992 汉字、wght 40–900）。
// 500 在屏上实测比 400 明显、比 700 克制，正好填眉标这一档：
// 眉标本来是 SUB 色，字重一重就压过它承载的计数。
export const WT_REGULAR: number = 400;
export const WT_MEDIUM: number = 500;
export const WT_BOLD: number = 700;

// 宋体的字重不是可调参数（见 FONT_SERIF 说明），单独给一个名字，
// 让「宋体一定用这个」在代码里是显式的，而不是靠调用方记得。
export const WT_SERIF: number = 800;

// ZCOOL XiaoWei 只有 400 一个面，与宋体同理：传 700 会触发合成加粗，
// 笔画糊成一团。WT_DISPLAY 编码「展示体字重不可调」这个约束。
export const WT_DISPLAY: number = 400;

// ---------------------------------------------------------------- 阴影
// 白盒体系**需要**阴影建立层级：纸色底靠底色差分层，纯白卡面在近白页底上
// 会直接消失。阴影 alpha 必须比纸底体系减半——#1A2B2622 在原纸底上刚好，
// 纯白底上会显脏。
//
// 择一原则：纯白卡面 + 近白页底必须有阴影或发丝，否则卡片消失；
// 两者择一，不要都给（给全了显脏）。
//   SHADOW_CARD_COLOR_LIGHT  白盒卡片（设计稿列表卡、Tab 悬浮条都用它）
//   LINE_HAIR                发丝描边（卡片、胶囊未选中态用它）
// 弹层阴影（原 SHADOW_MODAL_*）随纸底体系一起退场：白盒化后没有
// 模态浮层，CT 卡与 Tab 悬浮条共用上面这一组卡片阴影。
export const SHADOW_CARD_OFFSET: number = 4;
export const SHADOW_CARD_RADIUS: number = 12;
export const SHADOW_CARD_COLOR_LIGHT: string = '#0D141210'; // 白盒卡片：alpha 26 → 13

// ---------------------------------------------------------------- 动效
// 三档 + 条专用。EASE_OUT 统一做 UI 反馈（进场、退场、微交互）；
// 进出场成对出现时，入用 ease-out（快起慢收）、出用 ease-in，
// 这是 iOS/Material 共用的惯例，反了会显得"弹"。
export const DURATION_FAST: number = 130;   // 按下/松开等微交互
export const DURATION_BASE: number = 240;   // 进场、进度条
export const DURATION_SLOW: number = 420;   // 大区块展开
export const DURATION_ROUTE_IN: number = 220;
export const DURATION_ROUTE_OUT: number = 200;
export const DURATION_SCROLL_TO: number = 380;

// 缓动曲线是动效的另一半：时长决定「多久」，曲线决定「怎么走」。
// 只统一时长而不统一曲线，同一段动画在不同页面仍是两种质感——
// 快起慢收和匀速并置，观感上就是「有的地方利落、有的地方黏」。
//
// 三条曲线的分工按「谁在动」分，不按「进还是出」分：
//   EASE_OUT   跟随手指/用户操作的反应（按下回弹、滚动揭示、路由推入）
//   EASE_IN    离场（用户已决定，界面不该再挽留）
//   EASE_INOUT 位置不明的持续运动（扫描、进度、指示线）
export const CURVE_OUT: Curve = Curve.EaseOut;
export const CURVE_IN: Curve = Curve.EaseIn;
export const CURVE_INOUT: Curve = Curve.EaseInOut;

// ---------------------------------------------------------------- 动效几何
// 路由转场用的是「位移 + 淡入」而不是整页滑动：位移量刻意小于页宽，
// 让转场读起来是「这一页从纸的褶里升起来」而不是「翻页」。
// 转场动效是本站唯一被 DURATION_ROUTE_* 约束、也是唯一必须配
// 非对称曲线（进 ease-out / 出 ease-in）的地方。
export const ROUTE_SHIFT_VP: number = 48;    // 入场横移量
export const ROUTE_FADE_MIN: number = 0.6;   // 入场起始不透明度：留一丝底，别闪白

// 滚动揭示：进入视口的元素从下方 18vp 升起并转正（用法见 RevealOnScroll.ets）。
// 位移量小、时长短——滚动过程中元素在动，再叠一个大位移会晕。
// 判定不用 vp 而用可见比：onVisibleAreaChange 只认「可见面积比」，
// 带的下沿不取 0——初始就压在 0 的元素不算「已进入」，否则首屏之外的
// 内容会在挂载时一起转正，滚动揭示就没了。
export const REVEAL_SHIFT_VP: number = 18;
export const REVEAL_FADE_MIN: number = 0.35;
export const REVEAL_ENTER_RATIO: number = 0.05;  // 自身面积露出 5% 即揭示

// 按压微交互：三档状态（常态/按下/禁用）的统一位移与缩放。
// 缩放只到 0.98：再深一点卡片内容会糊，边框也会被自身圆角吃掉。
export const PRESS_SCALE: number = 0.98;
export const PRESS_OPACITY: number = 0.82;

// ---------------------------------------------------------------- 焦点环
// 给键盘 / 读屏焦点遍历用的可见指示。触屏用户看不到这一环（那是
// pressedStateEffect 的活），但两者缺一不可：外接键盘、开关控制、
// 读屏「逐项浏览」三种场景全靠它才知道当前落在哪一项上。
//
// 全站一个样式，不逐处自定义。理由是焦点环的可发现性取决于**一致性**：
// 同一个环在每处长得一样，用户学一次就会找；一旦某一处细一点粗一点，
// 用户就得逐处重新确认，等于没有。
export const FOCUS_RING_WIDTH_VP: number = 3;   // 3vp：约 2 个逻辑像素，在纸底上够醒目
export const FOCUS_RING_INSET_VP: number = -3;  // 内缩，避免压住卡片自身边框
export const FOCUS_RING_COLOR: string = ACCENT;  // 赭红：与选中态同一色，见下方说明

// 为什么用 ACCENT 而不是 INK：焦点环和「当前选中」是两种不同的语义，
// 但**红色**在本站的语言里已经专指「你现在操作的是这一项」——选中态
// 用的是 ACCENT 文字色与 ACCENT 下划线。再引入第二种高饱和色会
// 让人分不清「选中了」和「聚焦了」。INK 则与正文同色，正文密集的
// 段落里几乎看不见。
//
// 对比度：ACCENT(#9C4A2F) 在页面底 #FBFAF8 上是 5.86:1，
// 在卡片底 #FFFFFF 上是 6.12:1，均过 WCAG AA 的 4.5:1（见 check_contrast）。