# 任务看板（task-board）

本机个人使用的任务与进度看板。MCP App 页面 + 无第三方依赖的 stdio MCP Server，数据只写入本地 JSON。

## 结构

```text
task-board/
├── .qoder-plugin/plugin.json    # 插件清单
├── .mcp.json                    # 通过 ${QODER_PLUGIN_ROOT} 启动 server.mjs
├── server.mjs                   # stdio MCP Server：工具、HTML 资源、本地持久化
├── app.html                     # 页面结构与样式（light / dark 主题变量）
├── app.js                       # 页面与宿主的 JSON-RPC 通信、渲染与交互
├── skills/task-board/SKILL.md   # 模型侧工作流说明
├── scripts/smoke.mjs            # 静态检查 + 真实子进程协议测试
└── package.json
```

没有 `commands/`、`agents/`、`hooks/`、外部 Connector：按需求只包含页面、Server 与一个 Skill。

## 运行要求

- Node.js 20 或更高版本，`node` 在 PATH 中（`.mcp.json` 用 `command: "node"`）。
- 无需 `npm install`，无构建步骤。

## 本地校验

```sh
npm run check   # node --check 三个脚本
npm run smoke   # 清单/frontmatter 检查 + 启动真实子进程跑 initialize、tools、resources、增改删与重启后读回
```

## 入口与界面

- 左侧「更多」菜单 → **任务看板**：全屏独立视图。
- 会话右侧应用菜单 → **任务看板**：可关闭的右侧标签页。

页面偏好 `preferredDisplayMode: "fullscreen"`，因此模型调用工具时卡片区只显示纯文本结果和「在独立视图中打开」，不会把看板挤进消息流。

页面内容：进度条文字 + 四项统计（含逾期）、搜索、阶段筛选、四列看板、新建/编辑对话框。刷新为手动按钮，不做自动轮询。写入操作（改阶段、编辑、删除、新建）都会用服务端返回的最新快照重绘。

「同步到对话」按钮只在宿主声明 `message` 能力时出现，且只把摘要填入输入框（`send: false`），不直接发送。

## 数据

默认 `~/.qoder-task-board/board.json`，可用 `QODER_TASK_BOARD_DIR` 改目录。写入先写临时文件再 `rename`，进程重启后数据保留。解析失败时原文件会被改名为 `board.json.corrupt-<时间戳>.json` 保留，不会在首次写入时覆盖。

## 验证状态

- `npm run check`、`npm run smoke` 在创建时已通过（协议、持久化、错误分支）。
- 页面在 Qoder 容器内的实际渲染、明暗主题、键盘操作尚未验证，需安装后按下面步骤自查。

## 安装后自查

1. 新会话中让模型调用 `open_task_board`，应出现工具结果与「在独立视图中打开」，而不是空白卡片。
2. 左侧「更多」→ 任务看板，应占满主区域；新建一条任务后关闭再打开，任务仍在。
3. 同一会话右侧菜单打开看板，对话保持可见；关闭右侧标签后主对话正常。
4. 切换明暗主题，无需刷新页面即变色；Tab 键可依次聚焦搜索框、筛选、卡片按钮。
5. 在页面改一次阶段后点「刷新」，状态应一致；断网/停止 Server 时页面给出可读错误，不自动重试写入。

## 卸载

在扩展视图中禁用或删除插件，然后按需删除数据目录 `~/.qoder-task-board`。
