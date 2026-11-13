# 开发踩坑清单

> **使用纪律**：① 每个子任务开工前通读本清单全文；② 编码过程中逐条自查（尤其第 1~7、11、13 条属 ArkUI/ArkTS 声明式约束，最容易反复踩）；
> ③ 提交前再对照一次；④ **踩到新坑立即补条目**，禁止只改代码不改清单。
>
> 本清单只收录**本项目实际踩过或已验证**的坑。每条都带现象、原因与规则，不写"应该注意"这类空话。

## 一、ArkTS 语言层

1. **禁 `any`，且隐式 any 同样报错**：`arkts-no-any-unknown` lint 规则会在编译期拦下 `for (const x of obj['key'])` 这类写法——`obj['key']` 的类型是 `Object`，直接进 for-of 就成了 any。规则：**从 `Object` 取值后必须显式断言**为具体类型，如 `for (const f of figs as string[])`。

2. **`for...of` 可用但要保证元素类型已知**：对数组下标遍历（`for (let i = 0; i < arr.length; i++)`）完全无限制，功能相同时优先下标循环，避开类型推断的不确定性。

3. **类字段必须初始化或显式声明类型**：`class SiteEvent { year: string = ''; }`，不能只写 `year: string;`。新增 model 类时每个字段都给默认值，否则对象构造即报错。

4. **解构赋值禁用**：`const { a, b } = obj` 不允许，必须逐字段 `obj.a` / `obj.b`。

5. **`@State` 数组/对象修改必须整体赋值**：`this.list = [...]`、`this.obj = {...}`。只用 `push` 或 `obj.x = v` 不触发刷新。异步回填 PixelMap 数组时尤其注意——先 `slice()` 再改再整体赋值（见 `common/ImageViewer.ets` 的 `decodeAll`）。

## 二、ArkUI 声明式约束

6. **`build()` 根节点前不允许写任何语句**：连 `const x = this.filterList()` 这类局部变量声明都会被编译器当作额外根节点，报 "only one root node" + Rollup Unexpected token。派生数据改为在 UI 描述里直接调方法（`Text(this.filterList().length)`）或放进 `@Builder` 参数。

7. **`@Builder` 默认「按值传递」**，参数在首次渲染时被拷贝，之后状态变化**不会**触发其内部 UI 刷新。症状是"外层列表已按新状态更新，@Builder 里的高亮却停在初始值"。规则：需要跟随状态刷新的局部 UI 拆成独立 `@Component` 子组件用 `@Prop`/`@Link` 绑定；`ForEach` 项内部若依赖外部状态，把该状态纳入 key 生成函数确保节点重建。

8. **`layoutWeight` 只在主轴方向有明确约束时可用**：父容器未限定高度时，Column 内 `Line().layoutWeight(1)` 会被分配"无限剩余空间"而无限拉伸，连带外层 Row 一起被撑高。要做分隔线用 `Divider` 或固定高度，别用无约束容器里的 `layoutWeight`。

9. **`router` 目标页必须注册进 `resources/base/profile/main_pages.json`**，否则运行时路由找不到。传参 `router.pushUrl({ url, params })`，目标页 `router.getParams() as Record<string, string> | undefined` 取（返回 `Object`，需显式断言，禁 any）。

10. **`ForEach` 的 key 生成函数必须稳定唯一**：用业务 id 而不是数组下标，除非项本身确实可按下标定位。下标在列表重排时会错配节点。

## 三、数据文件（rawfile JSON）

11. **正文内嵌引号必须用中文「」，绝对不能用 ASCII `"`**：字符串在 ASCII 引号处提前闭合，`json.load` / `JSON.parse` 直接抛 "Expecting ',' delimiter"。2026-10-09 内容深度升级时实测：`hanwei_luoyangcheng_taiji.json` 与 `yanshi.json` 两个文件因此报废，需 `tools/fix_depth_json.py` 修复。

12. **同名键在 JSON 根层重复会被静默吞掉**：`json.load` 保留最后一个，**不报错**。2026-10-09 在 `duling_fangding.json` 实测：根层有一个多余的 `arch` 键，白丢约 111 字已考证内容，且全程无何告警规则：合并/改写站点 JSON 后必须 `json.load` 回来检查字段数量与字数，不能只看"解析成功"。

13. **逐条容错在解析层，整表失败判定在加载层**：`parseHeritageList` 遇到单条非法跳过该条是对的，但加载入口必须把"整表 0 条"转为抛异常，否则"加载失败"被静默成"空数据"，上游 catch 不到，兜底逻辑永不触发。空结果**不入缓存**。

14. **字段缺失兜底用空串/空数组，不做默认值幻觉**：`getStr` 找不到返回 `''` 而不是猜一个值。猜出来的默认值会一路流到 UI，评审看到的是编造内容。

15. **枚举值在 parse 时做合法值校验**，非法条目跳过并记日志，保证其余数据可用。非法枚举不应产生假相似度/假匹配。

## 四、SDK 与构建

16. **凭记忆写 SDK API 会直接编译失败**：网上旧版 OpenHarmony 文档与当前 SDK 已有漂移。规则：**用不熟悉的 kit 前先查本机 d.ts**，路径 `E:\ .stepclaw\DevEco Studio\sdk\default\openharmony\ets\component\*.d.ts`，grep 方法名/接口名即可。

17. **命令行构建三件套**：`DEVECO_SDK_HOME` + `NODE_HOME`，并且**必须把 `E:\ .stepclaw\DevEco Studio\tools\node` 放进 PATH**。仅设 `JAVA_HOME` 不生效，会报 `spawn java ENOENT`——此时 ArkTS 已编译通过但 PackageHap 失败，容易误判为代码问题。本项目统一走 `app/build-oh.bat`，不要手拼命令行。

18. **API 签名要连选项字段一起查**：`bindContentCover` 的 `ContentCoverOptions` 只接受 `backgroundColor` / `onAppear` / `onDisappear` / `onWillAppear` / `onWillDisappear`（继承自 `BindOptions`）加 `modalTransition` / `onWillDismiss`。**没有 `modal` 字段**——凭印象写 `modal: true` 会报 "No overload matches this call"，而且错误信息不指向具体字段，只能回 d.ts 查。2026-10-09 接 ImageViewer 时实测。

19. **ArkUI 组件名突**：项目里已有 `common/SilhouettePlate.ets`，新增图集组件时不要再叫 `ImageGallery.ets` 之类与竞品同名但语义不同的文件，避免后续 merge 混淆。

19b. **SDK 的 `.d.ts` 里没有「约束限制」，硬限制全在官方指南里**：`setDistributedTables` 的声明只列了参数表和四个错误码（401 / 801 / 14800000 / 14800014），**一句「什么表不能设分布式表」都没有**。真正的约束清单在 openharmony/docs 的 `zh-cn/application-dev/database/data-sync-of-rdb-store.md`「约束限制」章节：单应用最多 16 个分布式 RDB 库、单库最多 8 个变化订阅回调、**不支持将含有复合键的表设置为分布式表**、一张表不能同时端端+端云且不可切换、同库必须同存储机制。规则：**查 API 的「能不能用」要去指南，不能只看 d.ts 的「怎么调用」**——本项目 `SYNC_TABLES` 里三张复合键表（`note_tag`、`favorite_tag`、**`progress`**）就是这么漏过去的，只读 d.ts 永远发现不了。取文档：`api.github.com/repos/openharmony/docs/contents/<path>` 拿 base64（`raw.githubusercontent.com` 本机不通）。

19c. **「复合键表」判据是复合主键，不是「有没有主键」**：第一版笔记把 `note_tag`（`note_id, tag_id, updateTime`）描述成「无主键的复合键表」，据此只挑出 `note_tag` / `favorite_tag` 两张违规，**漏了 `progress`**——它的 DDL 是 `PRIMARY KEY(target_key, section)`，同样是复合主键，一样不能设分布式表。规则：**拿到「某类表不能用」的规则后，回到自己的 DDL 逐张对主键定义，别凭表的用途或印象筛**。

