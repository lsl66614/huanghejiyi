import assert from "node:assert/strict"
import { spawn } from "node:child_process"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { homedir, tmpdir } from "node:os"
import { join } from "node:path"

const configDir = join(homedir(), ".qoder-cn")
const installPath = join(configDir, "plugins", "cache", "local", "task-board", "0.1.0")
const dataDir = await mkdtemp(join(tmpdir(), "task-board-verify-"))

const registry = JSON.parse(await readFile(join(configDir, "plugins", "installed_plugins_v2.json"), "utf8"))
const settings = JSON.parse(await readFile(join(configDir, "settings.json"), "utf8"))
const entry = registry.plugins["task-board@local"]
assert.ok(Array.isArray(entry) && entry.length === 1)
assert.equal(entry[0].installPath, installPath)
assert.equal(entry[0].version, "0.1.0")
assert.equal(entry[0].scope, "user")
assert.equal(settings.enabledPlugins["task-board@local"], true)

const installedApp = await readFile(join(installPath, "app.js"), "utf8")
assert.ok(installedApp.includes('node[key.toLowerCase()] = value'), "安装副本应包含事件绑定修复")

const child = spawn(process.execPath, [join(installPath, "server.mjs")], {
  env: { ...process.env, QODER_TASK_BOARD_DIR: dataDir },
  stdio: ["pipe", "pipe", "inherit"],
})
let buffer = ""
let seq = 0
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
    if (settle) {
      waiting.delete(message.id)
      settle(message)
    }
  }
})
const call = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++seq
  const timer = setTimeout(() => reject(new Error(`超时 ${method}`)), 8000)
  waiting.set(id, message => {
    clearTimeout(timer)
    if (message.error) reject(new Error(`${method}: ${message.error.message}`))
    else resolve(message.result)
  })
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, params })}\n`)
})

try {
  const init = await call("initialize", { protocolVersion: "2025-11-25", capabilities: {} })
  const list = await call("tools/list")
  const page = (await call("resources/read", { uri: "ui://task-board/main.html" })).contents[0]
  const created = await call("tools/call", { name: "upsert_task", arguments: { title: "安装验证任务" } })
  const snapshot = await call("tools/call", { name: "open_task_board", arguments: {} })

  console.log(JSON.stringify({
    pluginId: "task-board@local",
    enabled: settings.enabledPlugins["task-board@local"],
    registeredPlugins: Object.keys(registry.plugins).length,
    enabledPlugins: Object.keys(settings.enabledPlugins).length,
    server: init.serverInfo,
    tools: list.tools.map(tool => tool.name),
    entrypoints: list.tools.find(tool => tool.name === "open_task_board")._meta["qoder/ui"].entrypoints,
    pageBytes: page.text.length,
    pageInjected: page.text.includes("ui/initialize") && !page.text.includes("/* APP_SCRIPT */"),
    created: created.structuredContent.stats.total,
    reopened: snapshot.structuredContent.stats.total,
    skillInstalled: await readFile(join(installPath, "skills/task-board/SKILL.md"), "utf8").then(text => text.includes("name: task-board")),
  }, null, 2))
} finally {
  child.kill()
  await rm(dataDir, { recursive: true, force: true })
}
