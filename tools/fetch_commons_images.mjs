// tools/fetch_commons_images.mjs
// 从 Wikimedia Commons 拉取实拍图，落到 rawfile/images/<site>/real_*.webp。
//
// 口径（见 docs/IMAGES.md）：
//   · 只取 real_ 前缀，UI 的 ImagePolicy 只渲染 real_ 图；
//   · 只用公开许可（CC0 / CC BY / CC BY-SA），逐条记录作者与许可；
//   · 长边 1280，WebP q78，单图控制在 200KB 内；
//   · 清单在 tools/commons_manifest.json，来源与许可写进台账。
//
// 用法：node tools/fetch_commons_images.mjs [--dry-run] [--only <siteId>]
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const MANIFEST = join(ROOT, 'tools/commons_manifest.json');
const IMG_ROOT = join(ROOT, 'app/entry/src/main/resources/rawfile/images');
const FFMPEG = 'C:/tools-setup/ffmpeg/bin/ffmpeg.exe';

const argv = process.argv.slice(2);
const dryRun = argv.includes('--dry-run');
const onlyIdx = argv.indexOf('--only');
const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : '';

const manifest = JSON.parse(readFileSync(MANIFEST, 'utf8'));
const items = manifest.items.filter((it) => (only ? it.site === only : true));

// Commons 的 thumb URL 走 upload.wikimedia.org 缩略图端点，宽度固定 1280。
function thumbUrl(file, width) {
  const enc = file.split('/').map(encodeURIComponent).join('/');
  return `https://upload.wikimedia.org/wikipedia/commons/thumb/${enc}/${width}px-${enc}`;
}

async function fetchOne(it) {
  const outDir = join(IMG_ROOT, it.site);
  const outFile = join(outDir, `${it.name}.webp`);
  if (existsSync(outFile) && !dryRun) {
    return { ...it, status: 'skip-exists' };
  }
  const url = thumbUrl(it.file, 1280);
  const res = await fetch(url, { headers: { 'User-Agent': 'huanghe-memory/1.0 (educational project)' } });
  if (!res.ok) {
    return { ...it, status: 'http-' + res.status };
  }
  const buf = Buffer.from(await res.arrayBuffer());
  if (!dryRun) {
    mkdirSync(outDir, { recursive: true });
    const tmp = join(outDir, `_tmp_${it.name}.jpg`);
    writeFileSync(tmp, buf);
    execFileSync(FFMPEG, [
      '-y', '-loglevel', 'error', '-i', tmp,
      '-vf', 'scale=1280:-2', '-c:v', 'libwebp', '-quality', '78',
      outFile
    ]);
  }
  return { ...it, status: dryRun ? 'dry-run' : 'ok', bytes: buf.length };
}

const results = [];
for (const it of items) {
  try {
    results.push(await fetchOne(it));
  } catch (e) {
    results.push({ ...it, status: 'error', message: String(e && e.message ? e.message : e) });
  }
  const r = results[results.length - 1];
  console.log(`${r.status.padEnd(12)} ${r.site}/${r.name}  <- ${r.file}`);
}

const failed = results.filter((r) => r.status !== 'ok' && r.status !== 'skip-exists' && r.status !== 'dry-run');
console.log(`\n共 ${results.length} 条：成功 ${results.filter((r) => r.status === 'ok' || r.status === 'skip-exists').length}，失败 ${failed.length}`);
if (failed.length) {
  console.log('失败清单：');
  for (const f of failed) console.log('  ' + f.site + '/' + f.name + '  ' + f.status + '  ' + (f.message || ''));
}
