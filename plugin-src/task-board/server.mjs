import { readFile, writeFile, mkdir, rename } from "node:fs/promises"
import { homedir } from "node:os"
import { join } from "node:path"

const VERSION = "0.1.0"
const resourceUri = "ui://task-board/main.html"
const dataDir = process.env.QODER_TASK_BOARD_DIR || join(homedir(), ".qoder-task-board")
const dataFile = join(dataDir, "board.json")

const STAGES = ["backlog", "doing", "review", "done"]
const PRIORITIES = ["high", "normal", "low"]
const MAX_TASKS = 500

const pageScript = (await readFile(new URL("./app.js", import.meta.url), "utf8")).replaceAll("</script", "<\\/script")
const html = (await readFile(new URL("./app.html", import.meta.url), "utf8"))
  .replace("/* APP_SCRIPT */", () => pageScript)

const emptySchema = { type: "object", properties: {}, additionalProperties: false }

const boardIcon = {
  src: "data:image/svg+xml;base64," + Buffer.from(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="none" stroke="#8a8f98" stroke-width="1.33" stroke-linecap="round" stroke-linejoin="round"><rect x="2.7" y="3.3" width="14.6" height="13.4" rx="2.2"/><path d="M6.4 7.3h7.2M6.4 10.3h7.2M6.4 13.3h4.2"/></svg>',
  ).toString("base64"),
  mimeType: "image/svg+xml",
  sizes: ["20x20"],
}

const tools = [
  {
    name: "open_task_board",
    title: "任务看板",
    description: "打开任务看板独立视图，并读取当前全部任务与进度统计。查看或整理任务时使用。",
    inputSchema: emptySchema,
    annotations: { readOnlyHint: true },
    icons: [boardIcon],
    _meta: { ui: { resourceUri }, "qoder/ui": { entrypoints: [{ type: "global" }, { type: "thread" }] } },
  },
  {
    name: "list_tasks",
    title: "读取任务列表",
    description: "读取本地任务看板中的任务，可按阶段或关键词过滤。回答「还差什么」「进度如何」这类问题前先调用，不要凭记忆回答。",
    inputSchema: {
      type: "object",
      properties: {
        stage: { type: "string", enum: STAGES, description: "只返回该阶段的任务" },
        query: { type: "string", maxLength: 200, description: "标题或备注包含的关键词" },
        includeDone: { type: "boolean", description: "是否包含已完成任务，默认包含" },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: true },
  },
  {
    name: "upsert_task",
    title: "新建或更新任务",
    description: "不传 id 时新建任务（必须给 title）；传 id 时只更新给出的字段。返回更新后的完整看板，调用前无需再读一次。",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", maxLength: 64, description: "已有任务的 id，取自 list_tasks 结果" },
        title: { type: "string", minLength: 1, maxLength: 200 },
        notes: { type: "string", maxLength: 4000 },
        stage: { type: "string", enum: STAGES },
        priority: { type: "string", enum: PRIORITIES },
        due: { type: "string", maxLength: 10, pattern: "^(\\d{4}-\\d{2}-\\d{2})?$", description: "截止日期 YYYY-MM-DD，空字符串表示清除" },
      },
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
  },
  {
    name: "delete_task",
    title: "删除任务",
    description: "从看板删除一个任务。只能在看板页面中触发。",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", maxLength: 64 } },
      required: ["id"],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: true, idempotentHint: true },
    _meta: { ui: { visibility: ["app"] } },
  },
]

let board = { tasks: [] }
let loaded = false
let writeChain = Promise.resolve()

const isDate = value => typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value)
const isTask = task => Boolean(task) && typeof task === "object"
  && typeof task.id === "string" && task.id.length > 0
  && typeof task.title === "string" && task.title.trim().length > 0
  && STAGES.includes(task.stage) && PRIORITIES.includes(task.priority)

function normalize(task) {
  return {
    id: task.id,
    title: task.title.trim(),
    notes: typeof task.notes === "string" ? task.notes : "",
    stage: task.stage,
    priority: task.priority,
    due: isDate(task.due) ? task.due : "",
    createdAt: typeof task.createdAt === "string" ? task.createdAt : new Date().toISOString(),
    updatedAt: typeof task.updatedAt === "string" ? task.updatedAt : new Date().toISOString(),
  }
}

async function ensureLoaded() {
  if (loaded) return
  loaded = true
  let raw
  try {
    raw = await readFile(dataFile, "utf8")
  } catch (error) {
    if (error.code !== "ENOENT") process.stderr.write(`task-board: 无法读取 ${dataFile}: ${error.message}\n`)
    return
  }
  try {
    const parsed = JSON.parse(raw)
    if (Array.isArray(parsed?.tasks)) {
      board.tasks = parsed.tasks.filter(isTask).map(normalize).slice(0, MAX_TASKS)
    }
  } catch (error) {
    // 保留损坏文件，避免第一次写入就覆盖用户数据。
    const backup = `${dataFile}.corrupt-${Date.now()}.json`
    try { await rename(dataFile, backup) } catch {}
    process.stderr.write(`task-board: ${dataFile} 解析失败，已备份到 ${backup}\n`)
  }
}

