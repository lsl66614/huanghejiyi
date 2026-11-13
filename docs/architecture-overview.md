# 黄河记忆 · 架构分析（2026-11-04）

> 场景：`system-modeler`（现状建模）＋ 证据核验。视图状态：**current state**，基于工作树（含 77 个已改文件 + 108 个未跟踪文件，非 master 提交态）。
> 图源：[docs/architecture-overview.mmd](architecture-overview.mmd)（Mermaid）。所有结论均标 `file:line` 或实测命令输出。

---

## 1. 一句话定性

一个**单 HAP、离线优先的 HarmonyOS 展陈应用**：语料全量预置在 rawfile，用户层数据走本地 RDB 并通过分布式 RDB 在两台设备间做 LWW 合并。真正的工程重心不在 App 代码，而在**自建的门禁与交付工具链**（tools/ 7,499 行 Python/Node/JS，13 道门禁）——这是本项目最独特、也最难被复刻的部分。

---

## 2. 规模实测

| 层 | 文件 | 行数 | 占比 |
|---|---|---|---|
| pages/（表现） | 20 | 12,036 | 60% |
| service/（领域） | 21 | 2,930 | 15% |
| common/（通用件） | 29 | 2,858 | 14% |
| repository/（仓储+传输） | 10 | 1,730 | 9% |
| model/（类型） | 3 | 204 | 1% |
| entryability/backup | 2 | 148 | — |
| **合计** | **85** | **19,906** | |

- 资产：rawfile **21.3 MB**，42 遗址 JSON / 104 文物 / 101 张 `real_` 实拍 / 7 条路线 / 2 款中文字体（ZCOOLXiaoWei 1.06 MB + NotoSerifSC-Head800 0.65 MB）。
- 产物：`entry-default-signed.hap` **23.47 MiB**（2026-11-04 实测；构成 rawfile 20.34 + modules.abc 2.07 + 符号表 0.80，脏条目 0）。
- 门禁：13 道，tools/ 7,499 行。
- 单测：Node 纯函数 **126/126 通过**（17 套）（`node --test`，实测 1065 ms）；设备侧 hypium 13 个用例（MergeEngine 8 / Recommend 5 / List 0）。
- 提交历史 133 commit，当前分支 `feat/slide-curtain` 领先 master **78 个 commit**。

---

## 3. 分层与依赖方向（核验结果）

设计文档 `设计方案.md` §3.1 声明六层自上而下。实际 import 关系核验：

**符合预期的部分（高置信）**
- `model/` 是纯类型叶子：0 处外部 import，只被上层引用。
- `pages → repository / service / common / model` 单向。
- `repository → model` 单向，`repository` 内部用 `IDataRepository` / `ITransport` 两个接口隔离实现。
- `service/` 主体确实是纯函数：`service/merge/*`、`service/content/*`、`service/recommend/*`、`service/notes/*`、`service/export/*`、`service/import/*` 共 19 个文件全部无 `@kit` import，文件头以「禁 @kit」自述；由 `tools/merge-tests/run.mjs` 转译成 `.ts` 在 Node 里跑测试（门禁 `tsbuild`）。

**实测到的三处偏离（不是 bug，是"纯函数"边界被有意突破）**
1. `service/sync/AutoSync.ets:14-23` 引 `@kit.NetworkKit` / `@kit.AbilityKit` / `@kit.PerformanceAnalysisKit` 和 `repository/UserDataRepo` + `repository/SoftBusRdbTransport`——网络监听与真机 transport 是有副作用的，不可能纯函数化。`service/sync/SyncScheduler.ets:10-11` 亦引 `IDataRepository` / `ITransport`。
2. `common/AppNavBar.ets:22`、`common/RelatedNotes.ets:14`、`common/SyncStatusBar.ets:7` 反向依赖 `service/`（3 处）。即 common 并非严格在最底层。
3. 因此"层次"实为**三块**：`common(设计语言) ← pages ← service/repository` 的混合，service 的"纯"是**按目录逐文件**保证的，不是分层保证的。

结论：README「service/ 纯函数」的表述应读作「service 下 19 个文件是纯函数，sync/ 下 2 个不是」。这是文档口径与实现口径之间最值得修正的一处。

---

## 4. 同步与合并（核心机制）

