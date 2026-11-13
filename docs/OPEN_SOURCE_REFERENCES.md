# 开源参考学习笔记

> **定位**：为「黄河记忆」提供跨平台设计参考。这里只记**实际查证过**的仓库、数值与结论，
> 查不到的一律标「未核实」，不写"应该注意"这类空话。
>
> **查询时间**：2026-10-11。star 数经 GitHub / Gitee API 实时查询，未查到的已标注。
> 第五、六节涉及本机 SDK 与源码的结论，均直接核对本地声明文件与项目代码，非网上转述。
>
> **使用纪律**：本文件是**结论层**笔记——「这个项目做对了什么、我抄不抄、为什么」。
> 踩坑与约束在 `PITFALLS.md`，两者不要重复。

---

## 〇、先记两条「查完才发现」的事

### 1. 我担心的性能坑，本项目并没有踩

调研给出的第一条警告是：官方文档明确 `ForEach` 只在 `List`/`Grid`/`Swiper` 内才是懒加载，
`Scroll` 里用 `ForEach` 等于全量构建、首屏耗时与内存峰值显著。

**核对本项目（2026-10-11）**：

| 位置 | 实际写法 | 结论 |
|---|---|---|
| `ListPage.ets:239` 42 处遗址列表 | `List() { ForEach(this.sites, ...) }` | 容器正确，42 条轻量文本行，无影响 |
| `Index.ets:203` 年代卡流 | `Scroll() { ForEach(this.stats, ...) }` | 固定 6 项，全量构建无问题 |
| `ListPage` 年代/城市/类型 chips | `Scroll() { ForEach(ERAS/CITIES/SITE_TYPES) }` | 6/5/4 项常量，无问题 |

**结论**：不改成 `LazyForEach`。数据量与项复杂度都不构成瓶颈，改了反而引入
`IDataSource` 与 key 生成器的新风险。官方那条警告本身没错，只是**不适用于本项目当前规模**。

### 2. `stateStyles` 无效这件事，反而和 M3 数值对上了

昨天（2026-10-09）实测 `stateStyles({ pressed })` 在本 SDK 抓不到按下态（详见
`PITFALLS.md` 与 `Motion.ets` 顶部注释）。今天查到的 Material 3 官方 token 是
**按下态叠 12% 不透明度的 state layer**——量级只有我原先定的 0.82 压暗的七分之一。
若当初按 M3 补透明度，视觉变化会小到截屏法几乎测不出，**很可能当时会被误判成"生效了"**。

---

## 一、同平台参考（ArkUI / 鸿蒙）

### 优先级最高：官方 codelabs

**`harmonyos_codelabs/OxHornCampus`** — Gitee，16★，2026-07-22
<https://gitee.com/harmonyos_codelabs/OxHornCampus>

官方 codelab 里**唯一以「展示 ArkUI 多样 UI 特性和丰富的动画效果」为卖点**的项目，
与本项目「年代卡片流 + 转场动效」的结构最接近。已读过的源码片段：

- `view/SwiperListItem.ets`：`LazyForEach` + `cachedCount` + `DotIndicator` + `Curve.EaseOut`
- `view/ImageAnimate.ets`：`@StorageLink` + `CustomDialogController` 做图片查看器
- 尺寸全部走 `$r('app.float.*')` 资源而非硬编码（比本项目当前的 `DesignTokens.ets` 更规范）

**⚠️ 当反面教材看**：它的 `SwiperListItem` 在 `LazyForEach` 的 key 生成器里用了
`JSON.stringify`。官方文档明确这是错的（key 应稳定唯一、廉价）。抄结构，别抄这个函数。

**`openharmony/applications_app_samples`** — Gitee，**1447★**，更新至 2026-09-30
<https://gitee.com/openharmony/applications_app_samples>

官方 ArkTS 全量样例。GitHub 镜像只有 7★，**以 Gitee 为准**。关注
`code/Solutions/IM/Chat`、`code/SuperFeature/MultiDeviceAppDev`（多端布局）。

**`openharmony/docs`** — Gitee，**7594★**
<https://gitee.com/openharmony/docs>

> **对本项目最实用的一份**。`zh-cn/application-dev/performance/` 下三篇必读：
> - `list-perf-improvement.md`（列表性能）
> - `component-reuse-overview.md`（`@Reusable` 六种类型分类）
> - `reasonable-using-animation.md`（动效合理使用；**官方把 `setInterval` 手算曲线列为反例**）

**`openharmony/arkui_ace_engine`** — Gitee，**620★**
<https://gitee.com/openharmony/arkui_ace_engine>

ArkUI 框架源码。要深挖 `transition` / `attributeModifier` 的实际行为时才读。

### 第三方（GitHub，star 已核实）