19d. **`pragma_table_info(?)` 传绑定参数返回零行且不报错**（2026-10-11 真机踩到，用它做 schema 迁移判据时迁移被静默跳过）：`await st.querySql('SELECT name FROM pragma_table_info(?)', [table])` 不抛异常，`goToNextRow()` 直接 false，看起来像「表不存在」，实际是表存在。设备 sqlite3 CLI 上可复现对照：`sqlite3 db "SELECT name FROM pragma_table_info('t')"` 有结果、换成 `?` 形式即 `no such column`。**正解：把表名内联进 SQL 字符串**——表名若只来自自家 DDL 常量，无注入面；若来自外部输入，必须先过标识符白名单。另外顺带：**重建表时要把列类型一起带上**（`pragma_table_info` 的第二列 `type`），只搬列名会造出 NONE 亲和性的新表，与原 DDL 声明的 TEXT/INTEGER 不一致。

19e. **就地迁移的临时表必须先 `DROP TABLE IF EXISTS`，且迁移失败不能只记日志**：SQLite 改不了主键，只能「建 `xxx__new` → INSERT...SELECT → DROP 旧 → RENAME」。这套模板里 `CREATE TABLE xxx__new` 若没带 `IF NOT EXISTS`，**一旦某轮在后续步骤失败，`__new` 就留在库里，之后每次启动都在 CREATE 这步撞「table already exists」而永久失败**——因为 catch 只 `rollBack()`，临时表不随事务回滚消失（旧表也不丢，但迁移永远做不成）。本项目首版就是这么坏的：真机 hilog 每启一次打两遍 `migrate xxx skipped`，`sqlite_master` 里躺着 `favorite_tag__new` / `note_tag__new` 两个残骸。规则：**迁移模板三步走——先 DROP 临时表、再 CREATE、再搬；判据函数查到「已迁过」就直接跳过；catch 里把该表标记为不可注册，别让上层照抄常量列表**。

19f. **`impl` 只在 await 之后赋值的单例，就是并发漏洞**：首页与「我的」页都会并发调 `UserDataRepo.get()`，而原写法是 `if (impl !== null) return impl; const rdb = new Impl(); await rdb.init(); impl = rdb;`——**`await` 期间 `impl` 仍是 null，第二个调用者会再造一个实例**，两个实例对同一批表并发跑建表/迁移。实测后果不是报错而是**静默丢数据**：一个实例 `DROP TABLE progress` 的同时另一个刚把数据搬完，4 行学习进度全没了，hilog 里表现为 `db ready` 打了两遍。规则：**单例初始化要用共享 Promise 兜住并发**（`pending = create(); return await pending`，finally 清空），或者在 await 前就置占位。判据很便宜：**日志里同一条初始化消息出现两次，就是并发调了**。

19g. **合并落库只能 upsert 终态，不能按「终态里没有的 key」删行**：`SyncRecord` 的删除语义由 `isDeleted` 墓碑表达，不是「行不存在」。`mergeElementSets` 的输出是 local ∪ remote，快照时已经存在的每个 key 必然出现在终态里；终态里缺失的 key 只可能是**快照拍完之后、落库之前**的新写入。`applyMerged` 原先用同一个复用谓词边遍历结果集边删行：先删掉结果集当前行导致后续遍历错位，再把「同步期间的新写入」静默删掉。谓词复用只是表象，**删除循环本身就不该存在**。规则：合并落库只 `INSERT OR REPLACE` 终态，删除交给墓碑列；确需差集时先把结果集读进数组、`close()` 后再用新谓词操作。

## 五、工程与数据一致性

20. **`IDataRepository` 的方法必须核对调用点**：2026-10-09 发现 `upsertTag` 全项目**零调用点**——用户自建的标签只存在于页面内存数组，重启即失。这类"接口已定义但无人调用"的断链不会被编译器和测试发现。规则：**新增 repository 方法时，同步 grep 全项目调用点；发现零调用要么接上要么删掉**。

21. **同一份数据的双份实现必须共用唯一解析入口**：如 rawfile 正式数据与预览器 mock 数据都走同一个 `parseXxxList`，结构漂移会在解析结果里立刻暴露，不会出现"预览器能跑、真机不对"。

22. **测试里的 `readdirSync` 必须过滤扩展名**：2026-10-09 实测 `tools/merge-tests/content_parse.test.mjs` 未过滤 `.json`，把 `images/` 子目录当文件读，抛 `EISDIR`。这是**先于本次改动就存在的 bug**，写测试时目录遍历一律 `filter(f => f.endsWith('.json'))`。

23. **文档改完要回读校验**：编辑状态表、清单类文档后立刻 Read 回来确认内容没被并发编辑覆盖。竞品项目历史上出过文档条目被覆盖丢失、导致"代码已注册路由但清单没记录"的事故。

## 六、内容纪律（与代码同等重要）

24. **不确定的内容留空，不编造**：开放时间、票价、发掘队负责人姓名等无法核实的字段一律留空字符串或空数组。UI 侧对每个字段都有空值守卫（`if (e.background !== '')`），留空即隐藏，不会渲染空白行——这是设计如此，不是缺内容。

25. **改写正文时保留原句**：2026-10-09 内容升级中，各批次 agent 采用"原句整体前置保留 + 续写扩写"的方式，构建脚本用 `assert 原文本 in 新文本` 强制校，从机制上杜绝扩写时无意改写既有事实。规则：**扩写类脚本必须内建原文包含断言**。

26. **源文件里的事实冲突不要静默选一个**：如郑州商城发现年份，原 `summary`/`intro` 写 1955 而通行记载为 1953。正确做法是把两种说法都写进正文并说明分歧，而不是挑一个删掉另一个——被评委追问时能答得上来。

## 七、对比度与可读性（本项目最大的隐性缺陷面）

27. **半透明文字必须按"合成后"的颜色算对比度，不是按前景色**：`eraInkA(era, '59')` 这类写法，肉眼看的是 ink 叠在年代底色上的结果。2026-10-09 实测最差的组合只有 **1.67:1**（周底 `#6F8288` 上叠 35% 的 `#1F1B16`）——前景 ink 单独看是 4.26:1，叠上去直接掉到三分之一。**只检查前景色与背景色的对比度会漏掉全部这类缺陷**。规则：任何 `alpha` 形式的文字，校验脚本里一律先 `composite(fg, bg, a)` 再算比值。

28. **token 函数里做钳制，把可读性做成不变量**：不要指望每个调用点都记得传对 alpha。`eraInkA()` 内部按 `ERA_INK_FLOORS` 把 alpha 抬到该年代的达标下限（各年代不同：龙山 `90` 即可，夏商需要 `F0`），调用方想传多低都拦得住。**层级弱化靠字号和字重做，不要靠把文字调透明**。

29. **中间调背景配黑字配白字都会不达标**：黄河题材的年代色（汉唐 `#B98A44`、宋 `#7F97A4`）作底色时配 `#1F1B16` 有 5.5:1 没问题，**反过来当字色压在纸底上只有 2.7:1**。同一色值在不同角色下的达标线完全不同。规则：色板要区分"底色 token"和"文字色 token"，本项目即 `ERA_COLORS` 与 `ERA_TEXT` 两套，文字变体只压明度、不改色相。

30. **对比度校验必须落成脚本，不能靠目视**：`tools/check_contrast.py` 把 WCAG 2.2 相对亮度公式做成 33 项门禁（文字层级 × 4 种底色、6 年代底 + ink、5 个半透明 ink 位点、6 个年代文字色，外加"已淘汰令牌不得残留"的源码扫描）。**改 `EraTheme.ets` 后必跑**，退出码非 0 即阻断。阈值按工信部《移动互联网应用(APP)适老化通用设计规范》与 WCAG 2.2 AA 取 4.5:1。

