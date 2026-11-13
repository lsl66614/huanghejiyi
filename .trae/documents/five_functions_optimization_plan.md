# 《黄河记忆》五项主要功能对标优化实施计划

> 依据:第三届河南省高等学校信息技术应用创新大赛通知(2026)附件 1「赛题一」逐条核对
> 范围:仅赛题一 5 项主要功能的代码与预置数据优化;不含 docx/视频/PPT 等提交材料(材料另案)
> 基线:HAP 已可构建(API 26),42 处遗址 / 104 件文物 / 149 图,Node 单测 19/19 绿

---

## 一、调研结论(上网学习类似项目与官方文档)

### 1. 鸿蒙分布式数据管理的官方路径(决定功能 3 方案)

- 官方关系型数据库跨设备同步四步:`store.setDistributedTables([...])` → `distributedDeviceManager.getAvailableDeviceListSync()` 取设备 → `store.remoteQuery(deviceId, table, predicates, columns, cb)` 拉对端数据 / `store.sync(SyncMode.SYNC_MODE_PUSH, predicates, cb)` 推送 → `store.on('dataChange', SubscribeType.SUBSCRIBE_TYPE_REMOTE, cb)` 订阅远端变化。
  来源:[关系型数据库跨设备数据同步(ArkTS)](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V14/data-sync-of-rdb-store-V14)
