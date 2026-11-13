# 黄河记忆 · 黄河文化分布式数字档案

HarmonyOS / OpenHarmony 应用（Stage 模型，ArkTS/ArkUI，API 26）。内容全部预置在本地，断网可读；用户产生的收藏、笔记、标签、研读进度通过分布式 RDB 在两台设备间同步，冲突按 LWW 规则裁决并保留败方快照。

## 项目概况

- 42 个遗址、104 件文物（按 `rawfile/sites/*.json` 的 id 统计），六个年代、五段落（考古 / 历史 / 诗词 / 文旅 / 参观）。
- 19 个页面：首页、遗址列表、遗址详情、文物图录、文物详情、全部笔记、笔记编辑、关联目标、收藏、最近删除、搜索、推荐、主题路线、路线详情、同步、主题网络图、导出档案、版权、我的。
- 运行时不依赖第三方库；仅测试使用 `@ohos/hypium` 与 `@ohos/hamock`。
- 包名 `com.example.huanghememory`，`compatibleSdkVersion` 为 `26.0.0`。

## 目录

```
app/                          HarmonyOS 工程（build-profile.json5、entry/）
  entry/src/main/ets/
    model/                    纯类型与同步域常量
    service/                  纯函数：合并、推荐、内容解析、路线、笔记回顾、网络图、布局、导出排版
    repository/               RDB、语料、署名表、传输适配器、系统文件保存
    pages/                    19 个页面
    common/                   设计令牌、主题、动效、按压、无障碍
  build-oh.bat                命令行出包（先跑门禁，再 assembleHap）
tools/                        内容校验、设计门禁、Node 单测、素材脚本
docs/                         设计规范、踩坑记录、演示脚本、开源参考
sign/                         debug 签名材料（换机需重新生成）
```

## 环境要求

- DevEco Studio（含 API 26 SDK）与 OpenHarmony SDK。
- Python 3（门禁脚本）。
- Node.js 24（`node --test` 与 `.ets` 类型剥离；低于 24 可能跑不了 `tools/merge-tests`）。
- 一台 API 26 真机或模拟器；真机分布式同步需要两台设备。

## 构建

```bat
cd app
build-oh.bat
```

`build-oh.bat` 会先执行 `python tools/run_gates.py`，任一门禁非 0 退出即阻断出包。默认工具链路径是本机路径，换机器时用环境变量覆盖：

```bat
set DEVECO_SDK_HOME=D:\DevEco Studio\sdk
set OHOS_BASE_SDK_HOME=D:\OpenHarmony\Sdk
set HUANGHE_NODE=D:\DevEco Studio\tools\node\node.exe
set HUANGHE_HVIGOR=D:\hvigor\bin\hvigorw.js
build-oh.bat
```

只在排障时使用 `SKIP_GATES=1`，不要用它产出交付包。

## 门禁与测试

```bash
python tools/run_gates.py            # 全跑 13 道
python tools/run_gates.py --list     # 查看清单
python tools/run_gates.py --only contrast,a11y
node --test tools/merge-tests/*.test.mjs
```

门禁覆盖内容 schema、图片引用与署名、诗词完备性、对比度、设计令牌、跨页间距、适老字号、无障碍、动效、字体搭配、纯函数转译与 Node 单测。

注意：门禁只在 `build-oh.bat` 路径上强制执行；用 DevEco Studio 直接 Run 不会触发。

## 交付出稿

三份要交给赛事的物件都由脚本产出，不手工编辑——手工改的稿子每次构建都会被覆盖：

```bash
python -I tools/make_submission_docx.py     # 设计方案-提交稿.docx（正文宋体·小四·1.5 倍）
# 路演稿：默认就地覆盖交付件路演PPT-提交稿.pptx；--out=<路径> 可另出
NODE_PATH="$APPDATA/npm/node_modules" node tools/make_roadshow_deck.cjs
python -I tools/pptx_ea_font.py 路演PPT-提交稿.pptx "Microsoft YaHei" "9C4A2F"
python -I tools/make_submission_pkg.py      # submission/ 下的交付包（清脏物 + 脱敏 + 自检）
```