31. **不要对计算出的比值取整**：WCAG 明确规定 4.499:1 不满足 4.5:1。脚本里保留两位小数仅用于**显示**，判定一律用浮点原值。

32. **审计脚本自身要先验证再下结论**：2026-10-09 我用脚本扫出"7 处点击热区不足 44vp，底部导航图标 19vp"，随后回 SDK 核实 `responseRegion` 默认取组件整体、并手工量了底部导航实际是 70vp+ 高——**脚本只截取了 `.onClick` 前 700 字符内最后一个 `.height()`，漏掉了外层 Row 的 padding**。结论作废。规则：**自动审计给出的每一条负面结论，都要人工复核一次再写进报告**，尤其是靠正则截取上下文得出的尺寸类结论。

## 八、交互与命中测试（Stack 图层必踩）

33. **Stack 里被上层组件盖住的 `onClick` 点不到，命中测试自上而下且默认兄弟节点被挡**：`DetailPage` 头图是 `Stack` 叠 4 层——底层 `Image`（挂 `onClick`→拉灯箱）、两个 100%×100% 渐变 `Row`（纯装饰无 handler）、最上层 info `Column`（默认命中模式，`width('100%')`）。`HitTestMode.Default` 的语义是"节点自身与子节点响应命中，但**阻塞兄弟节点**"，所以最顶层 Column 把整块头图都挡死，底层 Image 的 onClick 永远收不到点击——2026-10-10 模拟器实测：点照片区 5 个坐标全部落空。`HitTestMode.None`（自身不响应且不挡兄弟）加在 Column 上**也没救活**（该模式对"自身无 handler 的空档区"透传行为与预期不符）。**正解：把 onClick 从底层 Image 挪到最外层 Stack 上**——带 handler 的返回/笔记/收藏按钮在更深层优先消费事件，照片/渐变空档沿冒泡链到达 Stack 的 onClick。规则：**Stack 里需要"点背景"交互时，handler 一律挂最外层容器，不要挂在被盖住的子层**。

34. **`uitest uiInput tap` 是非法子命令**：`hdc shell uitest uiInput tap x y` 报 `Invalid parameters`，正确写法是 `uitest uiInput click x y`。用错时**表面上无报错**（swipe/截图正常），导致"点了没反应"被误判成 UI 缺陷。返回键用 `uitest uiInput keyEvent 2`（2=系统 BACK）。相关操作脚本在 `_scratch/uia.sh`、`_scratch/uitap.py`、`_scratch/forensic.py`。

35. **`stateStyles({ pressed })` 能编译、能过门禁，但真机抓不到按下态**：2026-10-09 在模拟器（127.0.0.1:5555）上逐像素实测（工具 `tools/press_probe.py`），56 处按压反馈**按住时零像素变化**。已排除的全部其他解释——不是注入问题（`uinput -T -d x y -i 15000` 日志打印 touch down，同坐标用 `-c` 点击确实跳页）；不是探针抓不到（对照组：年代卡手写 `onTouch` 实现同样按法变化 42.5%，而「什么都不按纯等 3 秒」变化 0%）；不是 UI 语法丢标识符（换字面量 `opacity: 0.3` 仍为 0）；不是没进产物（`modules.abc` 里 `pressed` 键存在）；不是输入通道（鼠标 `uinput -M` 同样为 0）。连 pressed 里写死 `backgroundColor:'#FF0000'` 都无变化。**规则：按压反馈在本项目唯一被证实有效的写法是 `@State` + `.onTouch(Down/Up/Cancel)` + `.opacity()/.scale()` + `.animation()`（见 `Index.ets` 年代卡）；`lint_motion` 规则 3 只能证明「挂了声明」，不能当有效性证据。**

36. **`stateStyles` 与 `.animation()` 同链直接编译失败**：报 `10905203 "'.stateStyles' doesn't conform standard"`，**与书写顺序无关**（写在 `.animation()` 前后都失败）。不是运行期抖动，是编译期就拦。`Index.ets` 年代卡那条链两者都有，所以它挂不了 `stateStyles`。

37. **`stateStyles` 的参数是 UI 语法，必须逐字内联字面量**：函数调用、跨模块 `const`、同文件 `const` 三种写法实测全报 10905203；`@Styles` 也不行（产出 `<T>() => T`，类型与 `StateStyles` 不匹配）。这也是 56 处各写一遍带来漂移风险的原因，`lint_motion` 规则 6 逐处比对 `PRESS_SCALE`/`PRESS_OPACITY` 两个令牌。

38. **JUnit/构建类 OOM 是资源问题不是代码问题**：`Failed to allocate initial concurrent mark overflow mark stack` 出现在 `PackageHap` 步骤。机器总内存 15.8GB、空闲仅 4.91GB 时触发。**重跑一次通常就过**（本项目 2026-10-09 实测第一次失败、第二次 5.6s 成功），不要误判为代码错误回头改源码。

39. **@Builder 组件调用后不能再续 `.layoutWeight()` 等修饰符**：ArkTS 里 `this.statCell(...)` 展开成 void 表达式，其后直接接 `.layoutWeight(1)` 报 `Property 'layoutWeight' does not exist on type 'void'`。正解是把 `.layoutWeight(1)` 写进 @Builder 内部根组件（本项 statCell 的 Column）上，调用点就写 `this.statCell(a,b)` 裸调。2026-10-12 首屏数据带首踩，改完即编过。

40. **间距「非档值」要冻结成基线，而不是逼着一次性清零**：`lint_tokens` 的 `spacing` 规则是逐处卡死数值，但间距迁移要翻 9 页、每页装机回归，一次做完风险高。`lint_visual_consistency.py` 的分工：`EXEMPT` 表把存量 100 条（文件,行号,值）三元组冻成基线，表内漂移不算违规（只提示过期条目待删）；**表外新写的非档间距立即 FAIL**。旧账分批还（`--plan` 给吸附建议、`--emit-exempt` 重建基线），新账不让进；全清后再开 `lint_tokens` 的 `spacing` 规则收口。

## 九、外部资源抓取（Commons 实拍图，2026-10-20/21 实测）

41. **Commons 缩略图 URL 不能自己拼**：真实路径是 `/thumb/<md5[0]>/<md5[0:2]>/<文件名>/<宽>px-<文件名>`，但这套 MD5 目录规则对带空格的 Unicode 文件名推不出来（实测 404）。正解是问 API 要 `thumburl`：`api.php?action=query&prop=imageinfo&iiprop=url&iiurlwidth=1024&titles=File:<名>`。

42. **整文件下载会卡死，必须分段 Range**：同一台机器上，Commons 根路径 HEAD 只要 1 秒，但拉整文件 40 秒超时——卡的是长连接被中间链路掐断，不是不可达。规则：先 HEAD 拿 `Content-Length`，再按 256KB 一段 `Range` 请求后拼接。

43. **同进程连拉会累积 TLS 状态**：第 2~3 张必现一次 `handshake operation timed out`，整批中断。规则：**每张图一个子进程**，单张失败只丢一张，不拖累后续。

44. **被限流时 Commons 返回 200 + HTML 错误页**：不校验就会把 HTML 当 JPEG 存进 rawfile，PIL 打开时才炸且报错误导。规则：**下载后校验前 3 字节是不是 `FF D8 FF`**，不是就判失败重试。429 错误信息里直接写明「用标准缩略图尺寸」——把宽度收敛到 1024/1280 这类标准档，别用 on-demand 尺寸。