| 仓库 | star | 更新 | 看什么 |
|---|---|---|---|
| [`xiaobaigroup/ClashBox`](https://github.com/xiaobaigroup/ClashBox) | 4513 | 2026-08-15 | **视觉水准最高的可读源码**。README 明说用 Navigation 框架、原生设计风格、深色模式与模糊效果 |
| [`mgz0227/legado-Harmony`](https://github.com/mgz0227/legado-Harmony) | 2201 | — | 阅读类应用，**图文混排详情页与本项目最同构** |
| [`sskEvan/NCMusicHarmony`](https://github.com/sskEvan/NCMusicHarmony) | 257 | — | README 有完整的状态管理装饰器对照表 + TabLayout 共享元素切换动效 |
| [`ausboyue/Wechat_HarmonyOS`](https://github.com/ausboyue/Wechat_HarmonyOS) | 491 | — | 沉浸式暗色状态栏 + Path 绘制 |
| [`AbnerMing888/HarmonyOsRefresh`](https://github.com/AbnerMing888/HarmonyOsRefresh) | 251 | — | 可直接替换本项目 Scroll 的刷新体验 |

未查证活跃度：[`LinysBrowser_NEXT`](https://github.com/awaLiny2333/LinysBrowser_NEXT) 289★、
[`HarmonyOpenEye`](https://github.com/WinWang/HarmonyOpenEye) 618★（2024-08，已停更）。

**ArkUI-X**：GitHub `arkui-x` 组织下 samples 5★ / docs 29★。
Gitee `arkui.com/arkui-x` 存在但 API 无数据，官网 arkui-x.huawei.com 无法访问
——**当前维护状态不确定**，暂不作为参考基线。

---

## 二、跨平台参考（按领域）

### 文化遗产 / 博物馆

**一条诚实的坏消息：没有可对标的成熟开源实现。**
搜索 "heritage / archaeology app" 只返回 0–5★ 的个人项目
（`z4zenn/Heritage-AI-Pakistan`、`sebastianmry/heritage-at-risk`，均为 0★）。
这个细分领域只能自己设计。

唯一够格的官方开源样本：

- [`art-institute-of-chicago/aic-mobile-android`](https://github.com/art-institute-of-chicago/aic-mobile-android) — Android/Kotlin，38★
- [`art-institute-of-chicago/aic-mobile-ios`](https://github.com/art-institute-of-chicago/aic-mobile-ios) — iOS/Swift，40★

**它做对了什么（这条最值得抄）**：藏品详情页是**「图像为主、metadata 为辅」**——
大图 + **可折叠的**题名/年代/媒介/来源字段分组，而不是等权平铺文字。
本项目 `DetailPage.ets` 现在字段平铺，可直接改成这个层级。

配套 [`aic-mobile-cms`](https://github.com/art-institute-of-chicago/aic-mobile-cms)（11★）
说明其内容模型是公开的，可参考字段设计。

**数据结构参考**（是数据不是 UI，但对信息架构有价值）：
[`metmuseum/openaccess`](https://github.com/metmuseum/openaccess) 1436★、
[`Smithsonian/OpenAccess`](https://github.com/Smithsonian/OpenAccess) 441★、
[`ClevelandMuseumArt/openaccess`](https://github.com/ClevelandMuseumArt/openaccess) 101★。

### 地图与地理探索

- [`maplibre/maplibre-gl-js`](https://github.com/maplibre/maplibre-gl-js) — **11845★**
- [`mapbox/supercluster`](https://github.com/mapbox/supercluster) — **2384★**，标记聚合的算法源头
  （网格化聚合 + 跨 zoom 层级增量聚合）
- [`organicmaps/organicmaps`](https://github.com/organicmaps/organicmaps) — **15640★**，离线地图完整实现
- [`osmandapp/OsmAnd`](https://github.com/osmandapp/OsmAnd) — 6071★，POI 密集型地图
- [`maplibre/maplibre-compose`](https://github.com/maplibre/maplibre-compose) — 586★，Compose 封装

**可借鉴的节奏**：地图相机变化 → 触发 bounds 查询 → **「moveend 后加载」**——
只在用户停手后加载当前视野数据。聚合点按 zoom 分级：低 zoom 显数字气泡、高 zoom 显单标记。

> 注：本项目已于 `bf9f2bc1` 撤下地图模式（回到帘幕基线）。此节留作将来重启时的参考。

### 长列表与内容流

- [`google/nowinandroid`](https://github.com/google/nowinandroid) — **21903★**，架构范本，
  `contentType` 复用 + 无限滚动 + 图片渐进加载的教科书实现
  （**正确路径是 `google/nowinandroid`**，我最初试的 `google/android/nowinandroid` 与
  `android/nowinandroid` 都 404）
- [`android/compose-samples`](https://github.com/android/compose-samples) — **23507★**，
  LazyColumn / LazyGrid / Paging 相关 sample 是权威参考
- [`Shopify/flash-list`](https://github.com/Shopify/flash-list) — 7244★，虚拟化与回收策略标杆
- [`coil-kt/coil`](https://github.com/coil-kt/coil) — 11926★，渐进式/占位图加载标准方案
- [`gregkorossy/lazy-sticky-headers`](https://github.com/gregkorossy/lazy-sticky-headers) — 36★，
  Compose sticky header 实现思路
- [`vipulasri/Timeline-View`](https://github.com/vipulasri/TimelineView) — 3888★（旧 Java 库），
  但**「时间轴节点 + 连接线」的视觉方案**可直接借鉴到年代轴

### 动效 / 手势交互

- [`Dimillian/IceCubesApp`](https://github.com/Dimillian/IceCubesApp) — **7081★**，
  **iOS 上设计水准最高的开源 App 之一**。滚动驱动的 header 折叠/展开、
  `.matchedGeometryEffect` 标签切换、滚动时 toolbar 渐变消失、`scrollTransition` 卡片翻转
  （**路径带 App 后缀**，`IceCubesApp/IceCubes` 404）
- [`skydoves/Orbital`](https://github.com/skydoves/Orbital) — 1200★，Compose Multiplatform 动态转场，
  **含 shared-element 转场**，Compose 生态里最接近 `matchedGeometryEffect` 的方案
- [`amosgyamfi/open-swiftui-animations`](https://github.com/amosgyamfi/open-swiftui-animations) —
  5665★，大量 springs / transitions 对照示例
- [`airbnb/lottie-ios`](https://github.com/airbnb/lottie-ios) — 26899★，转场动画通用方案
- [`chrisbanes/haze`](https://github.com/chrisbanes/haze) — 2594★，滚动驱动的背景模糊

---

## 三、按压反馈：唯一查得到权威数值的部分

### Material 3 官方 token（可查证）

来源：[`material-web` tokens/v0_192/_md-sys-state-layers.scss`](https://github.com/material-components/material-web/blob/main/tokens/versions/v0_192/_md-sys-state-layers.scss)

| 状态 | 不透明度 |
|---|---|
| Hover | 0.08 |
| Focus | 0.12 |
| **Pressed** | **0.12** |
| Dragged | 0.16 |

做法：叠一层前景色的 state layer，**不改变尺寸**。

**三条与本项目现状冲突的结论**：

1. **M3 不采用缩放做按压反馈**——缩放是 iOS / 自定义风格的用法。
   本项目 `Motion.ets` 现在定的「有底色缩放 0.98」是 iOS 路子，不是 M3 路子。
2. **0.12 远小于本项目现在定的 0.82 压暗**。两者差七倍，量级完全不同。
3. **M3 的 state layer 是即时切换，不做过渡**（M3 没有给出 pressed 的时长数值）。

### 未核实的部分（不要当标准用）

- **iOS HIG 的 haptic 数值：查不到。** 抓取 `developer.apple.com` HIG Feedback 页面时
  连接被重置（ECONNRESET），**未取得一手来源**。
- **「scale 0.96–0.98 + opacity 0.6–0.9 + duration 100–150ms + 轻 haptic」是社区惯例，
  没有权威规范背书。** 引用时须注明是经验值。
- Material 规范未规定按压 haptic（由 Android 系统 `performHapticFeedback` 提供，非 M3 token）。

### 对本项目的落点（待定，未实施）

若要把按压反馈改成手写版，依据应是 **M3 的 12% state layer**，而不是现在写在
`Motion.ets` 里的「有底色缩放 0.98 / 无底色压暗 0.82」。这意味着：
56 处 `stateStyles` 全部改写、lint_motion 规则 3 判据重做、现有二分约定推翻。
**改动面铺满 10 个页面，需先定方案再动手。**

---

## 四、可迁移手法速查

### ArkUI 侧

| 手法 | 要点 |
|---|---|
| **组件复用** | `@Reusable @Component` + `aboutToReuse(params)` 重置内部 `@State`。官方分六型，本项目卡片流最贴「标准型 + `cachedCount`」 |
| **状态装饰器分工** | `@State` 局部；`@Prop` 父→子单向；`@Link` 双向（适合 chips↔列表联动）；`@Observed`+`@ObjectLink` 处理复杂对象型数据源；`@StorageLink` 跨页共享 |
| **动效** | 只用系统属性动效 API：`.animation({duration, curve, delay, playMode})`、`withAnimation`。**官方把 `setInterval` 手算曲线列为反例**（UI 线程高负载丢帧） |
| **转场** | `transition()` 配 `sharedTransition` 做卡片→详情的大图转场（对应 SwiftUI `matchedGeometryEffect`） |
| **资源化** | 尺寸/颜色一律 `$r('app.float.*')`/`$r('app.color.*')`，深浅色由资源目录自动切换，不写代码。**本项目当前的 `DesignTokens.ets` 硬编码值，可考虑后续迁到资源目录** |
| **新观察方案** | `ObservedV2` + `@Trace`（[官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-new-observedv2-and-observed)）。笔记/收藏这类频繁变更列表优先考虑 |

### Compose 侧

- `Modifier.combinedClickable` —— 长按/多指手势，替代裸 `clickable`
- `LazyColumn` 的 `key` / `contentType` / `animateItem()`；`contentType` 让异构 item
  复用时不必销毁重建，是长列表不掉帧的关键
- `collectIsPressedAsState()` + `collectIsDraggedAsState()` —— 拿按压/拖拽状态驱动
  缩放/透明度/阴影，而不是只靠默认水波纹
- `Modifier.graphicsLayer` 做 scale/alpha，走绘制层避免重组
- 滚动揭示：读 `LazyListState.layoutInfo.visibleItemsInfo` 算进入视口比例，驱动 alpha + offset
- `animateItemPlacement()` / `animateItem()` 做列表项重排动画（**时间轴筛选后重排很关键**）

### SwiftUI 侧

- `.matchedGeometryEffect(id:in:)` —— 卡片 ↔ 详情页共享元素转场，**领域内最值得抄的转场套路**
- `.transition(.opacity / .move / .scale)` 配 `withAnimation`
- 滚动驱动：`GeometryReader` + `PreferenceKey` 取 offset，再 `.offset(y:)` / `.scaleEffect` / `.blur(radius:)`
  做视差与折叠
- `.scrollTransition` 做卡片随滚动翻转、淡出

---

## 五、同题材项目：Digital-Yellow-River（最重要的一档）

> `changrongqi/Digital-Yellow-River` — <https://github.com/changrongqi/Digital-Yellow-River>
> **0★，创建 2026-09-28，11 分钟后停止推送**，TypeScript，26 个 .ets / 13177 行。
> 本地副本：`_scratch/dyk/Digital-Yellow-River-main/`（2026-10-11 拉取）。
>
> **它也叫「黄河记忆」**，覆盖黄河河南段（三门峡/洛阳/郑州/开封/濮阳/安阳）
> 23 处遗址，6 个年代段、4 种类型。**同题材、同技术栈。**
> 这是全网唯一可对标的同题材开源项目。

### 一句话结论

**它是一份优秀的信息架构参考稿，不是工程基建参考稿。**
抄它的「内容分层与数据结构」，守住我的「数据组织、质量门禁、存储方案」。

### 一、我必须承认的差距（它比我强）

| 它做到的 | 我的现状 | 判断 |
|---|---|---|
| **详情页 6 页签**（`Detail.ets:300-322`，`Tabs + SubTabBarStyle`，横幅常驻不随内容滚动）：介绍/考古/事件/诗词/文旅/笔记 | 单页长滚动 + 时间轴 | **内容量翻倍后单页滚不动，这是刚需** |
| **事件子详情页** `EventDetail.ets`（350 行） | 无 | 抄 |
| **结构化事件模型** `Heritage.ets:88-100`：`year/title/summary/background/process/impact/figures[]/artifacts[]/furtherReading/commentary` | `{year: string, text: string}` 两个平铺字段 | **我最该抄的一条** |
| **向后兼容迁移器** `HeritageDataLoader.ets:158-213`：旧格式 `"1921年：正文"` 用正则 `/^(\d{3,4}年)[:：]\s*(.+)$/` 自动拆成 `year + title` | 无 | **「字段只增不改 + 加载层迁移」的模式可直接套用** |
| **知识图谱** `KnowledgeGraph.ets`（1087 行，Canvas 节点网络、主题增删改、归类管理） | 完全没有 | 功能缺口 |
| **文旅深度化**：`itinerary` 字段是实测成品（建议时长 2.5—3.5h / 推荐动线 / 交通 / 串联联动），**23 条全部非空** | 无 | 数据质量差距 |
| **推荐算法** `utils/Recommendation.ets`（见下） | RecommendPage 算法更简单 | 抄思路 |

### 二、可以直接抄的五处（附文件与行号）

1. **Canvas 知识图谱是圆周布局，不是力导向**（`KnowledgeGraph.ets:444-512`）：
   `angle = (i/n)*2π - π/2` 从 12 点方向顺时针；中心=选中主题，外环=已归类遗址；
   `layoutR = max(60, min(w,h)/2 - themeR - nodeR - 20)`。
   **它踩过的坑**：`CanvasRenderingContext2D` **默认单位就是 vp，不要乘 dpr**
   （`:436-442` 注释明说前两轮 ×dpr 导致图形放大 3 倍出画布）。
   命中测试：绘制时把 vp 坐标存进 `graphNodes[]`（`:509`），`onClick` 用
   `ClickEvent.x/y` 做距离判定 `dist <= r + 10`（`:515-526`）。
   `onReady` + `onAreaChange` 都要重绘——`context.width/height` 在 `onReady` 前为 0。

2. **推荐算法：分档而非连续分数**（`utils/Recommendation.ets:53-90,131-142`）：
   16 维 one-hot（年代 6 + 类型 4 + 城市 6）→ 余弦相似度。
   **关键洞察：对 one-hot 向量，余弦相似度退化成「共享特征维度数」**，
   分数只有 {0, 1/3, 2/3, 1} 四档。收藏微调 `+0.1`（`:47`）——刻意小于最小非零差 1/3，
   只在同档内提序、不颠倒主序。Top-N 两轮兜底（先取 score>0，不足再补满）保证区块永空。
   **⇒ 42 条规模下连续加权容易糊成一团，我该照搬分档思路**，维度可扩（加「是否 A 级景区」「有无出土文物」）。

3. **LWW 纯函数原语**（`SyncService.ets:193-199`）：`updatedAt` 谁新谁赢，
   完全相等时 **`deviceId` 字典序小者胜**。确定性兜底保证两端并发写也收敛到同一条，
   不会来回覆盖。**同样的确定性兜底加进我的 RDB 合并逻辑即可。**

4. **分层约定**：`pages`(UI) / `data`(解析) / `service`(业务+存储) / `model`(纯类型) /
   `utils`(纯函数) / `components`。README:58 写明原则。
   关键收益：`HeritageDataLoader` 与 `MockHeritages` **共用同一 `parseHeritageList` 入口**，
   结构漂移立刻暴露。**⇒ 这是我拆掉 615KB 单文件的直接理由（如果我也需要 mock 的话）。**

5. **API 26 上依然有效的 ArkUI 写法**：
   - `getUIContext().getHostContext()` 取 context，替代已废弃的全局 `getContext(this)`（`:133`）
   - `@Prop @Watch('onRefreshTick')` + 父页 `onPageShow` 里 `tick += 1` 驱动跨页返回刷新（`Index.ets:36-40`），**替代传统 emitter**
   - `bindContentCover` 做页面级全屏遮罩，**不被 Scroll 裁剪**（`ImageGallery.ets:285-290`）
   - `@Builder` 里**必须直读 `this.xxx`，禁止当参数传入**（`Index.ets:81-85` 把它写成硬约束注释，
     「发现页筛选 chips 曾因此高亮失灵」）——**这条我会踩，值得提前规避**
   - `ModalTransition.NONE` 避免灯箱弹出动画抖动

### 三、它的同步方案不如我，别改

它**根本没用 RDB**——`grep relationalStore` 全项目零命中：
- 本地持久化 = `preferences` 整表 JSON（`FavoriteService.ets:79-89`，键 `favorites_json`），**不是数据库**
- 同步 = `distributedKVStore`（`SyncService.ets:45-49,115`，`autoSync: true`）

**关于我那个复合键疑问**：它没这个问题，因为它压根没有表。单版本 KV 是纯键值对，
没有主键/复合键概念。**它是绕过了问题，不是解决了问题。** 代价是
无法条件查询（`getFavoriteByTag` 只能全表拉出来在内存 `indexOf` 过滤，`:115-125`），
收藏/笔记一多就是 O(n) 全表扫；并发下 `favorites_json` 整表覆写（`:173`）会丢写。

**⇒ 我的 `relationalStore.setDistributedTables` + RDB 明显更优，不要因为它用 KVStore 就改回去。**

**一处文档自相矛盾值得记**：README 与 `PROJECT_PLAN.md` 都写 API 12，
但 `build-profile.json5` 实测 `targetSdkVersion: "26.0.0"`——**它抄错了自己的配置**。

### 四、我全面领先的地方（具体）

| 维度 | 它 | 我 |
|---|---|---|
| 数据量 | 23 条 | **42 条** |
| 数据组织 | 单 `heritage_data.json` 599KB **+ `MockHeritages.ets` 615KB 重复一份** | 42 文件 493KB，不重复 |
| 无障碍 | **零**（`grep accessibility` 全项目 0 命中） | 4 个 lint 门禁 |
| 动效 | **零**（`grep animateTo/.animation(/transition(` 0 命中） | 有 |
| 设计令牌 | **零 `$r(` 引用**；色板硬编码 **325 处 hex**，最多 `KnowledgeGraph.ets` 83 处、`Favorites.ets` 61 处、`Detail.ets` 59 处 | 令牌化 + 对比度门禁 |
| 深色模式 | `dark/color.json` 只改了启动背景色，**所有页面硬编码 hex 无法适配** | 令牌驱动 |
| 测试 | `LocalUnit.test.ets` / `Ability.test.ets` 全是 DevEco 生成的空壳 `expect('abc').assertEqual('abc')` | 6 gate |
| Lint | 只配 `@security/*` 密码学规则，**无 UI/性能/无障碍规则** | 4 门禁 |
| LICENSE | README 声称 MIT 但**目录里没有 LICENSE 文件** | — |

**API 版本不是差距来源**：它用 `Preferences` 存整表 JSON 很可能是因为 API 12 时
`setDistributedTables` 支持尚不完善（被时代所迫）。`SubTabBarStyle`/`bindContentCover`
都是 API 12 就有的，**所以 UI 能力上我不缺东西**。

### 五、代码质量：认真写的，但没完工

**不是 AI 占位代码**——注释密度异常高且是**问题驱动**的：
`SyncService.ets:23`「踩坑 1/2/4」、`HeritageDataLoader.ets:42-44`「整表解析出 0 条必须抛异常，
否则失败被静默成空数据，M1.6 曾因此回归」、`KnowledgeGraph.ets:15`「前两轮 ×dpr 致 3 倍放大」。
**这些是真踩坑才写得出的话**，一次性生成不会自带这种回归记忆。
边界处理也扎实：越界 `eventIndex` 返回 null 不崩溃（`EventDetail.ets:86-95`）、
异步回写前检查 `disposed`（`ImageGallery.ets:41,77`）、DeviceManager 创建失败熔断不重试（`:378-394`）。

**但有明显未完工痕迹**：README 所有链接指向 `file:///e:/HarmonyOS_coding/...`（本地绝对路径）；
`PROJECT_PLAN.md` 说「五市」而代码里 `ANYANG` 六城矛盾；README 说 API 12 而配置是 26；
`M5 创新扩展 🚧` 标记未完成；无 LICENSE 实体。**它自己的文档不可信。**

**⇒ 可以抄**：架构分层、事件结构化模型与迁移正则、Canvas 图谱的几何与单位适配、
LWW 兜底、ImageGallery 组件骨架、推荐算法分档思路。
**⇒ 不要抄**：整表 JSON 存储、硬编码色板、`Preferences` 方案、以及它的项目文档。

---

## 六、内容与数据建模的网上参考

> 前四节是「界面怎么做」，第五节是同题材项目，这节是「数据怎么组织」。
> 对一个内容型应用，后两者往往比前者更决定上限。

### 1. 先说三个「查完才知道」的坏消息

1. **中国考古遗址 / 文博内容展示类移动 App，没有可参考的成熟开源实现。**
   用「文物」「博物馆」「非遗」「考古」「文物保护单位」在 GitHub 全库检索
   （`考古` 命中 477 个仓库），中文项目几乎全是**毕设/课设模板与 CRUD 管理后台**：
   `small-bears/artifact`（102★，SpringBoot+Vue 文物管理系统）、
   `666bears/IntangibleCultural`（56★，非遗数字化）、
   `lingdian1226/china-cultural-heritage`（0★，文物保护单位数据库）、
   `PenguinByte233/Heritage-App`（6★，非遗小程序）。
   这些是后台管理系统，不是内容产品，**信息架构层面零参考价值**。

2. **黄河流域相关内容在 GitHub 上是零。** 「黄河」「都江堰」「大运河」「敦煌」
   检索无任何有价值的开源项目或数据集。

3. **故宫博物院、国博均未开放官方结构化数据集。** 唯一一个声称聚合全球博物馆
   公开数据的 `FlamingoCheers/wenwu-database`（0★）实际不可用。

**结论**：这个题材的内容架构必须自己长，没有现成范式可抄。
能抄的是**通用方法论**（下面的 Pleiades / CIDOC CRM），不是具体实现。

### 2. Pleiades —— 最值得抄的数据模型

<https://pleiades.stoa.org/>，数据集 <https://github.com/isawnyu/pleiades.datasets>（数据仓库 53★，主站 star 未核实）

古地名 gazetteer（地名文献），JSON 接口公开可直连（实测 `places/423087/json` 可取）。
**它的字段设计就是「遗址类内容」该有的样子**，我实际拉了一份，顶层字段：

| 字段 | 作用 | 对黄河记忆的意义 |
|---|---|---|
| `placeTypes` + `placeTypeURIs` | 受控词表枚举（如 `settlement`），配词表链接 | **筛选项从数据里 `uniq()` 出来，不要硬编码**。我现在的 `ERAS`/`CITIES`/`SITE_TYPES` 是硬编码常量 |
| `reprPoint` `[lon, lat]` / `bbox` `[minLon, minLat, maxLon, maxLat]` | 单点 / 包围盒 | **加这两个字段，遗址数据就能直接上地图**（成本极低） |
| `connectsWith` | 遗址间关联（URI 数组） | 对应「仰韶 → 龙山」的传承关系，是文化谱系的可视化基础 |
| `locations[].attestations[]` | `{timePeriod, timePeriodURI, confidence, confidenceURI}` | **这就是年代分期的 schema**：用受控词表 URI + 置信度，而不是自由文本 |
| `references[]` | 文献出处，带 `title`/`authors`/`urls` | 可映射到我的「事件列表」 |
| `review_state` / `rights` / `creators` / `history` | 溯源与版权字段 | 内容合规字段，值得补 |

**最该抄的一条：`attestations` 用「受控词表 + 置信度」而不是自由文本。**
我现在的分期是靠 `era` 枚举字段硬划的，粒度只到「仰韶/龙山」，
没有「某事件发生在仰韶晚期」这种表达力，也没有置信度概念。

### 3. CIDOC CRM —— 事件-实体建模的标准

<https://cidoc-crm.org>

文化遗产领域的 ISO 标准事件模型，提供 E53 Place（地点）、E52 Actor（人物）、
E84 Time-Span（时间）等标准类。

**具体建议**：事件列表采用 `{when: {start, end}, what: E5, where: E53, who: [E52]}` 结构，
而不是我现在 `{year: string, text: string}` 的平铺两字段。
差别在于：`{start, end}` 能表达「前5000—前3000」这种区间，
现在用单个 `year` 字符串表达区间是丢失信息的。

### 4. 时间轴交互：TimelineJS3

<https://github.com/NUKnightLab/TimelineJS3> — **3225★**，JS，叙事时间轴组件

**分期时间轴的交互可以直接照搬其 slider + slide 结构**，而不是自绘横条。
它是目前这个细分领域唯一高星的成熟组件。

### 5. 其他 DH 参考

| 项目 | URL | star | 可参考 |
|---|---|---|---|
| **Omeka S** | <https://github.com/omeka/omeka-s> | 514 | 博物馆/图书馆/档案馆出版系统，PHP。**内容发布的信息架构范本** |
| **ResearchSpace** | <https://github.com/ResearchSpace/ResearchSpace> | 143 | 基于 CIDOC CRM + RDF 三元组的文化遗产知识图谱，SPARQL 查询 |
| **CBDB sqlite** | <https://github.com/cbdb-project/cbdb_sqlite> | 226 | **中国历代人物传记数据库**。中文史数据库字段设计的范本，人物-官职-社会关系表结构 |
| **Recogito 2** | <https://github.com/pelagios/recogito2> | 165 | 图像/文本语义标注，Scala。**文物图上挂热区标注**的交互可参考灯箱 |
| **Mukurtu CMS** | <https://github.com/MukurtuCMS/mukurtucms> | 95 | 原住民文化遗产 CMS，支持 IIIF / 媒体 bundle |
| **CHGIS** | <https://github.com/cga-harvard/chgis> | 8 | 哈佛中国历史地名数据（配套有 [MCP Server](https://github.com/huajibing/CHGIS_MCP_Server)） |
| awesome-digital-humanities | <https://github.com/dh-tech/awesome-digital-humanities> | 418 | DH 工具清单 |

### 6. 具体落点（成本从低到高）

- [ ] **筛选项从数据 `uniq()` 出来**，不硬编码 `ERAS`/`CITIES`/`SITE_TYPES`
      （抄 Pleiades 的受控词表思路，改动最小、收益最直接）
- [ ] 遗址 JSON 增加 `bbox` + `connectsWith` 两个字段 → 数据可地图化、可关联
- [ ] 分期加 `attestations[].confidence`（置信度）→ 内容严谨性提升，评审会认
- [ ] 事件列表改 `{start, end}` 区间结构（抄 CIDOC CRM 的 E84 Time-Span）
- [ ] 详情页时间轴交互参考 TimelineJS3 的 slider+slide
- [ ] 灯箱加文物图热区标注（抄 Recogito）

---

## 七、多设备分布式同步：官方路线与我当前设计的出入

> 四道门禁之一是「双设备组网」。这一节是**核实本机 SDK 后**的结论，
> 不是网上转述——涉及 API 23+ 新特性的地方以本地 `ets/api` 声明文件为准。

### 官方能力入口（新版命名）

统一入口是 **Distributed Service Kit** + **ArkData Kit**：

| 能力 | 模块 | 首批 API |
|---|---|---|
| 设备发现/绑定/上下线监听 | `distributedDeviceManager`（`@kit.DistributedServiceKit`） | 10 |
| 分布式键值库端端同步 | `distributedKVStore`（`@kit.ArkData`） | 9 |
| 关系库跨设备同步 | `relationalStore.setDistributedTables` | 9 |
| 跨设备拉起 Ability | `abilityConnectManager` | — |

**两条命名陷阱**（我核实过 SDK，务必按新版写）：
- **`distributedDataPreferences` 在新版文档树中已不存在**（官方 docs 仓库全文检索 0 命中），
  属旧版 API。对应能力是 `distributedKVStore` 的单版本 / 设备协同两种模式。
- `@ohos.distributedHardware.deviceManager` 是旧命名，新版为 `distributedDeviceManager`。

### 官方 sample（已实际访问确认可读，gitcode 官方仓）

- 分布式组网认证（设备管理 + PIN 配网）：
  <https://gitcode.com/openharmony/applications_app_samples/tree/master/code/DocsSample/DistributedAppDev/DistributedAuthentication>
- 分布式 RDB（含自动/手动同步设置 UI）：
  <https://gitcode.com/openharmony/applications_app_samples/tree/master/code/SuperFeature/DistributedAppDev/DistributedRdb>
- 分布式 KVStore：<https://gitcode.com/openharmony/applications_app_samples/tree/master/code/SuperFeature/DistributedAppDev/Kvstore>
- 分布式备忘录（`distributedDataObject`）：
  <https://gitcode.com/openharmony/applications_app_samples/tree/master/code/SuperFeature/DistributedAppDev/DistributedNote>
- 分布式软总线底层 `DistributedSoftbusBase` —— **sys 级，仅系统应用可用**

### ⚠️ 与我当前设计的实质出入（已用本机 SDK 核实）

**SDK 实测结论**：`setDistributedTables(tables)` 重载存在（`@ohos.data.relationalStore.d.ts:5643`，
API 9）；带 `DistributedType` 的重载存在（同文件 5660 行后，`DistributedType.DISTRIBUTED_DEVICE = 0`，
API 10，`DISTRIBUTED_CLOUD = 1`）。**我的代码用的是无 type 的重载，走默认设备间同步——这一点是对的。**

**出入一：官方没让应用自己走 SoftBus 传字节流再手工落库。**
官方路线是**数据管理服务直接读沙箱库、按 `deviceId` 走加密通道投递到对端同 bundleName 的库**，
应用只调 `sync()` / 订阅 `dataChange`。
我的 `SoftBusRdbTransport.ets` 实际已经是这个形态（调 `setDistributedTables` + `pushToDevices` +
`remoteQuery`），**不是**自研协议，这点没问题。但我额外建的 `sync_meta` 冲突台账
在官方设计里没有对应物。

**出入二：RDB 单版本表模式（API 23+）需要落地 schema 文件。**
官方要求在 `resources/rawfile/arkdata/schema/sync_schema.json` 声明同步列与**解冲突列**：
- `deviceSyncFields` 声明同步列
- `primaryKey: true` 标解冲突列，**只能一个、必须 UNIQUE、必须是 uuid 类全局唯一字段、不能有 null**
- **不支持同步自增主键**
- schema 变更必须升 `version`，同步列只能增不能减

**我核实的结果：`app/entry/src/main/resources/rawfile/arkdata/` 目录不存在。**
本机 SDK 的 `ets/` 下也搜不到 `sync_schema` / `deviceSyncFields` 字样——
这是**文档级约定而非 SDK 声明**，需要按官方文档落地 schema 文件才能用单版本表模式。

**⇒ 对我的影响**：我的表全部用 `TEXT PRIMARY KEY`（`target_key` / `note_id` 等，
见 `LocalRdbImpl.ets:15-35`），**没有 UUID 全局唯一列**，若要切官方单版本表模式，
得先加一列 uuid 并按官方 schema 声明。当前用无 type 重载的设备间协同模式可以先跑。

**出入三：一致性只有最终一致。** 官方明确「同应用跨设备数据同步**仅支持最终一致性**」，
强/弱一致性不支持。**⇒ 门禁措辞不能写「实时一致 / 强一致」，这条要改。**

**出入四：硬限制（影响门禁可行性）**
- 单应用最多同时打开 **16 个**分布式 RDB / KV 库
- 单库最多注册 **8 个**变化订阅回调
- 复合键表**不能**设分布式表
- 同一张表不能同时是端端 + 端云分布式表且不可切换
- 同一库下所有端端分布式表必须同一存储机制且不可切换

⇒ **违规确认（已改）**：`SYNC_TABLES` 里的 `note_tag`、`favorite_tag`、**`progress`**
三张表当时**都是复合键表**（`LocalRdbImpl.ets:15-35`；现状：三张表已改为单列
`row_id TEXT PRIMARY KEY`，见 `migrateJoinTables`，本段保留为问题定位记录）：
- `note_tag` PK `(note_id, tag_id)`
- `favorite_tag` PK `(target_key, tag_id)`
- `progress` PK `(target_key, section)`

官方规则是「不支持将含有**复合键**的表设置为分布式表」，判据是**复合主键**，
不是「有没有主键」。所以 `progress` 同样违规——初版笔记漏了它，
**现按三张表全部处理**（见第九节待办）。

**出入五：权限是硬门槛。** 必须声明 `ohos.permission.DISTRIBUTED_DATASYNC`
（**我已声明，`module.json5:51`** ✓）且**首次启动必须弹窗运行时授权**。

**出入六：组网入口必须走 deviceManager，不能裸用 SoftBus。** `sync()` 的 `deviceIds`
参数要的是 `networkId`，来自 `getAvailableDeviceListSync()`；软总线只是其下层传输，
`@ohos.softbusBase` 是系统 API 应用不可用。**我的实现已经是这条路线** ✓

### ArkUI 状态管理在多设备场景

- 跨页面/跨 UIAbility：新版推荐 **AppStorageV2**（API 12+）。
  注意 **AppStorage 与 AppStorageV2 数据互不共享**，AppStorageV2 支持主线程内
  多个 UIAbility 实例间共享。
- **状态管理是进程内机制，不跨设备。** 官方没有「`@StorageLink` 跨设备」这种能力。
  社区通行做法：**本地 UI 状态走 AppStorageV2，跨设备真值走 RDB/KVStore
  收到 `on('dataChange')` 回调后刷新 AppStorageV2 里的 view-model**——
  即状态层做单向缓存刷新，而不是让状态变量本身参与同步。
  ⇒ 我的设计只要保证「RDB 变化 → 通知 → 刷新」这条链即可，无需改造。

### 门禁需要改的两处（已确认，非推测）

- [ ] **一致性措辞**：门禁/文档里不能写「实时一致」「强一致」，官方只支持最终一致
- [x] **`SYNC_TABLES` 核对**：确认不含复合键表（`note_tag` / `favorite_tag` / **`progress`**）
      —— 违规已核实，见第七节出入四
- 官方硬限制一并存档：单应用最多 16 个分布式 RDB 库、单库最多 8 个变化订阅回调、
  复合键表不可设分布式表、端端/端云不可混配且不可切换、同库必须同存储机制
- 官方「关系型数据库数据同步」页（`zh-cn/application-dev/database/data-sync-of-rdb-store.md`）
  是这些限制的**权威出处**——SDK 的 `.d.ts` 里只写了参数和错误码，
  **没有「约束限制」章节**，只看 d.ts 会漏掉全部约束

### 未核实

- **GitHub 上开源的多设备鸿蒙应用**：本轮 GitHub 全站连接超时，**star 数一律未核实**。
  搜索页见过三个候选（**未逐一验证内容，仓库名可能已变化**）：
  `spartdark/harmony_os-distributed_data_service_apis`、
  `changrongqi/Digital-Yellow-River`（README 标称是黄河河南段分布式文化遗产档案应用，
  **与本项目同题材**，若真实存在值得优先看）、
  `aflzm/Smart-Farm`。
  结论：GitHub 上「完整可跑双设备同步」的高星开源鸿蒙应用**基本不存在**，
  建议直接依赖上面那些官方 sample。
- **社区实战踩坑**：本轮搜索引擎在该网络出口下不可用，**未取到可信社区帖子**，故不列。
- `developer.huawei.com` 为 SPA 正文抓不到；上述引用的华为 URL 已逐个 HTTP 200 校验存在，
  但**正文内容我是从 OpenHarmony 官方 docs 仓库（gitcode.com/openharmony/docs）读的**，
  两者对应但版本可能有差异。涉及 API 23 单版本表等新特性，**以本地 SDK 声明文件为准**。

---

## 八、本项目会踩的坑（官方文档口径）

以下为 `openharmony/docs` 与调研汇总，**均未在本项目实际发生**，先记着：

1. **`Scroll` 嵌 `ForEach` 等于全量构建**——本项目当前规模不构成问题（见第〇节），
   但**数据量增长后要重估**。
2. **`keyGenerator` 冲突**导致渲染错乱；**不要在 `LazyForEach` 的 key 生成器里用
   `JSON.stringify`**（OxHornCampus 就犯了这个）。
3. **复用导致状态错位**：`@Reusable` 组件复用时若不重置全部 `@State`，会残留上一条数据的
   状态——这是卡片流「图片串行 / 收藏态错位」的典型根因，必须在 `aboutToReuse` 里逐字段赋值。
4. **`@State` 刷新粒度**过粗会全量刷新。
5. **长列表动画开销**：`cachedCount` 太小滚动掉帧、太大占内存；`.animation()` 挂在
   长列表 item 上会持续占用动画通道。
6. **扁平化布局**（官方四大优化之一）：减少嵌套层级与组件数，避免过度绘制。
   `Column` 套 `Stack` 套多层 `Row` 的卡片会明显拖慢滚动。

---

## 九、待办（按优先级）

**同步门禁相关（2026-10-11 核实 SDK 后确认，非推测）**
- [x] 三张复合键表全部剔出分布式注册：`note_tag` / `favorite_tag` / **`progress`**
      —— 官方明确「不支持将含有复合键的表设置为分布式表」，原 `SyncModels.ets` 三张全违规
- [x] **三张关联表改单列 `row_id` 主键，六表全部重回官方分布式通道**（2026-10-11 完成）
      —— `row_id` = 两个业务列以 `char(31)` 拼接，与 `mergeElementSets` 的逻辑身份一致，
      所以同步行天然收敛到同一行。**不需要 uuid 全局唯一列**：官方 schema 文件
      只在**单版本表模式**下需要，多设备协同表模式「不支持设置schema，默认不读取schema文件」，
      本项目用的就是默认模式。旧库就地迁移（建 `__new` → 搬 → DROP → RENAME），
      详见 `LocalRdbImpl.migrateJoinTables` 与 PITFALLS 19d/19e/19f
- [x] 一致性措辞体检：全项目搜「实时一致 / 强一致」**零命中**，
      `设计方案.md:28` 本来就写的「最终一致性」，无需改动
- [ ] 若要切官方单版本表模式：才需要落地 `rawfile/arkdata/schema/sync_schema.json`
      （SDK 里搜不到该约定，属文档级）—— 当前无此需求

**内容与数据建模（抄 Digital-Yellow-River，第五节）**
- [ ] **事件结构化**：`{year, text}` → `{year, title, summary, background, process, impact, figures[], artifacts[], furtherReading}`
      + 加载层正则迁移器（抄 `HeritageDataLoader.ets:158-213`）—— **成本最低收益最高的一条**
- [ ] **详情页改 6 页签**（介绍/考古/事件/诗词/文旅/笔记），横幅常驻不随内容滚动（抄 `Detail.ets:300-322`）
- [ ] **事件子详情页**（背景/经过/影响/相关人物文物/延伸阅读），空字段自动隐藏小节
- [ ] **推荐算法改分档**（抄 `Recommendation.ets`）：one-hot 余弦相似度退化成共享维度数，
      收藏微调 +0.1 < 最小非零差 1/3，Top-N 两轮兜底保证区块永空
- [ ] **知识图谱**（Canvas 圆周布局，注意**单位已是 vp 不要乘 dpr**）
- [ ] **`@Builder` 里直读 `this.xxx` 禁止当参数传入**——它的筛选 chips 曾因此高亮失灵，我大概率会踩

**内容与数据建模（抄 Pleiades / CIDOC，第六节）**
- [ ] 筛选项从数据 `uniq()` 出来，不硬编码 `ERAS`/`CITIES`/`SITE_TYPES`（抄 Pleiades）
- [ ] 遗址 JSON 加 `bbox` + `connectsWith` → 数据可地图化、可关联
- [ ] 分期加 `attestations[].confidence`
- [ ] 事件列表改 `{start, end}` 区间结构（抄 CIDOC CRM 的 E84）
- [ ] 详情页时间轴交互参考 TimelineJS3 的 slider+slide
- [ ] 灯箱加文物图热区标注（抄 Recogito）

**界面**
- [ ] 按压反馈改写成手写版，依据 M3 的 12% state layer —— **需先定方案**
- [ ] `DetailPage` 字段改成可收起分组（抄芝加哥艺术博物馆 App）— 设计提升最直接
- [ ] 灯箱 Swiper 分级加载：列表用缩略图、灯箱载原图
- [ ] `DesignTokens.ets` 是否迁到 `$r('app.float.*')` 资源目录
- [ ] 年龄轴视觉方案（抄 `vipulasri/Timeline-View` 的节点+连接线）
- [ ] 笔记/收藏列表考虑迁 `ObservedV2` + `@Trace`
- [ ] RDB 合并逻辑补 LWW 确定性兜底（相等时 `deviceId` 字典序小者胜，抄 `SyncService.ets:193-199`）

## 十、查证状态说明

- **已核实**：Gitee star（Gitee API）、GitHub star（GitHub REST API），查询时间 2026-10-11。
- **本机 SDK 实测**：第七节所有涉及 `setDistributedTables` / `DistributedType` /
  命名 / 表结构的结论，均直接读本机 `E:\OpenHarmony\Sdk\26.0.0\ets\api` 声明文件
  与项目源码核对，非网上转述。
- **官方指南核实**：第七节的「约束限制」清单取自 openharmony/docs 仓库
  `zh-cn/application-dev/database/data-sync-of-rdb-store.md`（2026-10-11 取）。
  **这份指南才是约束的权威出处**——SDK 的 `.d.ts` 只列参数表和错误码表，
  不含任何约束说明；只读 d.ts 会漏掉全部硬限制（我第一版笔记就漏了 `progress`）。
  取法：`api.github.com/repos/openharmony/docs/contents/<path>` → base64。
- **第五节已精读源码**：本地副本 `_scratch/dyk/Digital-Yellow-River-main/`，
  26 个 .ets 全部可读，结论均附文件路径 + 行号。
- **未核实**：ArkUI-X 维护状态（官网不可访问）；iOS HIG haptic 数值（连接被重置）；
  第七节末尾三个多设备鸿蒙候选仓库（GitHub 超时）。
- **反模式警告**：GitHub 上 `nowinandroid` 与 `IceCubesApp` 都有极易写错的路径，
  见正文括注。
- **网络现状变更**：本机曾无法直连 github.com（见记忆 `github-access-cn-mirrors`），
  **2026-10-11 实测已恢复直连（HTTP 200），无需代理**。但 `raw.githubusercontent.com`
  **仍被阻断**——取文件内容要用 `api.github.com/repos/OWNER/REPO/contents/PATH`
  （返回 base64）或 `codeload.github.com` 下载 tarball。