- Word 稿的事实源是 `设计方案.md`，提交版差异（去本机路径、去渠道信息、历史读数加口径注）集中在 `make_submission_docx.py` 的 `REPL`/`DROP_BLOCKS` 里，改稿请改这两处而不是改 md 的结论。
- 路演稿由 `make_roadshow_deck.cjs` 生成（12 页、逐页含口播与秒数备注、两张原生图表），配色与母题取自应用自己的年代色。**出稿后必须跑 `tools/pptx_ea_font.py` 补齐主题的东亚字体槽**，否则中文会退化成评审机的默认字体（见 `docs/PITFALLS.md` 第 69 条）；第三个参数是期望的 accent1 色值，缺位即失败退出——`applyTheme` 失败时坏稿已经落盘，不能只看退出码。历史备选稿（9 页版）存 `alternates/`，不在交付包内。
- 交付包脚本负责三件事：排除脏物与凭证（`sign/` 私钥、构建产物、探针中间物、`.bak`）、文档内本机绝对路径中性化、包内生成《交付清单.md》并**出包后自检断言**（排除项是否真被排除、中文文件名是否带 UTF-8 标志位、身份与院校信息是否零命中）。校名队名只出现在压缩包文件名上，包内正文出现即判红。
- 包体上限按「HAP ≤40MB、视频 ≤100MB」执行；需要不含 HAP 的瘦包用 `--slim`。

## 签名

`app/build-profile.json5` 当前指向本仓库 `sign/` 下的 debug 材料，且是绝对路径。换机器或换设备时：

1. 在 DevEco Studio 的 Project Structure → Signing Configs 重新生成调试签名；
2. 或修改 `storeFile` / `profile` / `certpath` 三个路径；
3. 确认目标设备在 debug profile 的允许列表内，否则 HAP 安装会被拒。

## 演示

- 单机仿真：同步页默认模式，两份独立档案（`huanghe_memory.db.sim.deviceA/B`），可稳定演示“同一笔记两端修改 → 冲突裁决”。
- 真机分布式：两台 API 26 设备登录同一华为账号、接入同一局域网并完成可信组网；在同步页切到“真机分布式”，首次同步会申请 `ohos.permission.DISTRIBUTED_DATASYNC`。
- 真机不可用时切回仿真，合并引擎与冲突日志是同一套。

## 已知限制

- 版本号取自本机**单调逻辑时钟**（高水位持久化在 `sync_meta.lastWrite`，见 `service/merge/LogicalClock.ets` 与 `LocalRdbImpl.nextWriteTime`）：同一设备连写不会产生并列时间戳，时钟回拨也不会让后续编辑整批输掉。但**两台设备之间的时钟偏差仍会影响裁决**——A 的墙钟比 B 快一分钟时 A 的编辑会稳赢，这需要系统侧 NTP 兜底，应用层不做跨设备逻辑时钟。
- 真机同步是「拉取快照 → 合并 → 推送终态」三步，不是分布式事务；对端在拉取之后、推送之前的新写入仍可能被覆盖（窄窗口，单机仿真无此问题）。
- 只同步用户层六张表，语料本身不参与同步（语料随包预置）。
- 冲突自动裁决，不提供手工选择保留哪一版；败方版本可在冲突历史中回看。
- 标签关联表已改为软删墓碑；老库首次启动会自动补 `isDeleted` 列。
- 网络图用 Canvas 绘制。画布本身读不出内容，替代文本给了统计与操作说明，年代 / 标签另有一行等价的文字芯片（可聚焦、可选中、再点取消）；遗址与文物的条目清单在年代清单下方，可聚焦、点按直接进详情，节点级语义与画布同路。
- 档案可以导出（Markdown / JSON，走系统保存框），也可以把 JSON 档案导回：导入沿用导出格式（`huanghe-memory/archive@1`），按「targetKey + 正文」判重笔记、按 targetKey 跳过本机已有或已删的收藏、进度逐行 LWW（导出版本号更新才写入），且导入不覆盖本机在导出之后的任何编辑与删除。Markdown 不能导回。
- 只有浅色主题。夜间模式需要把全部颜色从构建期常量改成可观察状态并重做对比度校验，属 P3 裁剪项，理由见 `docs/功能补全方案.md` 0.1。

## 相关文档

- `设计方案.md`：总体设计与赛题映射。
- `docs/答辩/`：**答辩资料**（`01` 十二页讲稿与数字口径 / `02` 老师提问速查 47 题 / `03` 现场操作清单）；数字口径以 `docs/答辩/README.md` 的实测基线为准。
- `docs/学习路线.md`：10 个学习板块（按依赖方向排，从数据契约到交付链路）。
- `docs/strata-ui-spec.md`：展陈白盒视觉规范与对比度实测。
- `docs/PITFALLS.md`：真机与 SDK 踩坑记录（现象 / 原因 / 规则）。
- `docs/演示脚本.md`：5 分钟演示时间线。
- `docs/OPEN_SOURCE_REFERENCES.md`：同类项目与官方约束参考。

## 仓库说明

- 本仓库是源码与文档快照：`app/`（HarmonyOS 工程）、`tools/`、`docs/`、`design/`、`设计方案.md`、`路演PPT-提交稿.pptx`、`设计方案-提交稿.docx`。
- 未随源码上传：`sign/`（调试签名材料，换机需重新生成）、`submission/`（赛题交付压缩包）、`演示视频.mp4`。