45. **转码用 PIL 而不是 ffmpeg**：分段下载偶尔得到不完整 JPEG，ffmpeg 会直接失败退出（exit 69）；PIL 能容忍并输出可用结果。配套规则：**判重不能只看文件存在**，转码失败会留下 0 字节 webp，必须用 `PIL.verify()` 验一次再当"已完成"。

## 十、待补条目

- ~~多图 Lightbox 在模拟器上的实际渲染效果尚未截图验证~~ → 2026-10-10 已验证：点开（文物细观/关闭✕/◀▶ 均在）、翻页图区均值变化、关闭回到 Detail 均正常；头图入口靠 #33 的 Stack onClick 修复后打通。
- `sync(PUSH)` 真机双设备组网下的冲突台账表现尚未实测，当前只有模拟器单端。
- 提亮后的周底色 `#75888F` 与宋底 `#7F97A4` 色相接近（同为灰蓝），只靠色相区分两期，六期缩略图并排时可能混淆——尚未在真机做过色觉障碍模拟检查。
- 半透明 ink 钳制后，`示意图` 角标等弱化文字的视觉层级是否还成立（钳制把它压得更实了），尚未截图复核观感。

## 十一、列表刷新与模拟器点击（2026-10-25 实测）

46. **子组件的普通成员不会随父状态更新**：`DepthRuler` 的 `segs` 原本是裸成员，详情页勾选「已研读」后父页 `readKeys` 已变、标签文案也变了，但导览尺五格仍是发丝灰（像素采样 232,229,220 全程不动）。规则：父状态驱动的入参一律 `@Prop`；同时 `ForEach` 的 key 要把会变的值带上（`${seg.key}|${done}`），否则键不变、条目沿用旧节点。改完同一操作下第二格立刻变赭红（142,63,30）。

47. **分组列表的 key 只写组名会把旧成员冻住**：收藏页按标签分组时 `ForEach(..., g => g.tag)`，给条目补标签后 `未分类` 组的 key 不变，界面继续显示"3 项"且里面还留着已打标签的条目（数据层已是 2 项）。key 要含成员集合：``(g) => `${g.tag}|${g.entries.map(e => e.key).join(',')}` ``；条目级 key 也要带 `tags`，否则标签 chips 不刷新。同理：已选某标签筛出的视图只建该标签一组，别按条目的其它标签再分组（"1/3 条"却列出两组）。

48. **`uinput -T -d x y` 只按下、不抬起**，界面不产生点击（命令回显"touch down"却毫无反应）。点击用 `uinput -T -c x y`；拖拽/滑动用 `uinput -T -g x1 y1 x2 y2 <press> <total>`，且 `press ≥ 500ms`、`total - press ≥ 500ms`，否则被判为无效手势直接丢弃。滑到页顶后再点 `‹ 返回`：详情页头栏在 Scroll 内，滚动后按钮不在屏上。

49. **固定高度的 `Stack` 不裁剪子组件**：`AccessionPlate` 在 120 档仍会往下画材质/编号/状态三行，列高 192vp；父级 `Stack` 写死 120×120 且没有 `.clip(true)`，三行就压到卡片标题上（截图里标题像"叠字"）。规则：**组件的总高不能只看主图形尺寸**——入参只是图幅，文字行另算；要么父级按真实总高留位（本处 120+8+16=144），要么在组件内按尺寸门槛只画能放下的层级，并把"图幅 ≠ 总高"写进组件注释。

50. **横向 `Scroll` 的内容窄于视口时默认居中**：收藏页 chips 行宽 892、视口 1320，整排左右各留 214，与页面 `PAGE_PAD_X=60` 对不齐；点选项加粗使宽度变化时，整排还会跟着横移（实测左缘 154→144）。规则：横向 `Scroll` 显式 `.align(Alignment.Start)`，让左缘钉在 padding 上。另：若外层容器已经给了 `PAGE_PAD_X`，内层 `Row` 不要再补左边距——详情页文物横滚两处都加了 24，第一张卡比「代表文物」标题右移一个 pad，且三张卡被挤出屏外。

51. **`Blank().layoutWeight(1)` 会把内容 `Scroll` 挤成零高**：文物页原本是 `Column` 里「标题/图/事实/tabs」+ `Blank().layoutWeight(1)` + 「tab 内容 Scroll().layoutWeight(1)」+ 钉底按钮。`Blank` 先吃满剩余高度，tab 内容拿到 0，屏幕上只剩 tabs 和笔记按钮——看起来像「tab 坏了」。规则：有固定头尾的页面，`layoutWeight` 只给**一个**滚动容器；把从标题到 tab 内容全部包进同一个 `Scroll`，钉底按钮放它外面，不要再放弹性 `Blank`。

52. **实拍文物页不能沿用占位图的「浮动小图」版式**：210vp 藏品签放进 340vp 深色框，实拍时四周全是空黑，像把展品悬在半空。规则：有 `real_` 图时 `Image` 用 `width('100%') × MEDIA_H(340) + ImageFit.Cover` 满幅铺，占位时才回藏品签；两者共用一个高度常量，用 `firstRealImage()` 判空切换。另：文物页标题下的「文化 · 遗址」与下方 Facts 三列完全重复，删掉后信息量不减。

53. **文物卡上「点图」和「点标题」是两个动作**：详情页实拍文物卡的图区 `onClick` 打开「文物细观」Lightbox（子节点事件不冒泡到卡片的跳转），点卡片下半部的名称/材质才进文物页。验收时想进 RelicPage 要点文字区；点图后按返回键可关 Lightbox（`关闭 ✕` 与系统返回都可用）。

54. **跨筛选的「全库计数」放在局部筛选页上一定对不上**：列表页材质入口原用全库索引，宋层展开后仍写「未记 1」，点进去却一件都没有（那件未记文物不在宋层）。规则：入口计数用**当前筛选后的集合**重建（`buildMaterialIndex(filteredSites)`），表头按范围写「当前 N 件 / 全库 N 件」；0 件的桶不渲染、也不可点，免得点出一页空结果。注意计数要用「材质过滤之前」的集合，否则选中某材质后其余桶全归零。

55. **瞬时进度状态不能当持久事实显示**：同步面板的 `progress` 只活在本次同步过程中，重进页面后是 0，而 `lastSyncTime` 已落库，于是「同步进度 0% + 最后同步 12:45 + 冲突记录 1」自相矛盾。规则：读持久时间戳时同步回填——`lastSyncTime > 0` 且当前不在同步中，进度按已完成显示 100%；只有真正开跑时才从 0 起涨。

56. **切了档案再返回，「我的」页统计会停在旧档案——而且就算重读了也还是 0**：同步面板进场会把当前库切到仿真身份（`setSimMode(true)`），但 MinePage 只在 `aboutToAppear` 读一次收藏/笔记/最后同步；更隐蔽的是它的 `stat` 用 `@Builder` 接参，本 SDK 按值拷贝，异步读回的数字不会触发重绘（日志已读到 fav=3，屏上仍是 0）。规则：① 跨页会改当前库的页面，统计读取放 `onPageShow` 重算；② 会变的指标必须做成独立 `@Component` + `@Prop`（同 SyncPage 的 `MetricCell`），不要用 `@Builder(label, value)`。修后从同步面板返回，「我的」由 3/0/— 变成仿真档案的 0/1/12:45。

57. **`real_` 前缀只是「可显示」，不代表「挂对了」**：UI 的判定只有 `ImagePolicy.isRealImage()`，文件名以 `real_` 开头就直接当该遗址/文物的实拍。因此把同址器物图挂到别的文物、或把器物图排在遗址 `images` 首位，界面会毫无提示地显示错图（实测：二里头铜牌饰展示的是大河村出土的刻槽盆，北宋皇陵头图是陵前石狮）。规则：① 遗址 `images` 首位必须是外景/现场遗迹，器物图最多排进图集；② 文物 `images` 只放同器类、同出处的照片，器类不符宁可回退剪影；③ 换图时按 Commons 原题 / 馆方展签核对 provenance，不能只看文件名。