- **表**：`SYNC_TABLES = ['favorite','favorite_tag','note','note_tag','tag','progress']`（`model/SyncModels.ets:39`），恰 6 张，与 README 一致。`visit`、`reco_feedback` 刻意留在本机不进同步域（`LocalRdbImpl.ets:34-41` 注释说明）。
- **逻辑时钟**：`service/merge/LogicalClock.ets:20-25`，`now = wall > last ? wall : last + 1`，高水位持久化在 `sync_meta.lastWrite`（`LocalRdbImpl.ets:455-506`）。修掉"本机回拨 + 同毫秒连写"两类致因；**跨设备绝对时钟偏差仍按墙钟误裁决**，作者在文件头 14-16 行诚实写明这是已知限制。
- **合并**：`service/merge/MergeEngine.ets:12-50` 是纯函数 LWW。平局 `updateTime` 相等时按 `deviceId` 字典序裁决（`:36-38`），败方快照由 `appendConflictLog`（`:52-63`，带容量上限）落盘。
- **传输抽象**：`repository/ITransport.ets` 只有两个方法 `exchange` / `notifyAfterSync`；`LoopbackAdapter`（仿真，A/B 两个独立 RDBStore）与 `SoftBusRdbTransport`（真机，软总线 + `setDistributedTables` + `remoteQuery` + `pushToDevices`）都实现它，**裁决引擎是同一套**，演示口径与真机口径一致——这是应对"模拟器上跑不了分布式"质疑的架构答案（设计方案 R2）。
- **真机三步序**：`SoftBusRdbTransport.ets:53-70` 注释明确"先拉后推"，并承认这是「拉→合并→推」三步而非分布式事务，PUSH 与 remoteQuery 之间的窄窗口会覆盖对端新写。
- **冷启动闸门**：`service/sync/BootGate.ets` 把"模式恢复"与"首屏渲染"解耦——页面所有 DB 访问经 `UserDataRepo.get()` → `await whenBootGate()`（3 秒超时兜底），`EntryAbility.onWindowStageCreate` 先 `loadContent` 再后台 `AutoSync.prepare()`。这是一个设计得相当克制、注释里写清了两难取舍的冷启动方案。

---

## 5. 内容与资产管线

- `rawfile/sites/*.json` 42 个文件，字段 `id/name/city/era/site_type/summary/tags/sections/images/relics`；年代分布实测 `yangshao 10 / hantang 8 / xiashang 7 / song 6 / zhou 6 / longshan 5`（六年代）。
- 门禁 `validate` 做 schema + 图片引用存在性 + **反向差集**（`tools/validate_sites.py:107` 注释：rawfile/images 里没人引用的 webp 也会被打进 HAP，必须拦）——这一条直接对应"包体 40 MB 上限"的现实约束。
- `validate-src` 保证 `tools/sites-src` 母本与 rawfile 同 schema，`attribution` 保证每张在包实拍都有版权记录（实测许可分布 CC BY-SA 4.0×83 / CC0×17 / CC BY-SA 3.0×1），`poems` 保证 42 站每站 ≥1 首且三要素齐全（实测 42/42，bad 0）。
- `real_` 前缀是渲染层硬约定（`common/ImagePolicy.ets:4-5`），缺图走材质线稿，不以生成图冒充实物影像——与设计方案的 R5 一致。

---

## 6. 工具链与交付（项目最独特的部分）

`tools/run_gates.py` 的 13 道门禁顺序即依赖顺序：内容校验 → 署名 → 诗词 → 对比度 → 令牌 → 跨页间距 → 字号 → 无障碍 → 动效 → 字体 → tsbuild → 单测。`app/build-oh.bat` 在 `assembleHap` **之前**调用它，任一非 0 直接阻断出包（`SKIP_GATES=1` 可绕过，但注释明写"never for a release artifact"）。

交付三件套全部脚本化、不手工编辑：设计方案 docx（事实源 `设计方案.md`，提交版差异集中在 `make_submission_docx.py` 的 `REPL`/`DROP_BLOCKS`）、12 页路演 PPT（`make_roadshow_deck.cjs` + `pptx_ea_font.py` 补东亚字体槽）、交付包（`make_submission_pkg.py` 负责排除脏物/凭证、路径中性化、包内自检断言）。

---

## 7. 风险与健康度

### 7.1 实测红灯：门禁当前 **10/13 通过**（`python tools/run_gates.py`，exit 1）

| 门禁 | 失败项 |
|---|---|
| `tokens` | `common/IconButton.ets:27` fontSize 16（应归 18）；`pages/ArchivePage.ets:290` borderRadius 999；`:308` 间距 18；`:334` 间距 20 |
| `visual` | `ArchivePage.ets` L308 间距 18→16、L334 间距 20→24，两处新增漂移 |
| `aging` | `common/IconButton.ets:27` 字号 16 档外（490 处档内 / 1 处档外） |

三道红都指向同一片正在施工的区域：**`ArchivePage.ets` 与新建的公共件（`IconButton`/`SectionTitle`/`SegmentTab`/`StatStrip`/`StratumCrumb` 等 8 个 untracked 文件）**。这些文件尚未进 git，因此 `docs/修复计划.md` §7.1 记录的"13/13 全绿"基线已经过期。按当前工作树直接出包会被门禁挡住。

### 7.2 工作树状态（提交纪律风险，中高）