async function persist() {
  const payload = JSON.stringify({ version: 1, tasks: board.tasks }, null, 2)
  writeChain = writeChain.catch(() => {}).then(async () => {
    await mkdir(dataDir, { recursive: true })
    const temp = `${dataFile}.${process.pid}.tmp`
    await writeFile(temp, payload, "utf8")
    await rename(temp, dataFile)
  })
  return writeChain
}

function localDate(date = new Date()) {
  const pad = value => String(value).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function statsOf(tasks) {
  const today = localDate()
  const counts = { backlog: 0, doing: 0, review: 0, done: 0 }
  let overdue = 0
  for (const task of tasks) {
    counts[task.stage] += 1
    if (task.stage !== "done" && isDate(task.due) && task.due < today) overdue += 1
  }
  const total = tasks.length
  return { total, ...counts, overdue, percent: total === 0 ? 0 : Math.round((counts.done / total) * 100) }
}

const stageLabel = { backlog: "待开始", doing: "进行中", review: "待验收", done: "已完成" }
const priorityLabel = { high: "高", normal: "中", low: "低" }

function summaryText(tasks, stats) {
  if (stats.total === 0) return "任务看板目前是空的。"
  const lines = [`任务看板：共 ${stats.total} 项，进行中 ${stats.doing} 项，待验收 ${stats.review} 项，已完成 ${stats.done} 项（${stats.percent}%）。`]
  if (stats.overdue > 0) lines.push(`其中 ${stats.overdue} 项已逾期。`)
  const open = tasks.filter(task => task.stage !== "done").slice(0, 6)
  if (open.length > 0) {
    lines.push("未完成的任务：")
    for (const task of open) {
      const due = task.due ? `（截止 ${task.due}）` : ""
      lines.push(`- [${stageLabel[task.stage]}] ${task.title}${due}`)
    }
  }
  return lines.join("\n")
}

function snapshot(tasks = board.tasks) {
  const stats = statsOf(tasks)
  return {
    content: [{ type: "text", text: summaryText(tasks, stats) }],
    structuredContent: { tasks: tasks.map(task => ({ ...task })), stats },
  }
}

const invalid = message => ({ isError: true, content: [{ type: "text", text: message }] })

function makeId() {
  return `t_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`
}

function filterTasks({ stage, query, includeDone = true }) {
  const needle = typeof query === "string" ? query.trim().toLowerCase() : ""
  return board.tasks.filter(task => {
    if (stage && task.stage !== stage) return false
    if (includeDone === false && task.stage === "done") return false
    if (!needle) return true
    return `${task.title}\n${task.notes}`.toLowerCase().includes(needle)
  })
}

async function upsert(args) {
  const id = typeof args.id === "string" ? args.id : undefined
  const fields = {}
  if (args.title !== undefined) {
    if (typeof args.title !== "string" || args.title.trim() === "" || args.title.length > 200) return invalid("title 必须是 1-200 个字符。")
    fields.title = args.title.trim()
  }
  if (args.notes !== undefined) {
    if (typeof args.notes !== "string" || args.notes.length > 4000) return invalid("notes 必须是不超过 4000 字符的字符串。")
    fields.notes = args.notes
  }
  if (args.stage !== undefined) {
    if (!STAGES.includes(args.stage)) return invalid(`stage 只能是 ${STAGES.join(" / ")}。`)
    fields.stage = args.stage
  }
  if (args.priority !== undefined) {
    if (!PRIORITIES.includes(args.priority)) return invalid(`priority 只能是 ${PRIORITIES.join(" / ")}。`)
    fields.priority = args.priority
  }
  if (args.due !== undefined) {
    if (args.due !== "" && !isDate(args.due)) return invalid("due 必须为空或 YYYY-MM-DD。")
    fields.due = args.due
  }

  const now = new Date().toISOString()
  if (id) {
    const task = board.tasks.find(item => item.id === id)
    if (!task) return invalid(`没有找到 id 为 ${id} 的任务。先用 list_tasks 读取最新列表。`)
    Object.assign(task, fields, { updatedAt: now })
    await persist()
    return snapshot()
  }

  if (!fields.title) return invalid("新建任务必须提供 title。")
  if (board.tasks.length >= MAX_TASKS) return invalid(`任务数已达上限 ${MAX_TASKS}，请先清理已完成任务。`)
  board.tasks.unshift(normalize({
    id: makeId(),
    title: fields.title,
    notes: fields.notes ?? "",
    stage: fields.stage ?? "backlog",
    priority: fields.priority ?? "normal",
    due: fields.due ?? "",
    createdAt: now,
    updatedAt: now,
  }))
  await persist()
  return snapshot()
}

async function remove(args) {
  if (typeof args.id !== "string" || args.id.length === 0) return invalid("必须提供任务 id。")
  const index = board.tasks.findIndex(task => task.id === args.id)
  if (index === -1) return invalid(`没有找到 id 为 ${args.id} 的任务。`)
  board.tasks.splice(index, 1)
  await persist()
  return snapshot()
}

const reply = message => process.stdout.write(`${JSON.stringify({ jsonrpc: "2.0", ...message })}\n`)

async function handleCall(name, args) {
  await ensureLoaded()
  if (name === "open_task_board") {
    if (Object.keys(args).length !== 0) return invalid("open_task_board 不接受参数。")
    return snapshot()
  }
  if (name === "list_tasks") {
    for (const key of Object.keys(args)) {
      if (!["stage", "query", "includeDone"].includes(key)) return invalid(`不支持的参数 ${key}。`)
    }
    if (args.stage !== undefined && !STAGES.includes(args.stage)) return invalid(`stage 只能是 ${STAGES.join(" / ")}。`)
    if (args.query !== undefined && typeof args.query !== "string") return invalid("query 必须是字符串。")
    if (args.includeDone !== undefined && typeof args.includeDone !== "boolean") return invalid("includeDone 必须是布尔值。")
    const tasks = filterTasks(args)
    const stats = statsOf(board.tasks)
    const filtered = snapshot(tasks)
    filtered.content = [{ type: "text", text: `${summaryText(tasks, statsOf(tasks))}\n（筛选自共 ${stats.total} 项）` }]
    return filtered
  }
  if (name === "upsert_task") return upsert(args)
  if (name === "delete_task") return remove(args)
  return invalid("未知工具。")
}

function handle(request) {
  if (!request || request.jsonrpc !== "2.0" || typeof request.method !== "string") {
    reply({ id: null, error: { code: -32600, message: "Invalid request" } })
    return
  }
  if (request.id === undefined) return
  if (typeof request.id !== "string" && typeof request.id !== "number") {
    reply({ id: null, error: { code: -32600, message: "Invalid request identifier" } })
    return
  }
  const { id, method } = request
  const params = request.params ?? {}
  const fail = (code, message) => reply({ id, error: { code, message } })
  if (!params || typeof params !== "object" || Array.isArray(params)) return fail(-32602, "Parameters must be an object")

  switch (method) {
    case "initialize":
      return reply({
        id,
        result: {
          protocolVersion: ["2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"].includes(params.protocolVersion)
            ? params.protocolVersion
            : "2025-11-25",
          capabilities: { tools: {}, resources: {} },
          serverInfo: { name: "task-board", version: VERSION },
        },
      })
    case "ping":
      return reply({ id, result: {} })
    case "tools/list":
      return reply({ id, result: { tools } })
    case "resources/list":
      return reply({
        id,
        result: { resources: [{ uri: resourceUri, name: "任务看板", mimeType: "text/html;profile=mcp-app" }] },
      })
    case "resources/read":
      if (params.uri !== resourceUri) return fail(-32602, "Resource not found")
      return reply({
        id,
        result: {
          contents: [{
            uri: resourceUri,
            mimeType: "text/html;profile=mcp-app",
            text: html,
            _meta: { "qoder/ui": { availableDisplayModes: ["fullscreen"], preferredDisplayMode: "fullscreen" } },
          }],
        },
      })
    case "tools/call": {
      const args = params.arguments ?? {}
      if (!args || typeof args !== "object" || Array.isArray(args)) return fail(-32602, "Tool arguments must be an object")
      if (typeof params.name !== "string") return fail(-32602, "Tool name is required")
      handleCall(params.name, args).then(
        result => reply({ id, result }),
        error => {
          process.stderr.write(`task-board: ${error?.message ?? error}\n`)
          reply({ id, result: invalid(`保存失败：${error?.message ?? "未知错误"}`) })
        },
      )
      return
    }
    default:
      return fail(-32601, "Method not supported")
  }
}

const maxLineBytes = 256 * 1024
let buffer = Buffer.alloc(0)
process.stdin.on("data", chunk => {
  buffer = Buffer.concat([buffer, chunk])
  let end
  while ((end = buffer.indexOf(10)) !== -1) {
    const line = buffer.subarray(0, end)
    buffer = buffer.subarray(end + 1)
    if (line.length > maxLineBytes) {
      process.stderr.write("task-board: 请求超出大小限制\n")
      process.exit(1)
    }
    const text = line.toString("utf8").trim()
    if (!text) continue
    try {
      handle(JSON.parse(text))
    } catch {
      reply({ id: null, error: { code: -32700, message: "Invalid JSON" } })
    }
  }
  if (buffer.length > maxLineBytes) {
    process.stderr.write("task-board: 请求超出大小限制\n")
    process.exit(1)
  }
})