58. **实拍文物卡只换图不补编号行，会在 144 格里留一条 24vp 白边**：详情页文物横滚每格 144（120 图 + 24 编号），占位分支 `AccessionPlate` 自己画满 144；实拍分支若只放一张 120×120 `Image`，格底就空出 24vp 白条，而且没有「L2 · 001」编号行——2026-10-25 模拟器实测被误读为「图片没加载出来」，整格像半成品。规则：**实拍分支和占位分支必须以同一总高收口**——实拍用 `Column`（120 图 + 24 高、居中的 `relicCode()` 编号行），编号与占位签同口径（层号 + 本址序号，按 `site.relics` 数组序补零到三位）。改后王城岗首格为「实拍图 + L2 · 001」，与右侧两张藏品签同高对齐。

59. **Commons 的 API 与图片二进制走的是两个域，被掐的只有 API**：2026-10-25 本机 `commons.wikimedia.org` / `api.wikimedia.org` / `zh.wikipedia.org` 全部解析到 103.102.166.224 并连接超时，但 `upload.wikimedia.org`（103.102.166.240）能直连——`curl` 拿原图 64KB 只要 2 秒。规则：**检索走云端代理（firecrawl scrape 直接请求 API URL，返回体就是 JSON），下载留在本地**（`tools/fetch_commons_images.py`，分段 Range + 魔数校验）。另两条实测：① 三个下载进程并发会触发 `429 does not comply with our robot policy`，改串行 + 429 退避 30s×n 后 6/6 全过；② 分块大小 256KB 时每张要重做 7 次 TLS 握手（1.7MB 约 100 秒），提到 1MB 后基本一次拿完。

60. **子代理报回来的文件名不能直接信**：同一轮检索里，头图组给的 `File:戚城入口 濮阳.jpg` 在 Commons 根本不存在（批量 `titles=` 查询返回 `missing`），另有几张只写了标题没写许可。规则：挂载前用**一次** `action=query&titles=A|B|...&prop=imageinfo&iiprop=url|extmetadata&iiextmetadatafilter=Categories|LicenseShortName|Artist` 批量核存在性 + 分类 + 许可（50 个标题一次请求），分类里点不出该址/该器的直接退回。本轮就是靠这一步把「潼关复建景区全景」「汉霸二王城碑（与荥阳故城是两处国保）」「永昭陵神道石像生（卡片要的是陵台）」三张拦在包外。

61. **内容口径改了，schema 没跟着改，闸门会长期假红——而且被管道吞掉退出码后根本看不见**：`tools/site.schema.json` 规定遗址 `images` 是 `minItems 2 / maxItems 4`，但 2026-10-25 的图像口径已改成「遗址位只放外景/现场遗迹，无实拍就回退年代色；器物实拍可进图集」。于是 7 个站 `0<2`、大河村图集 `13>4` 一直在 FAIL，而 `python tools/validate_sites.py … | tail -4; echo exit=$?` 拿的是 `tail` 的退出码，把红灯全藏住了（同用户级坑「`…| tail` 吞真实退出码」）。规则：① 校验类命令**不许接管道**，要 `>/dev/null 2>&1; echo $?`；② 改内容政策时同步改 schema，并把理由写进 schema 的 `description`——本次改为遗址 `images` 不设下限、上限 16，文物 `images` 上限 2→4（同器多角度实拍并存）；③ schema 的 `pattern` 是小写 `^[a-z0-9_]+$`，落盘文件名别混大写（`real_xizhucun_M1` 已改 `real_xizhucun_m1`）。

62. **大图连拉会触发 upload.wikimedia.org 的 429，而且同机再探测会把限流坐实**：2026-10-25 第三轮要下 14 张 4096×3072 的原图（8.6MB/张），串行下载进程跑到第 5 张起持续 `HTTP 429 Too many requests`，退避 30s×n 也不放行；同时我在另一个 shell 里对同一文件跑 `curl -r 0-1048575` 探速，两路请求互相挤，那次探测 75 秒拿到 0 字节。规则：① 单轮下载控制在 5 张以内、间隔 ≥1s，超了就分轮，别在一个进程里排 14 张大图；② **探测与下载绝不并发**——429 期间任何额外请求都会延长限流（实测 429 后约 5 分钟才恢复）；③ 大图优先拿 Commons 的缩略图尺寸（**只能是固定档宽**，`1024px-` 会回 HTTP 400，本项目用 `1280px-` 再本地压到长边 1024），原图 8.6MB 是纯浪费带宽；④ 退避逻辑要区分 429（长退避，60s 起）与读超时（短重试），现在脚本对 429 只退 30s×n，429 场景不够。

63. **"不挂载"不等于"不进包"——rawfile 里没人引用的文件会一路打进 HAP**：2026-10-26 第四轮对账，前三轮核图撤下的 21 张 `real_` 图一直留在 `rawfile/images/` 里，`.gitignore` 挡得住 git 但挡不住 hvigor 打包，HAP 白背 3.40 MB。同一轮还查出两处：① `validate_sites.py` 缺省把发布版写到 `<src>/../sites-out`，对 `rawfile/sites` 就是**写进资源树**，42 份重复 JSON 进了包；② 9 条图片引用缺 `images/<遗址>/` 前缀，文件在盘上但 `$rawfile` 取不到，界面静默回落剪影——根因是 `check_site()` 只查 enum/minItems/maxItems，**从不应用 schema 里写的 `items.pattern`**，而文物级 `images` 干脆没写 pattern，所以闸门一路绿。规则：**"引用集 vs 盘上文件集"要做双向差集**，正向（引用缺文件）查渲染断裂，反向（文件无人引用）查包体死重，两边都查才算对完账；校验器要顺手校验"文件真在盘上"，光校验路径形制挡不住拼错目录名；派生/审计产物一律写到 `tools/` 下，别落在 `src/main/resources/` 里。修完的复验口径是**从签名 HAP 内部**逐条读 `sites/*.json` 并比对包内文件清单（261 条引用 0 缺失），而不是只看工作目录。


64. **"JSON 里引用了"≠"屏上会显示"——渲染层的过滤让 110 张示意图成为死内容**：2026-10-26 被问"每个地方都有图片吗"时才发现，`DetailPage`/`ListPage`/`RelicPage` 的每一个图位都先过 `isRealImage` / `firstRealImage` / `realImagesExclude`（含灯箱两处 `filter(isRealImage)`），所以 `sites/*.json` 里 184 条非 `real_` 引用**一张都不上屏**，却照样被 hvigor 打进包（2.05 MB）。真正渲染的示意图只有 `EraTheme.ERA_COVER_IMAGES` 那 6 张首页年代卡封面，而它们是**硬编码在 .ets 里、不经内容 JSON** 的。规则：① 内容口径要与**渲染谓词**对账，不能只对着数据文件读——查"有没有图"要顺着 `Image($rawfile(...))` 的每个调用点看它套了什么过滤；② 做资产对账时把"引用但永不渲染"当作第三类差集（此前只查了"引用缺文件"和"文件缺引用"两类）；③ 硬编码在源码里的资源路径是隐性引用面，反向对账先扫 `*.ets` 再判死重（本轮据此保住 6 张封面不被误迁）；④ 收紧校验要分清树的职责：进包树（rawfile）按 `real_` 硬卡，`tools/sites-src` 母本留全量语料且是手写紧凑数组排版，对它硬卡会逼出一整轮无意义重排（实测 `json.dumps` 往返不逐字节一致，改写前的往返断言把这一步拦住了）。

