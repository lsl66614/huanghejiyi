// 页面消息边界：只接受父容器消息；初始化后再按宿主声明能力开放操作。
const STAGES = [
  { id: "backlog", label: "待开始" },
  { id: "doing", label: "进行中" },
  { id: "review", label: "待验收" },
  { id: "done", label: "已完成" },
]
const STAGE_LABEL = Object.fromEntries(STAGES.map(stage => [stage.id, stage.label]))
const PRIORITY_LABEL = { high: "高", normal: "中", low: "低" }

const $ = selector => document.querySelector(selector)
const progress = $("#progress")
const statsBox = $("#stats")
const filters = $("#filters")
const board = $("#board")
const status = $("#status")
const queryInput = $("#query")
const showDoneInput = $("#show-done")
const refreshButton = $("#refresh")
const newButton = $("#new")
const sendButton = $("#send")
const editor = $("#editor")
const form = $("#form")
const editorTitle = $("#editor-title")
const titleInput = $("#f-title")
const notesInput = $("#f-notes")
const stageInput = $("#f-stage")
const priorityInput = $("#f-priority")
const dueInput = $("#f-due")
const cancelButton = $("#cancel")
const saveButton = $("#save")

const pending = new Map()
let sequence = 0
let ready = false
let closed = false
let busy = false
let caps = {}
let tasks = []
let stats = null
let filter = "all"
let query = ""
let confirmDeleteId = null
let confirmTimer = 0
let editingId = null
let context = {}

const request = (method, params, timeout = 20000) => {
  if (closed || pending.size >= 8) return Promise.reject(new Error("页面已关闭或繁忙，请重新打开任务看板。"))
  const id = `task-board-${++sequence}`
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id)
      reject(new Error("结果未确认，请点「刷新」核对后再操作。"))
    }, timeout)
    pending.set(id, { resolve, reject, timer })
    try {
      window.parent.postMessage({ jsonrpc: "2.0", id, method, params }, "*")
    } catch {
      clearTimeout(timer)
      pending.delete(id)
      reject(new Error("无法连接宿主，请重新打开任务看板。"))
    }
  })
}

function setStatus(text, error = false) {
  status.textContent = text
  status.dataset.error = String(error)
}

function syncControls() {
  const blocked = closed || !ready || busy
  newButton.disabled = blocked
  refreshButton.disabled = blocked
  sendButton.disabled = blocked || tasks.length === 0
  saveButton.disabled = blocked
  for (const control of board.querySelectorAll("button, select")) control.disabled = blocked
}