- **77 个已修改文件 + 108 个未跟踪文件**（本次分析前实测；含本文档与图源则为 110），全部未提交。已跟踪内容包括 30+ 页面、门禁脚本、rawfile JSON、`设计方案.md`、提交稿 docx。
- `design/verify/` 下 **50+ 张装机截图**未跟踪。
- 关键新模块 `service/import/`（导入裁决）、`ArchivePage.ets`、8 个公共件全部处于未跟踪状态——**一次误 checkout 就会丢失**。
- 同目录还有 12 个 `tools/_*.py` 一次性脚本未跟踪，其中 `tools/_migrate_colors.py` 已被跟踪，属历史残留。

### 7.3 已知且未修的缺陷（`docs/修复计划.md` §7.3–7.8 自己登记的，装机实证）

- **B1 分段计数恒 0**：首页「遗址 0」（实际 42 已加载）、档案「收藏 0」（下方渲染 3 条）——`SegmentItem.count` 在异步装载后未重建数组。**这是数据可见性级别的错，用户一眼能看见。**
- **B2 年代打架**：首页「继续研读·巩义窑址」标"宋·郑州"，同页「今日一物」标"汉唐"，而 `巩义窑址 era=hantang`——年代源取错。
- **C2 `StratumCrumb` 零调用点**：面包屑公共件建好了但一件没套，阶段 2 判据不成立。
- **C1/C3/C4**：ACCENT 短杠违规 ×3（"短杠=层色或 INK，禁 ACCENT"）、收藏视图切换未走 SegmentTab、「最近删除」双呈现。
- **G1 字体子集缺字**：`ExportPage` 标题「把带走的档案放□来」豆腐块——ZCOOLXiaoWei 子集未覆盖该字形，且属回归。
- **G3 工程语言外露**：`RecommendPage` 直接把评分公式（同年代 0.4 · 同类型 0.3）与裸分数 0.75 上屏。
- 另有 §7.6/7.7 登记的**三层页头叠加**病族（`showNav` 只关底栏不关页头）——已在 `ArchivePage`/`RelicListPage` 落处方但未见修复证据。

### 7.4 架构层面的中低风险项

| 项 | 证据 | 判断 |
|---|---|---|
| 页面层体量 | `DetailPage.ets` 1292 行、`RelicPage.ets` 1148 行、`FavoritesPage.ets` 827 行 | 页面承担了业务逻辑，跨页复用只能靠 `@Builder` body 结构（`FavoritesBody`/`NoteCenterBody` 被 `ArchivePage` 内嵌） |
| 路由注册与实现不一致 | `main_pages.json` 18 条；`FavoritesPage`/`NoteCenterPage` 不在注册表，但被 `ArchivePage` 当组件内嵌 | 有意设计，但"页面"与"组件"同文件，后续容易误用 |
| 口径漂移 | ✅ 已修 2026-11-04：提交清单/路演稿/设计方案里的「103 单测 / 19.28 MiB」已对齐到实测的 126 / 23.47 |
| 分布式竞态 | 「拉→合并→推」窄窗口覆盖对端新写 | 作者已诚实标注为已知限制，应用层难根治 |
| 跨设备时钟偏差 | 两台真机墙钟绝对偏差仍影响裁决 | 依赖系统 NTP 兜底，已在 README 与代码注释双处声明 |
| 夜间模式 | 主动裁剪，理由充分（ArkUI `export const` 是构建期值，真做需逐页 `@StorageProp` + 第二套对比度矩阵） | 合理取舍 |
| 签名材料 | `app/build-profile.json5` 硬编码绝对路径 + 明文口令；`sign/` 未被 git 跟踪（历史也从未跟踪过） | 口令是 debug 签名口令，但路径绑定本机、换机即废 |

---

## 8. 未核验项（诚实边界）

- 未执行 `build-oh.bat` / hvigor 构建（本次只跑了门禁与 Node 单测）；HAP 大小取自 2026-11-04 21:54 的既有产物，未重新构建。
- 未做真机 / 模拟器装机验证，B1/B2/C1 等缺陷均引用 `docs/修复计划.md` 的装机记录，未复现。
- 未验证 `tools/make_submission_pkg.py` 的实际出包与自检结果（需要 WinRAR 与本机 DevEco 路径）。
- `dotnet`/hvigor 链路的可复现性未在本次会话验证。

---

## 9. 建议的下一步（按投入产出排序）

1. **先让门禁回绿**：修 `ArchivePage.ets` 的 4 处裸值 + `IconButton.ets:27` 字号 → 13/13。当前状态出不了包。
2. **修 B1（计数恒 0）与 B2（年代源错）**：用户可见的两处硬错，改动小、收益最高。
3. **提交工作树**：108 个未跟踪文件里有 8 个公共件、`service/import/`、`ArchivePage.ets` 等新模块，是当前最贵的一笔未落盘资产。
4. ~~**重跑交付生成链路**~~ ✅ 已做 2026-11-04：单测口径 126、HAP 23.47 MiB、实拍 101 张（42 遗址 + 104 文物全有实拍）已同步到设计方案与交付脚本。
5. 清理：`tools/_*.py` 一次性脚本归入 `_archive/` 或删；`design/verify/` 截图加 `.gitignore` 或单独归档。