65. **文档写"门禁随构建执行"，而构建脚本里只有 hvigor——承诺与实现可以长期背离**：`设计方案.md` 第 265 行声称"八道脚本门禁全部随构建执行，任一非 0 退出码即阻断出包"，但 2026-10-26 逐字读 `app/build-oh.bat` 只有一条 `hvigorw.js assembleHap`，一条门禁都不跑；`PackingCheck` 只查包结构合法性，不查设计令牌与对比度。这类"写在文档里的流程"必须由一个可执行聚合器承担，否则门禁等于靠人记得跑。规则：① **声明性承诺要去读它指向的那个文件核实**（脚本、配置、CI），文本本身不算证据；② 聚合器给一条命令跑完全部校验（现 `tools/run_gates.py` 12 条：两处 `validate_sites` + `check_attribution` + 七道样式/无障碍门禁 + tsbuild + 单测），由 `build-oh.bat` 在 `assembleHap` 之前调用，`if errorlevel 1` 直接 `exit /b 1` 阻断出包，`SKIP_GATES=1` 仅留给排障；③ 聚合器自己也要能被证伪——新增 `check_attribution.py` 后用"临时塞一张无记录的 `real_` 图"做负对照，确认它真会 exit 1（并把探针文件删干净再复验 0）。附带一条 Windows 坑：cmd 默认 GBK 码页下，把 node 输出里的 `ℹ`、表格里 `×`/`−` 直接 `print` 会 `UnicodeEncodeError` 崩掉整个出包流程；`sys.stdout.reconfigure(errors='replace')` 保留中文可读、只把编不出的字符换成 `?`。④ **`.bat` 本身不能用 UTF-8 写中文**：cmd 按控制台码页逐行解析批处理，中文 `rem` 注释会被多字节序列切出假命令（实测首行报 `'…临时排障，可' 不是内部或外部命令`，且污染后续 `if errorlevel 1` 的判据）——`app/build-oh.bat` 已改成纯 ASCII 注释与提示，中文输出一律由被调用的 `run_gates.py` 负责（并在 bat 里先 `chcp 65001`）。验证阻断要跑整条链路而不是只看子脚本退出码：`cmd //c app\build-oh.bat > log 2>&1; echo $?` 拿到 1、日志里有 `GATES FAILED, packaging blocked`、且 **hvigor 零输出**三条同时成立才算证明（别用 `| head`，那拿到的是 head 的退出码）。

66. **署名台账与图片是两套生命周期，不钉住就会违约**：`rawfile/attribution.json` 由 `tools/build_attribution.py` 一次生成，而 `real_` 图是分五轮挂进来的——每轮都只盯着"图对不对题"，没人回头查"这张有没有记录"。本批 76 张里 61 张是 CC BY-SA（4.0/3.0），漏一张就是一次实打实的许可违约，而且屏上看不出来，评审问到才暴露。规则：① 台账与资产之间要**双向差集门禁**（在包 `real_` − 已记录 = 违约；已记录 − 在包 = 版权页链向不存在的图）；② 逐字段也卡：`CC BY*` 必须有作者、https 来源链接与改动说明，非 BY 系列至少要有来源，否则等同"来源不明"；③ 隐性引用面同样入册——`EraTheme.ERA_COVER_IMAGES` 那 6 张年代兜底图不在内容 JSON 里，必须与 `ai_illustrations` 声明逐张对齐，否则"AI 示意图被当考古照片展示"这条披露会漏；④ 署名在屏上出现两处才站得住：灯箱图注（作品旁边，`ImageViewer.credits`）+ 版权页（完整清单），后者从「我的」进入。

67. **模拟器起不来先看 commit charge，别急着怀疑 hdc 和端口**：2026-10-26 拉起 `Pura X View` 后 `hdc list targets` 恒为 `[Empty]`，`Emulator.exe` 进程存在但没有监听端口，第二次 `-start` 回"this emulator instance is already running"——三条线索都指向"网络/服务"，实际读 `C:\ProgramData\huawei\Emulator\deployed\Pura X View\Log\Emulator.log` 才是根因：`CheckCommitCharge … Warning: Can not allocate virtual memory : 4` + `Commit charge is not enough!`，进程随即自行退出。规则：① 判据是 `GlobalMemoryStatusEx` 的 `ullAvailPageFile`（本机实测 1.4 GB）对实例 `hw.ramSize`（4 GB），不是"有没有 5555 端口"；② 大 commit 占用来自用户其他会话（本机 python 16 个进程合计 14.5 GB commit，含另一个项目的训练任务），**不许代为结束**，要等或请用户自行让出；③ 顺带一条：`hdc kill` 在 pid 文件丢失时会报 `Read pid file failed / Terminal the hdc process in the task manager first`，这条报错**不代表**设备通路坏了，也不代表 hdc 该由我强杀。
68. **字体是第三类版权面，而"文件名像什么"不等于"许可是什么"**：给图片补完署名后顺着同一条线查 `rawfile/font/`，两个 ttf 同样没有任何许可记录，而可读的证据并不对称——`ZCOOLXiaoWei-Sub.ttf` 的 name 表自带 OFL 1.1（nameID 13 声明 + 14 链接，7/8 给出作者 xiaowei / foundry ZCOOL），`NotoSerifSC-Head800.ttf` 的 name 表却被剥到只剩 family/subfamily，**文件本身答不出许可**。规则：① 字体许可按**上游** `google/fonts` 的 `ofl/<family>/OFL.txt` 认定——本轮经 `api.github.com/repos/google/fonts/contents/...`（头 `Accept: application/vnd.github.raw`）实取两份原文并核对首行含 `Copyright`，随包放进 `rawfile/font/OFL-*.txt`；② OFL 的分发条件是"带上版权行与许可本身"，页面上写一句"字体用自 OFL"不够，**原文必须在包里**；③ 门禁三向核对（在包字体 ↔ `attribution.json.fonts` ↔ `licence_file` 存在且首段含 Copyright），并跑负对照（藏掉一份原文 → exit 1）证明它真会红；④ 改名与取字面按实叙述，**不替上游的 Reserved Font Name 条款下"我们已合规"的结论**——那是法律判断，不是这一轮能证的东西。

69. **pptxgenjs 只写 latin 字体槽，中文（东亚槽）留空 = 字体交给对方机器决定**：2026-11-01 出路演 PPT 时，`pres.theme` 里 `headFontFace/bodyFontFace` 设为 Microsoft YaHei，检查发现主题的 `<a:ea typeface=""/>` 与 `<a:cs typeface=""/>` **两个槽都是空的**，母版又是用 `+mn-ea`/`+mj-ea` 引用主题的——于是 9 页里只有我显式传了 `fontFace` 的 3 页（1/3/9）带 `<a:ea>`，另外 6 页的中文完全没有字体声明，落到评审机上会按 Office 自己的默认 CJK 字体渲染（中文 Windows 常见是宋体），字宽与换行点随之改变，本地量好的版式当场不可复现。规则：① 生成 pptx 后**要按层查字体声明**——`ppt/theme/theme1.xml`（major/minor 的 latin/ea/cs）、`ppt/slideMasters/*`（是否 `+mn-ea` 引用）、`ppt/slides/*`（run 层有没有 `<a:ea>`），三层都看过才算"字体定了"；② 补齐用 `tools/pptx_ea_font.py`，只替换 `typeface=""` 这种空槽，**不动 `+mn-ea` 之类的引用**，也不动别的部件；③ pptxgenjs 的 `charts` 枚举不在实例上，正确入口是 `pres.ChartType.bar`、形状是 `pres.shapes.*`；`addChart` 的数据系列**必须带 `labels`**，只给 `values` 会在 writeFile 时抛 `Cannot read properties of undefined (reading 'length')`；④ 分节必须先 `pres.addSection({title})` 再 `addSlide({sectionTitle})`——`addSlide` 是按标题在**已存在**的分节里查，查不到只警告一句、把页丢进 Default 节；⑤ 工作区根 `package.json` 带 `"type": "module"`，CommonJS 的 node 脚本一律 `.cjs`（`gen_icons.cjs` 早就是这个约定）。

