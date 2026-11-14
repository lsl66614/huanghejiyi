import { cp, mkdir, readFile, stat, writeFile, readdir } from "node:fs/promises"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const source = join(here, "task-board")
const configDir = process.env.QODER_CONFIG_DIR || join(homedir(), ".qoder-cn")
const version = JSON.parse(await readFile(join(source, ".qoder-plugin/plugin.json"), "utf8")).version
const name = JSON.parse(await readFile(join(source, ".qoder-plugin/plugin.json"), "utf8")).name
const pluginId = `${name}@local`
const installPath = join(configDir, "plugins", "cache", "local", name, version)
const entryFile = join(configDir, "plugins", "installed_plugins_v2.json")
const settingsFile = join(configDir, "settings.json")

const entries = [".qoder-plugin", ".mcp.json", "package.json", "server.mjs", "app.html", "app.js", "README.md", "skills", "scripts"]

await mkdir(installPath, { recursive: true })
for (const entry of entries) {
  await cp(join(source, entry), join(installPath, entry), { recursive: true })
}

async function backup(file) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-")
  await cp(file, `${file}.bak-${stamp}`)
  return `${file}.bak-${stamp}`
}

const entryBackup = await backup(entryFile)
const settingsBackup = await backup(settingsFile)

const registry = JSON.parse(await readFile(entryFile, "utf8"))
registry.version = 2
registry.plugins ??= {}
registry.plugins[pluginId] = [{
  scope: "user",
  installPath,
  version,
  installedAt: new Date().toISOString(),
  displayName: "任务看板",
}]
await writeFile(entryFile, `${JSON.stringify(registry, null, 2)}\n`, "utf8")

const settings = JSON.parse(await readFile(settingsFile, "utf8"))
settings.enabledPlugins ??= {}
settings.enabledPlugins[pluginId] = true
await writeFile(settingsFile, `${JSON.stringify(settings, null, 2)}\n`, "utf8")

const installedFiles = (await readdir(installPath)).sort()
console.log(JSON.stringify({
  pluginId,
  installPath,
  version,
  entries,
  installedFiles,
  entryBackup,
  settingsBackup,
  registryEntry: registry.plugins[pluginId],
  enabled: settings.enabledPlugins[pluginId],
  serverExists: Boolean((await stat(join(installPath, "server.mjs"))).size),
}, null, 2))
