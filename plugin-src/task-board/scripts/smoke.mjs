import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const dataDir = await mkdtemp(join(root, ".smoke-data-"))
const results = []
const record = name => results.push(name)

async function checkStatic() {
  const manifest = JSON.parse(await readFile(join(root, ".qoder-plugin/plugin.json"), "utf8"))
  assert.equal(manifest.name, "task-board")
  assert.match(manifest.version, /^\d+\.\d+\.\d+$/)
  assert.ok(manifest.description && manifest.keywords.includes("qoder-plugin"))

  const mcp = JSON.parse(await readFile(join(root, ".mcp.json"), "utf8"))
  assert.ok(mcp.mcpServers?.["task-board"]?.command)
  assert.deepEqual(mcp.mcpServers["task-board"].args, ["${QODER_PLUGIN_ROOT}/server.mjs"])

  const skill = await readFile(join(root, "skills/task-board/SKILL.md"), "utf8")
  const frontmatter = skill.match(/^---\n([\s\S]*?)\n---\n/)
  assert.ok(frontmatter, "SKILL.md 缺少 frontmatter")
  assert.match(frontmatter[1], /^name: task-board$/m)
  assert.match(frontmatter[1], /^description: .+/m)

  const html = await readFile(join(root, "app.html"), "utf8")
  assert.ok(html.includes("/* APP_SCRIPT */"))
  record("静态检查")
}

function startServer() {
  const child = spawn(process.execPath, [join(root, "server.mjs")], {
    env: { ...process.env, QODER_TASK_BOARD_DIR: dataDir },
    stdio: ["pipe", "pipe", "pipe"],
  })
  let buffer = ""
  let sequence = 0
  const waiting = new Map()
  child.stdout.setEncoding("utf8")
  child.stdout.on("data", chunk => {
    buffer += chunk
    let end
    while ((end = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, end)
      buffer = buffer.slice(end + 1)
      if (!line.trim()) continue
      const message = JSON.parse(line)
      const settle = waiting.get(message.id)
      if (!settle) continue
      waiting.delete(message.id)
      settle(message)
    }
  })
  child.stderr.setEncoding("utf8")
  child.stderr.on("data", chunk => process.stderr.write(`[server] ${chunk}`))
  const call = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++sequence
    const timer = setTimeout(() => {
      waiting.delete(id)
      reject(new Error(`超时：${method}`))
    }, 8000)
    waiting.set(id, message => {
      clearTimeout(timer)
      if (message.error) reject(new Error(`${method}: ${message.error.message}`))
      else resolve(message.result)
    })
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`)
  })
  return { child, call, stop: () => new Promise(resolve => { child.once("exit", resolve); child.kill() }) }
}

async function checkProtocol() {
  let server = startServer()
  try {
    const init = await server.call("initialize", { protocolVersion: "2025-11-25", capabilities: {} })
    assert.equal(init.serverInfo.name, "task-board")
    assert.ok(init.capabilities.tools && init.capabilities.resources)

    const list = await server.call("tools/list")
    const byName = Object.fromEntries(list.tools.map(tool => [tool.name, tool]))
    assert.deepEqual(Object.keys(byName).sort(), ["delete_task", "list_tasks", "open_task_board", "upsert_task"])
    assert.equal(byName.open_task_board._meta.ui.resourceUri, "ui://task-board/main.html")
    assert.deepEqual(byName.open_task_board._meta["qoder/ui"].entrypoints, [{ type: "global" }, { type: "thread" }])
    assert.deepEqual(byName.delete_task._meta.ui.visibility, ["app"])
    assert.equal(byName.delete_task.annotations.destructiveHint, true)
    assert.equal(byName.list_tasks.annotations.readOnlyHint, true)

    const resource = await server.call("resources/read", { uri: "ui://task-board/main.html" })
    const page = resource.contents[0]
    assert.equal(page.mimeType, "text/html;profile=mcp-app")
    assert.deepEqual(page._meta["qoder/ui"], { availableDisplayModes: ["fullscreen"], preferredDisplayMode: "fullscreen" })
    assert.ok(page.text.includes("<main>") && page.text.includes("ui/initialize"))
    assert.ok(!page.text.includes("/* APP_SCRIPT */"))

    const empty = await server.call("tools/call", { name: "open_task_board", arguments: {} })
    assert.equal(empty.structuredContent.stats.total, 0)

    const created = await server.call("tools/call", { name: "upsert_task", arguments: { title: "冒烟任务", notes: "验证持久化", priority: "high" } })
    assert.equal(created.structuredContent.stats.backlog, 1)
    const id = created.structuredContent.tasks[0].id
    assert.ok(id)

    const moved = await server.call("tools/call", { name: "upsert_task", arguments: { id, stage: "done" } })
    assert.equal(moved.structuredContent.stats.done, 1)
    assert.equal(moved.structuredContent.stats.backlog, 0)

    const filtered = await server.call("tools/call", { name: "list_tasks", arguments: { stage: "done" } })
    assert.equal(filtered.structuredContent.tasks.length, 1)
    const missed = await server.call("tools/call", { name: "list_tasks", arguments: { query: "不存在的关键词" } })
    assert.equal(missed.structuredContent.tasks.length, 0)
    const hiddenDone = await server.call("tools/call", { name: "list_tasks", arguments: { includeDone: false } })
    assert.equal(hiddenDone.structuredContent.tasks.length, 0)

    const badCreate = await server.call("tools/call", { name: "upsert_task", arguments: { notes: "没有标题" } })
    assert.equal(badCreate.isError, true)
    const badStage = await server.call("tools/call", { name: "upsert_task", arguments: { id, stage: "archived" } })
    assert.equal(badStage.isError, true)
    const unknownId = await server.call("tools/call", { name: "upsert_task", arguments: { id: "t_missing", stage: "doing" } })
    assert.equal(unknownId.isError, true)

    const badResource = await server.call("resources/read", { uri: "ui://task-board/other.html" }).then(() => false, () => true)
    assert.equal(badResource, true)

    await server.stop()
    server = startServer()
    const reopened = await server.call("tools/call", { name: "open_task_board", arguments: {} })
    assert.equal(reopened.structuredContent.stats.total, 1, "重启后应读回已保存任务")
    assert.equal(reopened.structuredContent.tasks[0].title, "冒烟任务")

    const deleted = await server.call("tools/call", { name: "delete_task", arguments: { id } })
    assert.equal(deleted.structuredContent.stats.total, 0)
    record("协议与持久化")
  } finally {
    await server.stop()
  }
}

try {
  await checkStatic()
  await checkProtocol()
  console.log(`smoke 通过：${results.join("、")}`)
  console.log(`数据目录 ${dataDir} 将在清理后删除`)
} finally {
  await rm(dataDir, { recursive: true, force: true })
}