70. **"工具打印了成功"不等于"事情做了"——本轮两次假阴性**：① `pptx_ea_font.py` 第一版正则写成 `(<a:(?:ea|cs) typeface=")("")`，多要一对引号，结果**匹配 0 处**却走到"无需改动，幂等通过"的分支，我在终端看到"通过"两个字就准备收工——是复查文件时看见 `<a:ea typeface=""/>` 仍在才抓住的。规则：**幂等分支必须读回文件复验**（改前有空槽而替换命中 0 → 直接失败退出），"没改动"和"改完了"不能共用一条成功文案。② 交付包的匿名化扫描按扩展名过滤文本文件，**恰好跳过了 `.docx`**，而提交稿 docx 正是评审主要读的物件、正文还在嵌套 zip 里；补上嵌套扫描后一次扫到 16 个部件、正文 438 KB，同样的分支也要覆盖 `.pptx`（含 `docProps`，那里会带 author/company）。规则：闸门覆盖面要按"**评审会读什么**"来定，不是按扩展名列表顺手写；新增任何一条扫描/排除规则后**必须做一次证伪**——造一个应当被判红的样本喂进去，看到它真的红才算这条规则存在（本轮用假 pptx 塞校名，slide 与 docProps 两处都命中才收工）。附带一条：打包脚本自身若内嵌身份探测词（人名、机器名、群号），**不能随包分发**，否则这些串被脚本自己带进交付物里——`make_submission_pkg.py` 已在排除正则里把自己挡掉。

71. **`validate.py` 会假失败，根因是联网取远程 XSD，不是稿件缺陷**：2026-11-01 出路演稿时，同一个 pptx 连测出现 `FAILED → PASSED → PASSED`。失败时只报一条：`docProps/core.xml` 的 `XSImport` 解析不了 `http://dublincore.org/schemas/xmls/qdc/.../dc.xsd`（本机实测 `dc.xsd` 回 **403**、`dcterms.xsd` **超时**，属 MEMORY 第 3 章的网络受限面）。Office 系的 `core.xml` 天生要 import Dublin Core schema，离线/受限环境下这个 import 解析不了就报"Failed to parse the XML resource"，看起来像包坏了。判据三条同时成立即可判定为假失败：① 报错**只落在 `docProps/core.xml`**；② **只此一条**（图表/关系/content-types/幻灯片都过）；③ **复跑就 PASSED**。规则：① 遇到先复跑，别去改稿子或怀疑自己的生成器——本轮两份稿的 `core.xml` 命名空间与元素结构逐字段一致，只差标题文本与 creator 是否留空；② 报结论时要**如实把两次结果都写出来**（"首跑因 XSD 拉取失败，重跑全绿"），不能只挑 PASSED 那次说，否则掩盖了真实经历；③ 这条同样适用于 docx/xlsx 校验器——凡见 `Failed to parse the XML resource 'http://...'`，先归因网络再归因文件。

72. **多步生成链路会在中途失败时留下"看起来成功"的半成品，必须断言最终产物的特征**：出路演 pptx 是 `writeFile → applyTheme → 补字体槽` 三步。`applyTheme` 找不到 jszip（全局装但裸 `require("jszip")` 解析不到）时会 throw 且明写 "Nothing was changed"——**但第一步的 `writeFile` 已经把一份未上色的 pptx 留在盘上了**。谁漏看退出码（`node … | tail`、或任何只看输出不看 code 的调用），拿到的就是 Office 默认蓝 `4472C4` 的稿子，视觉上一应俱全、只等评委打开才发现配色全错。规则：① 链路的**最后一步要断言"前几步真的生效了"**——现在 `pptx_ea_font.py` 收第三个参数，复验 `theme1.xml` 里有没有预期 accent1（`9C4A2F`），没有就直接失败；② 断言必须**证伪**：用桩替换 `applyTheme`（`HH_PPTX_APPLY_THEME` 指向一个空实现）跑一遍，实测产物 accent1 落在 `4472C4` 且被拦下、退出码 1；正常路径 accent1 `9C4A2F`、退出码 0；③ 补槽一步永远排在 `applyTheme` 之后，反过来会被主题重写回空槽（见 69）；④ 验证临时产物一律写 `_scratch/` 再删，别让它落到交付路径（本仓库有"根目录只允许一份 pptx"的不变量）。

73. **纯函数写好了、注释也宣称接线了，调用方却一个都没有——这是"看起来修了"的最隐蔽形态**：`service/merge/LogicalClock.ets` 完整实现了单调时钟，注释明写"高水位存 `sync_meta.lastWrite`，见 `UserDataRepo.nextWriteTime`"，可全仓检索发现 `monotonicNow` 除自身与测试转译清单外**零调用方**，`UserDataRepo` 里也不存在 `nextWriteTime`，写路径仍是 11 处裸 `Date.now()`；同仓库 README 的"已知限制"还老实写着"LWW 使用 Date.now，没有逻辑时钟"，两处说法互相矛盾。后果是真实的：同一毫秒连点收藏产出并列时间戳，LWW 退到 `deviceId` 字典序，与"谁后写"的因果无关；设备时钟被回拨后该设备后续编辑会整批输给对端。规则：① 判定"某机制已生效"的唯一口径是**调用方存在且在写路径上**，注释与文档一律不算证据——`grep 函数名` 数调用点比读注释可靠；② 高水位不能放门面层：`读高水位 → 算新值 → 回写` 三步都跨 `await`，两次并发写会交错拿到同一个旧值，所以实现落在 `LocalRdbImpl`，并把调用排成一条串行队列（`writeChain`），失败只吞结果不断链；③ 合并进来的远端 `updateTime` 必须吸收进高水位（`observeSyncedTime`），否则本机时钟慢于对端时，自己的下一次写入会立刻输给刚同步回来的那条；④ 补测只能测纯函数（`logical_clock.test.mjs` 7 条），持久化部分需要真机 RDB——**这点要在测试注释里写明**，不要让绿色数字冒充端到端验证。

74. **首屏 `await` 数据库初始化 = 白屏，而"先恢复模式再 `loadContent`"这个顺序又不能简单删掉**：`EntryAbility.onWindowStageCreate` 原本等 `AutoSync.prepare()` 完成（开 RDB、老库跑迁移、按 `syncMode` 切档案）才 `loadContent`，首页骨架与 `rawfile` 语料这些**根本不依赖数据库**的东西被一起按住；而直接倒过来又会出另一种错——首页先读主库，等模式切到仿真档案后不重读，用户看到"数据少了一半"（同第 56 条：跨页换库后旧数据停在屏上）。规则：**把"顺序要求"和"执行时机"拆开**——时机上前置动作转后台、界面先出；顺序上收成一道闸门（`service/sync/BootGate.ets`）：页面所有读写都经 `UserDataRepo.get()`，`get()` 先等闸门，`prepare()` 走完（成功/失败/超时）必放行。要点有三：① 闸门必须**带超时兜底**（3s），否则 `prepare` 万一没被调用就把页面吊死；② 放行点要排在 `prepare` 内部的 `checkNow()` **之前**——`checkNow → triggerSync → UserDataRepo.get()` 同样在等闸门，顺序写反就是自锁；③ 这类"先出一半再补齐"的改动，屏幕上的中间态要能被证伪（本轮口径：`BOOT corpus ready` 锚点从此记录的是用户真正看见首页的时刻，见设计方案 T4 行），不能只凭"构建通过"宣布完成。

