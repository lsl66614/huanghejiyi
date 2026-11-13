// P1 大标题字图导出：headless Edge 透明底渲染 _headline.html，
// 按 #l1/#l2 包围盒分别裁剪输出 3x PNG，供 ArkTS Image 直接使用。
// 用法: node _headline_shot.cjs
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const PORT = 9339;
const DIR = __dirname;
const HTML = 'file:///' + encodeURI('E:/ .stepclaw/huanghe-memory/design/_headline.html').replace(/%20/g, '%20');
const W = 900, H = 480;

const edge = spawn(EDGE, [
  '--headless=new', `--remote-debugging-port=${PORT}`, '--no-first-run',
  `--user-data-dir=${DIR}\\_edge_profile_tmp`,
  `--window-size=${W},${H}`, '--disable-gpu', '--default-background-color=00000000', 'about:blank',
], { stdio: 'ignore' });

function get(p) { return fetch(`http://127.0.0.1:${PORT}${p}`).then(r => r.json()); }

async function main() {
  let targets;
  for (let i = 0; i < 100; i++) {
    try { targets = await get('/json/list'); if (targets && targets.length) break; } catch { /* retry */ }
    await new Promise(r => setTimeout(r, 300));
  }
  if (!targets || !targets.length) throw new Error('CDP /json/list empty');
  const page = targets.find(t => t.type === 'page' && t.webSocketDebuggerUrl) || targets.find(t => t.webSocketDebuggerUrl);
  if (!page) throw new Error('no CDP target: ' + JSON.stringify(targets.map(t => t.type)));
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise(r => ws.onopen = r);
  let id = 0;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  };
  const send = (method, params = {}) => new Promise(res => {
    const mid = ++id; pending.set(mid, res); ws.send(JSON.stringify({ id: mid, method, params }));
  });
  await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: 1, mobile: false });
  await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
  await send('Page.enable');
  await send('Page.navigate', { url: HTML });
  await new Promise(r => setTimeout(r, 1500));
  // 等字体就绪（子集 TTF 已含标题五字——App 正文语料自带）
  const fontOk = await send('Runtime.evaluate', {
    expression: `document.fonts.load("800 186px NSC","五千年都在土里").then(f=>f.length)`,
    awaitPromise: true, returnByValue: true,
  });
  console.log('fonts loaded:', fontOk.result?.result?.value);
  const box = await send('Runtime.evaluate', {
    expression: `JSON.stringify(['l1','l2'].map(i=>{const r=document.getElementById(i).getBoundingClientRect();return {x:r.x,y:r.y,w:r.width,h:r.height}}))`,
    returnByValue: true,
  });
  const rects = JSON.parse(box.result.result.value);
  const names = ['headline-5000.png', 'headline-tuli.png'];
  for (let i = 0; i < rects.length; i++) {
    const r = rects[i];
    const { result } = await send('Page.captureScreenshot', {
      format: 'png',
      clip: { x: r.x, y: r.y, width: r.w, height: r.h, scale: 3 },
    });
    fs.writeFileSync(path.join(DIR, names[i]), Buffer.from(result.data, 'base64'));
    console.log('saved', names[i], Math.round(r.w * 3) + 'x' + Math.round(r.h * 3));
  }
  ws.close(); edge.kill();
}
main().catch(e => { console.error(e); edge.kill(); process.exit(1); });