function localTime(value) {
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ""
  const pad = input => String(input).padStart(2, "0")
  return `${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

function today() {
  const date = new Date()
  const pad = input => String(input).padStart(2, "0")
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
}

const isOverdue = task => task.stage !== "done" && /^\d{4}-\d{2}-\d{2}$/.test(task.due) && task.due < today()

function el(tag, props = {}, children = []) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value
    else if (key === "text") node.textContent = value
    else if (key.startsWith("on") && typeof value === "function") node[key.toLowerCase()] = value
    else if (key in node) node[key] = value
    else node.setAttribute(key, value)
  }
  for (const child of [].concat(children)) {
    if (child === null || child === undefined || child === false) continue
    node.append(child)
  }
  return node
}

function matchesQuery(task) {
  if (!query) return true
  return `${task.title}\n${task.notes}`.toLowerCase().includes(query)
}

function renderStats() {
  statsBox.replaceChildren()
  if (!stats) return
  const items = [
    { label: "待开始", value: stats.backlog },
    { label: "进行中", value: stats.doing },
    { label: "待验收", value: stats.review },
    { label: "已完成", value: stats.done },
    { label: "逾期", value: stats.overdue, warn: stats.overdue > 0 },
  ]
  for (const item of items) {
    statsBox.append(el("div", { class: item.warn ? "stat warn" : "stat" }, [
      el("b", { text: String(item.value ?? 0) }),
      el("span", { text: item.label }),
    ]))
  }
}

function renderFilters() {
  const options = [{ id: "all", label: "全部" }, ...STAGES]
  filters.replaceChildren()
  for (const option of options) {
    filters.append(el("button", {
      type: "button",
      class: "chip",
      text: option.label,
      "aria-pressed": String(filter === option.id),
      onClick: () => {
        filter = option.id
        if (option.id === "done") showDoneInput.checked = true
        render()
      },
    }))
  }
}

function buildCard(task) {
  const card = el("article", { class: "card" })
  card.append(el("div", { class: "card-title", text: task.title }))
  if (task.notes) card.append(el("div", { class: "card-notes", text: task.notes }))

  const meta = el("div", { class: "meta" })
  if (task.priority === "high") meta.append(el("span", { class: "tag high", text: "高优先级" }))
  else if (task.priority === "low") meta.append(el("span", { class: "tag", text: "低优先级" }))
  if (task.due) {
    meta.append(el("span", {
      class: isOverdue(task) ? "tag due-over" : "tag",
      text: `${isOverdue(task) ? "已逾期 " : "截止 "}${task.due}`,
    }))
  }
  if (task.stage === "done" && task.updatedAt) meta.append(el("span", { text: `完成于 ${localTime(task.updatedAt)}` }))
  if (meta.childNodes.length > 0) card.append(meta)

  const actions = el("div", { class: "card-actions" })

  const select = el("select", { name: "stage", "aria-label": `移动「${task.title}」到其他阶段` })
  for (const stage of STAGES) {
    select.append(el("option", { value: stage.id, text: stage.label, selected: stage.id === task.stage }))
  }
  select.addEventListener("change", () => {
    const nextStage = select.value
    if (nextStage === task.stage) return
    void mutate("upsert_task", { id: task.id, stage: nextStage }, `已移到「${STAGE_LABEL[nextStage]}」`)
  })
  actions.append(select)

  actions.append(el("button", { type: "button", text: "编辑", onClick: () => openEditor(task) }))

  const deleting = confirmDeleteId === task.id
  actions.append(el("button", {
    type: "button",
    class: deleting ? "danger confirm" : "danger",
    text: deleting ? "确认删除" : "删除",
    onClick: () => confirmAndDelete(task.id),
  }))

  card.append(actions)
  return card
}

function renderBoard() {
  board.replaceChildren()
  const visibleStages = filter === "all" ? STAGES.filter(stage => stage.id !== "done" || showDoneInput.checked) : STAGES.filter(stage => stage.id === filter)
  const visibleTasks = tasks.filter(matchesQuery)

  if (tasks.length === 0) {
    board.append(el("div", { class: "empty" }, [
      el("p", { text: "看板还是空的。建一个任务，用阶段推进它。" }),
      el("button", { type: "button", class: "primary", text: "新建第一个任务", onClick: () => openEditor(null) }),
    ]))
    return
  }

  for (const stage of visibleStages) {
    const list = visibleTasks.filter(task => task.stage === stage.id)
    const column = el("section", { class: "column", "aria-label": stage.label }, [
      el("div", { class: "column-head" }, [
        el("h2", { text: stage.label }),
        el("span", { class: "count", text: `${list.length} 项` }),
      ]),
    ])
    if (list.length === 0) column.append(el("p", { class: "column-empty", text: query ? "没有匹配的任务" : "暂无任务" }))
    for (const task of list) column.append(buildCard(task))
    board.append(column)
  }

  if (visibleStages.length === 0) board.append(el("div", { class: "empty" }, [el("p", { text: "勾选「显示已完成」查看已完成任务。" })]))
}

function renderProgress() {
  if (!stats) {
    progress.textContent = "还没有数据"
    return
  }
  if (stats.total === 0) {
    progress.textContent = "看板为空 · 新建任务开始推进"
    return
  }
  const parts = [`已完成 ${stats.done} / ${stats.total}（${stats.percent}%）`]
  if (stats.overdue > 0) parts.push(`逾期 ${stats.overdue} 项`)
  if (stats.doing > 0) parts.push(`进行中 ${stats.doing} 项`)
  progress.textContent = parts.join(" · ")
}

function render() {
  renderProgress()
  renderStats()
  renderFilters()
  renderBoard()
  syncControls()
}

function applyResult(result) {
  const next = result?.structuredContent
  if (!next || !Array.isArray(next.tasks) || !next.stats) throw new Error("读到的看板数据不完整，请点「刷新」重试。")
  tasks = next.tasks
  stats = next.stats
  render()
}

async function mutate(name, args, okText) {
  if (!ready || busy || closed) return
  busy = true
  syncControls()
  setStatus("正在保存…")
  try {
    const result = await request("tools/call", { name, arguments: args })
    if (closed) return
    if (result?.isError) throw new Error(result.content?.[0]?.text || "操作没有完成。")
    applyResult(result)
    confirmDeleteId = null
    clearTimeout(confirmTimer)
    setStatus(okText)
  } catch (error) {
    if (!closed) setStatus(error.message, true)
  } finally {
    busy = false
    syncControls()
  }
}

function confirmAndDelete(id) {
  if (confirmDeleteId !== id) {
    confirmDeleteId = id
    clearTimeout(confirmTimer)
    confirmTimer = setTimeout(() => {
      confirmDeleteId = null
      renderBoard()
      syncControls()
    }, 4000)
    renderBoard()
    syncControls()
    setStatus("再点一次「确认删除」移除该任务。")
    return
  }
  confirmDeleteId = null
  clearTimeout(confirmTimer)
  void mutate("delete_task", { id }, "任务已删除")
}

function openEditor(task) {
  editingId = task ? task.id : null
  editorTitle.textContent = task ? "编辑任务" : "新建任务"
  titleInput.value = task ? task.title : ""
  notesInput.value = task ? task.notes : ""
  stageInput.value = task ? task.stage : "backlog"
  priorityInput.value = task ? task.priority : "normal"
  dueInput.value = task && /^\d{4}-\d{2}-\d{2}$/.test(task.due) ? task.due : ""
  editor.showModal()
  titleInput.focus()
}

async function saveTask(event) {
  event.preventDefault()
  const title = titleInput.value.trim()
  if (!title) {
    titleInput.focus()
    setStatus("标题不能为空。", true)
    return
  }
  const args = {
    title,
    notes: notesInput.value.trim(),
    stage: stageInput.value,
    priority: priorityInput.value,
    due: dueInput.value,
  }
  if (editingId) args.id = editingId
  const okText = editingId ? "任务已更新" : "任务已创建"
  editor.close()
  await mutate("upsert_task", args, okText)
}

function boardSummary() {
  const lines = [`任务看板（${today()}）：共 ${stats.total} 项，进行中 ${stats.doing} 项，待验收 ${stats.review} 项，已完成 ${stats.done} 项（${stats.percent}%）。`]
  if (stats.overdue > 0) lines.push(`逾期 ${stats.overdue} 项。`)
  const open = tasks.filter(task => task.stage !== "done")
  if (open.length > 0) {
    lines.push("", "未完成：")
    for (const task of open) {
      const kind = task.priority === "high" ? "高优先级" : PRIORITY_LABEL[task.priority]
      const due = task.due ? `，截止 ${task.due}${isOverdue(task) ? "（已逾期）" : ""}` : ""
      lines.push(`- [${STAGE_LABEL[task.stage]}] ${task.title}（${kind}${due}）`)
    }
  }
  return lines.join("\n")
}

async function sendToChat() {
  if (busy || closed || pending.size >= 8) return
  busy = true
  syncControls()
  setStatus("正在填入输入框…")
  try {
    await request("ui/message", {
      role: "user",
      content: [{ type: "text", text: `${boardSummary()}\n\n请基于这份看板帮我排一下接下来先做什么。` }],
      _meta: { "qoder/message": { send: false } },
    }, 30000)
    if (!closed) setStatus("已填入输入框，确认后发送。")
  } catch (error) {
    if (!closed) setStatus(`${error.message} 请到对话窗口确认。`, true)
  } finally {
    busy = false
    syncControls()
  }
}

async function refresh() {
  if (!ready || busy || closed) return
  await mutate("open_task_board", {}, "已同步")
}

function applyHostContext(value) {
  context = { ...context, ...value }
  if (context.theme === "light" || context.theme === "dark") document.documentElement.dataset.theme = context.theme
}

function receive(event) {
  if (event.source !== window.parent || closed) return
  const message = event.data
  if (!message || typeof message !== "object" || message.jsonrpc !== "2.0") return

  if (!message.method && pending.has(message.id)) {
    const task = pending.get(message.id)
    if (!("error" in message) && !("result" in message)) return
    pending.delete(message.id)
    clearTimeout(task.timer)
    if (message.error) task.reject(new Error("宿主没有完成这次操作，请刷新确认。"))
    else task.resolve(message.result)
    return
  }

  if (message.method === "ui/notifications/tool-result") {
    try {
      applyResult(message.params)
      if (!ready) setStatus("已载入看板")
    } catch (error) {
      setStatus(error.message, true)
    }
    return
  }
  if (message.method === "ui/notifications/host-context-changed") {
    applyHostContext(message.params ?? {})
    return
  }
  if (message.method === "ui/notifications/tool-cancelled") {
    setStatus("操作已取消，可以点「刷新」查看最新状态。")
    return
  }
  if (message.id !== undefined) {
    if (message.method === "ping") {
      window.parent.postMessage({ jsonrpc: "2.0", id: message.id, result: {} }, "*")
    } else if (message.method === "ui/resource-teardown") {
      window.parent.postMessage({ jsonrpc: "2.0", id: message.id, result: {} }, "*")
      dispose()
    } else {
      window.parent.postMessage({ jsonrpc: "2.0", id: message.id, error: { code: -32601, message: "Method not supported" } }, "*")
    }
  }
}

function dispose() {
  if (closed) return
  closed = true
  clearTimeout(confirmTimer)
  for (const task of pending.values()) {
    clearTimeout(task.timer)
    task.reject(new Error("任务看板已关闭。"))
  }
  pending.clear()
  window.removeEventListener("message", receive)
  window.removeEventListener("pagehide", dispose)
  queryInput.removeEventListener("input", onQueryInput)
  showDoneInput.removeEventListener("change", onShowDone)
  refreshButton.removeEventListener("click", refresh)
  newButton.removeEventListener("click", onNew)
  sendButton.removeEventListener("click", sendToChat)
  cancelButton.removeEventListener("click", onCancel)
  form.removeEventListener("submit", saveTask)
  syncControls()
  setStatus("任务看板已关闭")
}

const onQueryInput = () => {
  query = queryInput.value.trim().toLowerCase()
  renderBoard()
  syncControls()
}
const onShowDone = () => {
  render()
}
const onNew = () => openEditor(null)
const onCancel = () => editor.close()

queryInput.addEventListener("input", onQueryInput)
showDoneInput.addEventListener("change", onShowDone)
refreshButton.addEventListener("click", refresh)
newButton.addEventListener("click", onNew)
sendButton.addEventListener("click", sendToChat)
cancelButton.addEventListener("click", onCancel)
form.addEventListener("submit", saveTask)
window.addEventListener("message", receive)
window.addEventListener("pagehide", dispose)

if (window.parent === window) {
  setStatus("请在 Qoder 中打开这个插件；直接打开 HTML 不会连接宿主。", true)
} else {
  render()
  request("ui/initialize", {
    protocolVersion: "2026-01-26",
    appInfo: { name: "task-board", version: "0.1.0" },
    appCapabilities: { availableDisplayModes: ["fullscreen"] },
  }).then(result => {
    if (closed) return
    if (result?.protocolVersion !== "2026-01-26") throw new Error("宿主协议版本不匹配，请更新 Qoder。")
    caps = result.hostCapabilities ?? {}
    ready = Boolean(caps.serverTools)
    applyHostContext(result.hostContext ?? {})
    sendButton.hidden = !(caps.message || caps.experimental?.["qoder/message"])
    window.parent.postMessage({ jsonrpc: "2.0", method: "ui/notifications/initialized", params: {} }, "*")
    setStatus(ready ? "已连接，可新建或调整任务" : "此宿主不允许页面调用工具，看板只读。")
    render()
  }).catch(error => {
    if (!closed) setStatus(error.message, true)
  })
}