**本轮自查又踩了一次第 65 条的同一格**：第一次证伪时我写 `node … 2>&1 | tail -3; echo "退出码=$?"`，拿到的是 `tail` 的退出码 0，而 node 其实是 1——正是这条坑里点名批评的写法。去掉管道重测才拿到真值。**教训形式**：判据是"我这条命令的退出码是谁的"，凡是管道末端不是被测进程，`$?` 一律不可信（PowerShell 侧同理：`| Out-String`、`| Select-Object -Last N` 都换掉退出码）。

76. **`uitest dumpLayout` 不导出 `accessibilityText`，只导出 `description`——纯图标按钮因此"读屏能念、脚本点不到"**：2026-11-06 逐页实测时，档案页头三颗图标按钮（搜索/导出/更多）在 dumpLayout 里是 `type=Column clickable=true` 而 `text` 与 `desc` 双空，一度被我判成"控件树里没有文本节点"的缺陷。查证后结论要分开：① `-e <attr>` 只接受 `uniqueId`（实测 `-e accessibilityText` 直接报 `Invalid attribute name, currently supported names are 'uniqueId'`），所以**工具确实拿不到 accessibilityText**；② 但 `accessibilityText` + `accessibilityLevel('yes')` 对读屏是生效的，判"读屏念不到"是错的；③ 真正的缺口是**可测试性**——脚本无法按文案定位纯图标按钮，只能按坐标，而坐标随分辨率/布局漂移。修法：给组件补 `accessibilityDescription`（本仓 Accessibility.ets 的既有约定本来就是"text 给是什么、description 给会怎样"），dumpLayout 的 `desc` 字段立刻可读。复验口径：改前该行子树三个 Column 的 desc 全空，改后读出 `打开全局搜索 / 打开导出页，可选 Markdown 或 JSON / 打开图片版权与来源` 三条，`len(hits)==3` 才算成立。**顺带一条取证纪律**：把"控件树里没有"当结论前，先区分「应用没设」「工具不导出」「被父节点合并」三种成因，否则会把工具限制写成产品缺陷。

77. **同一个「设备 A」背后可能是两个库——冷启未进同步页时读主库，进过同步页后切到仿真库**：2026-11-06 逐页实测末尾发现档案页显示「收藏 9 条」，而 `huanghe_memory.db.sim.deviceA` 里只有 2 条，一度判成"屏上计数与库不一致"。查 `AutoSync.prepare` 才明白：`readSyncMode` 返回 `''`（从未选过模式）时**故意保持主库**，注释写着"避免升级后把老用户的主库数据藏起来"；只有 `mode==='sim'` 才 `setSimMode(true)` 切到 `sim.deviceA`。而 `setSimMode(true)` 只在**进同步页**时被 `SyncPage.aboutToAppear` 调用，所以：① 冷启 → 档案页读的是主库 `huanghe_memory.db`；② 进过一次同步页 → 之后全站读 `huanghe_memory.db.sim.deviceA`。两处都自称「设备 A」，数据却是两份。**演示影响**：预置数据如果是在"没进过同步页"的状态下写的，进了同步页做冲突演示时会看起来"数据没了"；反过来，冲突演示后回到档案页读的是仿真库，主库里预置的东西不在屏上。**做法**：预置数据**在进过同步页、切到仿真身份之后写**；或者在演示脚本里把"先点一次同步页"列为固定前置动作（现脚本 F3 第 1 步就是进同步页，顺序是对的）。**取证影响**：判"计数对不对"必须同时报出**读的是哪个库文件**（`UserDataRepo.storeName()` 在同步页「设备与档案」里有现成读数），只比屏上数字与某个 db 文件会把正确行为判成缺陷。


75. **全站第一次上手势，两格都是编译器和屏上告诉我的，不是文档**：2026-11-06 给 `ImageViewer` 加双指缩放（`common/ZoomMath.ets` + 手势接线），① **`@State` 字段名不能叫 `scale`**——ArkUI 给每个自定义组件都挂了 `.scale()` 属性，同名状态字段把属性遮蔽，编译报 `10505001 Property 'scale' in type 'ImageViewer' is not assignable to the same property in base type 'CustomComponent'`，而且**报错行号指向状态声明（43 行），不指向真正冲突的 `build()` 调用处**，按报错去找 `.scale({...})` 会找错地方。改名 `zoom` 即通。同类风险名要一起防：`position`、`size`、`opacity`、`translate`。② **图片节点上那句"空 `.onClick` 防穿透"把双击吃掉了**——它本是为了让点图不冒泡到下层遮罩而误关灯箱，但 `onClick` 等价于一个 `count:1` 识别器，与 `TapGesture({count:2})` 并存时实测 `uitest uiInput doubleClick` 完全不触发放大。SDK 在 `GestureGroupGestureHandlerOptions.gestures` 的 NOTE 里把规则写死了：**双击必须排在单击之前，反了两者都不工作**。改法是删掉 `.onClick`，把 `TapGesture({count:1})` 空操作放进同一个 `GestureGroup(GestureMode.Exclusive, …)` 末尾——拦截效果一样（节点上有识别器就不穿透），双击先判。**教训形式**：一个节点上"点击"和"多次点击"不能一个走属性一个走手势，必须同组同序；改完要拿注入命令实测那条最像没事的路径（本轮 `doubleClick`），别信"编译过了就是能用了"。③ 顺带一条取证口径：缩放这类纯视觉变化，`dumpLayout` 里读不到 `translate/scale`，**要在屏上留一个文字读数**（顶栏右侧 `2.5×`，未放大时是"双指 / 双击可放大"提示），否则自动化只能断言一个空字符串；判"画面真的动了"用截图 md5 比对（1× 拖动前后 md5 相同、放大后拖动 md5 改变），最终仍以看图为准。

78. **字体子集里「有映射、有轮廓、却画成纯黑方块」——`check_font_coverage.py` 的两条判据都放行，而且这个脚本根本没接进 13 道门禁**：2026-11-06 测导出→导回时，导出页标题「把带走的档案放■来」的「回」渲成实心黑块。查到根因在 `ZCOOLXiaoWei-Sub.ttf` 的 U+56DE：三条轮廓**绕向全为负**（-473646 / -93144 / -310068），非零填充规则下内白被填死；参考字体 `NotoSerifSC-Head800` 同字正常，PIL 直接栅格化该 TTF 也是黑块 ⇒ 是字体数据坏了，不是渲染、不是缺字、不是加粗。`check_font_coverage.py` 只查「cmap 有映射 + `numberOfContours!=0`」，这字两条都过；更要命的是 `run_gates.py` 的 13 道里只有 `check_font_pairing.py`，**`check_font_coverage.py` 从来没被调用**，所谓"门禁全绿"与它无关。**修法**：字体是 OFL 且带 Reserved Font Name，不重制 1.1MB 二进制；只把那一处文案改成「把带走的档案放进来」避开该字，装机截图确认黑块消失。**判据踩坑（全部收回）**：先后试过四种自动判据——① 包围盒判嵌套同向 → 误报 729 字（`日`/`田` 这类多笔画字全中招）；② 小字号洞面积阈值 → 误报 59 字；③ 大字号差分 → 误报 49 字（真值：49 个候选里只有「回」一个是黑块）；④ 字心五点非零绕数 → 误报 251 处（`细`/`发`/`水` 笔画穿过字心）。**可靠的只有"与参考字体逐字比对栅格化洞面积"**，但要引入 PIL 栅格化，成本高于这个门禁的定位，故不并入 `check_font_coverage.py`，只把这段结论写进它的文件头注释。**教训形式**：判据必须拿"已知坏字 + 已知好字"做正负对照再采信；一串越来越大的数字（729→59→49→251）本身就是在报警，别顺着它往外报结论；「全绿」之前先核这个检查到底在不在门禁清单里。

