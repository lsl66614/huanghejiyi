import { createServer } from "node:http"
import { readFile } from "node:fs/promises"
import { dirname, extname, join } from "node:path"
import { fileURLToPath } from "node:url"

const here = dirname(fileURLToPath(import.meta.url))
const pluginDir = join(here, "..", "task-board")
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".json": "application/json; charset=utf-8" }

const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://127.0.0.1")
  if (url.pathname === "/" || url.pathname === "/host.html") {
    const body = await readFile(join(here, "host.html"))
    response.writeHead(200, { "content-type": types[".html"], "cache-control": "no-store" })
    response.end(body)
    return
  }
  if (url.pathname === "/app.html") {
    // 与 server.mjs 一致：把 app.js 内联进页面。
    const script = (await readFile(join(pluginDir, "app.js"), "utf8")).replaceAll("</script", "<\\/script")
    const page = (await readFile(join(pluginDir, "app.html"), "utf8")).replace("/* APP_SCRIPT */", () => script)
    response.writeHead(200, { "content-type": types[".html"], "cache-control": "no-store" })
    response.end(page)
    return
  }
  const file = join(pluginDir, url.pathname === "/app.js" ? "app.js" : "missing")
  try {
    const body = await readFile(file)
    response.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream", "cache-control": "no-store" })
    response.end(body)
  } catch {
    response.writeHead(404, { "content-type": "text/plain; charset=utf-8" })
    response.end("not found")
  }
})

const port = Number(process.env.PREVIEW_PORT || 8799)
server.listen(port, "127.0.0.1", () => console.log(`preview http://127.0.0.1:${port}/?theme=${process.env.PREVIEW_THEME || "light"}`))