- **关键限制(已证实)**:`Distributed Service Kit` 设备管理模块「**暂不支持模拟器**」;开发者论坛官方答复模拟器分布式「目前还不支持」。分布式数据对象(dataObject)仅限跨设备 Call 协同场景,且单对象 ≤500KB,不适合本项目五表结构。
  来源:[分布式设备管理开发指南·模拟器支持情况](https://device.harmonyos.com/cn/security/harmonyos-guides/devicemanager-guidelines)、[华为开发者问答](https://developer.huawei.com/consumer/cn/forum/topic/0203191621325788118)
- 权限:跨设备同步需用户授权 `ohos.permission.DISTRIBUTED_DATASYNC`(user_grant),设备须同账号可信组网、同局域网或蓝牙开启。

**推论(功能 3 决策)**:采用「**双轨制**」——保留现有 Loopback 双档案仿真(模拟器/无第二台真机时的兜底演示,比赛现场零硬件风险),同时新增**真实的分布式 RDB 传输适配器**(真机上走 `remoteQuery/sync` 官方 API),SyncPage 可切换、检测不到组网设备时自动回落。这样代码中存在可评审的真实分布式实现,演示又不被硬件绑架。

### 2. 同类文博产品的可借鉴点(只取契合项)

- 山西博物院「文物知识聚合展示」:检索后跨类型汇聚知识、实体间超链接互访 → 本项目已具备「根系网络图 + 脉络推荐」雏形,优化方向是**详情页内联关联跳转、网络图节点直达条目**,不新做重功能。
- 中国文物报(2026)「十五五」规划方向:文物图像知识图谱 → 与本项目 NetworkPage 叙事一致,可在设计方案中引用为对标依据。
- 国博鸿蒙元服务、智游文博金奖(NFC 碰一碰/服务流转)、湖北博 AI 导航:均依赖元服务、NFC、地图或后端,超本赛题「纯北向、可离线、无三方依赖」边界,**不学**。
- 文博内容通则:时间轴 + 实体关联 + 个性化推荐,与赛题三维结构一致,不额外扩张范围。

### 3. 仓库现状核对(逐功能证据)

| 功能 | 已具备 | 缺口(本计划要解决的) |
|---|---|---|
| F1 展示检索 | 42 遗址/104 文物;六年代×四类型×五市枚举;ListPage 关键词+三维筛选;详情五层级+文物子页 | ①42 个 JSON 的 `sections.poems` **全部为空数组**,「诗词」层无内容;②首页「检索」入口写死带 `era=yangshao` 参数,进页即被过滤 |
| F2 收藏笔记标签 | 遗址/文物双实体收藏;笔记文字+时间戳+标签(预置三标签+自建);墓碑删除 | ①收藏页 4 个标签 chip 是**死按钮**(只改高亮,不筛选、不能给收藏贴标签),赛题「按标签对收藏内容分类管理」未闭环;②progress 在写入但首页无任何研读完成度可视化(设计稿承诺的「年代完成度环」缺失) |
| F3 分布式同步 | LWW 合并、墓碑、冲突历史、面板三要素全部真实;MergeEngine 与 ITransport 解耦 | 仅 Loopback 单机仿真,全工程无分布式 API;无 DISTRIBUTED_DATASYNC 权限 |
| F4 离线浏览 | 全资产 rawfile 预置,HAP 9.86MB,零网络依赖 | 无代码缺口;补「网络恢复自动同步」钩子(随真机适配器一并提供),并形成人工离线实测记录项 |
| F5 智能推荐 | 本地加权纯函数(年代0.4/类型0.3/城市0.2/标签Jaccard/行为≤0.15),详情页与推荐页已接入 | 「浏览行为」**未采集**,behaviorHistory 实际只取收藏;无全局「为你推荐」入口 |

---

## 二、文件与模块清单

### 数据(rawfile,新增内容,不改 schema)
- `app/entry/src/main/resources/rawfile/sites/*.json`(42 个):为 `sections.poems` 补 1–2 条 `{text, author, source}`,字段形状与现有 schema 一致,解析器 `ContentParse` 无需改动。

### 数据模型与仓储
- `model/UserDataModels.ets`:新增 `VisitDO`(浏览记录)与收藏标签关系的类型(如需)。
- `model/SyncModels.ets`:`SYNC_TABLES` 增加 `favorite_tag`(收藏-标签关系纳入同步域)。
- `repository/IDataRepository.ets`:补 `listFavoriteTags/setFavoriteTags/listVisits/addVisit` 等签名。
- `repository/LocalRdbImpl.ets`:
  - DDL 新增 `favorite_tag(target_key, tag_id, updateTime, PK 复合)` 与 `visit(target_key, createTime INTEGER PRIMARY KEY?)`;
  - `TABLE_META` 注册 `favorite_tag`(与 note_tag 同构,无墓碑列);
  - visit 表仅本地缓存,**不进** `SYNC_TABLES` 与 `TABLE_META`;
  - 初始化后 `setDistributedTables`(六张同步表,sync_meta 不同步)。
- `repository/UserDataRepo.ets`:收藏贴标签/查标签、`recordVisit`(环形保留最近 50 条)、`recentVisitInputs` 装配。
- `repository/SoftBusRdbTransport.ets`(**新增**):实现 `ITransport`,封装设备发现 → remoteQuery 拉五表快照 → 合并后 sync 推送 → dataChange 订阅;任何一步不可用即抛带 code 的错,由 UI 回落。

### 页面
- `pages/FavoritesPage.ets`:标签 chip 接真实筛选;条目增加「贴标签」操作(复用标签池,预置三标签+自建);空标签态「全部」。
- `pages/Index.ets`:①检索入口改为不带 era(进全量列表);②六年代卡叠加「研读完成度」小环(progress 按 era 聚合:该年代遗址五段完成数/总数)。
- `pages/DetailPage.ets`、`pages/RelicPage.ets`:`aboutToAppear` 调 `recordVisit`(去重节流,同条目 60s 内不重复记)。
- `pages/RecommendPage.ets`:新增无参「为你推荐」模式(候选=全部遗址,行为=收藏+浏览)。
- `pages/MinePage.ets`:文案「78 件」改 104;同步入口副标题随模式显示。
- `pages/SyncPage.ets`:顶部模式切换「双档案仿真 / 真机分布式」;真机模式下:申请权限→列出可信设备→同步;0 设备置灰并提示回落;面板方向文案显示真实设备类型。
- 标签选择器若两处复用,抽 `common/TagPicker.ets`(轻量 @Builder 组件);仅在复用确实成立时创建。

### 配置
- `module.json5`:abilities 同级 `requestPermissions` 增 `ohos.permission.DISTRIBUTED_DATASYNC`(reason/usedScene 字符串放 resources)。
- `resources/base/element/string.json`(或现有字符串文件):权限说明文案。

### 测试
- `tools/merge-tests/`:①merge 引擎增加 favorite_tag 关系表同步用例;②recommend 增加「浏览历史改变排序」用例;③content_parse 增加「42 遗址诗词非空」断言;④run.mjs 文件清单无需新增模块(均为既有文件)。

---

## 三、实施步骤(依赖排序)

### 阶段 A:内容补齐(零代码风险,先做)
1. 导出 42 个 JSON 的 `id/name/era/city` 清单,按「年代+地域」匹配诗词。
2. 诗词编纂铁律:**只录公有领域确定名篇,真句真作者真出处,禁止杜撰**;归属原则:
   - 夏商条目→《诗经·商颂》;两周洛阳/卫地(濮阳)→《诗经·郑风/卫风/王风/小雅》;
   - 汉唐→唐代名家(洛阳用白居易/刘禹锡/李白,陕州可用杜甫《石壕吏》,开封用盛唐咏汴句);
   - 宋→宋词咏汴洛(周邦彦/刘子翚《汴京纪事》等);
   - 史前(仰韶/龙山)无当代作品,用咏黄河/怀古名篇(王之涣、李白《将进酒》、刘禹锡《浪淘沙》),`source` 如实写篇名;
   - 无法确定具体地域的,放通用黄河诗词,不硬配。
3. 每处至少 1 条;写 Node 脚本做临时校验(poems 非空、author/source 非空、无重复污染),脚本放 `tools/` 下作为正式校验工具保留。

### 阶段 B:F2 收藏标签闭环 + 进度可视化
4. 模型/DDL/接口/仓储加 `favorite_tag`(参照 note_tag 现有实现,含标签字典自动补全)。
5. `SyncModels.SYNC_TABLES` 注册新表;MergeEngine 为泛型实现,验证无需改算法。
6. UserDataRepo 封装贴标签/查标签;FavoritesPage 接通:chip 真实过滤、条目「贴标签」弹层、swipeAction 保留。
7. Index 年代卡完成度环:新增 progress 聚合查询(按 era 统计 done 段数),`onPageShow` 刷新。

### 阶段 C:F5 浏览行为与推荐
8. visit 表(本地、不同步)+ `recordVisit` 节流写入;Detail/Relic 页埋点。
9. RecoSource 的 behaviorHistory 改为「最近收藏 + 最近浏览」合并输入;RecommendPage 支持全局模式;MinePage/Detail 入口接通。
10. 推荐单测覆盖行为加权排序。

### 阶段 D:F3 真机分布式(隔离度最高,放最后)
11. `module.json5` 加权限与文案;LocalRdbImpl 初始化成功后 `setDistributedTables`(try/catch,模拟器上失败仅记日志,不阻断)。
12. 新建 `SoftBusRdbTransport`:`createDeviceManager('com.example.huanghememory')` → 设备列表 → 逐表 `remoteQuery` 转 SyncRecord(复用快照行映射逻辑)→ runSync 合并 → `sync(PUSH)`;`on('dataChange', REMOTE)` 回调触发面板刷新。
13. SyncPage 双模式 UI:权限运行时申请;真机模式无设备/异常时明确提示并一键切回仿真;仿真模式现有功能与文案保持不变。
14. 网络恢复自动同步(可选,随本阶段):`@kit.NetworkKit` connection 订阅 netAvailable,仅在真机模式触发一次 runSync;若编译/复杂度超预期则裁剪,不影响主线。

### 阶段 E:收尾
15. MinePage 文物数文案;Index 检索入口参数修正(可在 A 阶段顺手做)。
16. 全量验证(见下),失败只允许收敛修复,不扩范围。

---

## 四、依赖与注意事项

- ArkTS 严格规则:禁 `any`/非空断言 `!`/解构/对象展开;catch 量必须包 `Error` 再抛(已踩过);对象字面量仅赋 Record/ValuesBucket;V1 装饰器,不引入 V2。
- `favorite_tag` 走 `applyMerged` 的 UPSERT 事务路径（只写合并终态，不物理删行；删除靠 `isDeleted` 墓碑表达）,白名单 `SAFE_COLUMN` 已覆盖列名注入;新增表不改变事务代码。
- 分布式表约束:仅关系型表可 setDistributedTables;sync_meta 不设置;安全级现为 S1,跨设备同步文档示例用 S3,若真机报安全级错误则升 S3(不影响本地逻辑)。
- 模拟器上 deviceManager 直接不可用:SoftBusRdbTransport 的所有调用必须可失败、可回落,严禁因能力缺失导致页面崩溃或仿真模式不可用。
- bundleName 固定 `com.example.huanghememory`;签名/HAP 当前为 debug 签名,真机分布式要求同应用同签名多端安装。
- Git 纪律:只 add huanghe-memory 路径,不提交 commit(用户未要求);不处理索引中历史冲突条目。
- 不新增三方运行时依赖;图片资源不涉及新增。

## 五、验证

1. `node tools/merge-tests/run.mjs` + `node --test "tools/merge-tests/*.test.mjs"`:全绿(含新增 favorite_tag 同步、浏览加权、诗词非空用例)。
2. 完整构建:`app\` 下 hvigor shim + JBR 环境变量跑 `assembleHap` debug,BUILD SUCCESSFUL,HAP 产出。
3. 人工走查清单(模拟器,记录截图供后续文档):
   - 42 处详情页诗词层均有内容;
   - 收藏条目贴标签→chip 筛选生效→杀进程重启仍在;
   - A/B 双身份改写同一条(含标签)→同步→标签关系一致、冲突历史正确;
   - 浏览若干遗址后推荐页排序变化;
   - 真机模式在模拟器上优雅提示并可切回仿真(不崩溃);
   - 飞行模式下浏览/收藏/笔记/仿真同步全流程可用。

## 六、风险与对策

| 风险 | 对策 |
|---|---|
| 诗词地理归属拿不准 | 宁缺毋滥,降级为通用咏黄河名篇并如实标 source;不杜撰作者 |
| favorite_tag 进同步域引入合并问题 | 与 note_tag 同构,MergeEngine 不改算法;新增针对性单测先写后验 |
| 分布式 API 在 SDK 26 签名/行为差异,本机无法实测 | 适配器与 UI 解耦、全程 try/catch 回落;编译通过+仿真全绿为门禁,真机验证列为人工项 |
| 阶段 D 超预期膨胀 | D 阶段独立成块,可整体裁剪而不影响 A–C 交付;网络恢复钩子最先裁 |
| 完成度环/全局推荐改动首页结构 | 复用现有年代卡与推荐纯函数,仅增量渲染,不改导航骨架 |
