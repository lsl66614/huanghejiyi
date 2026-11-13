// 生成"夯层"土层纹理 PNG（纯 Node，无依赖）。
// 用途：1) P1 大标题字身填充（earth 模式，design/_headline.html 引用）
//       2) 备用同色系暗纹（light 模式，白色低透明层带，可叠任意年代色）
// 用法: node tools/gen_strata_texture.cjs <输出.png> <模式 earth|light> [宽] [高]
// 约定：层带高 30-80px、边界左右波动 ±8px、逐像素 ±5 明度噪点、0.4% 深色斑点。
// 注：.cjs 后缀用于绕开工作区根 package.json 的 "type": "module"（ESM 污染，同 build-oh.bat）。
const zlib = require('zlib');
const fs = require('fs');

const out = process.argv[2];
const mode = process.argv[3] || 'earth';
const W = Number(process.argv[4] || 1600);
const H = Number(process.argv[5] || 512);

function hex(c) {
  return [parseInt(c.slice(1, 3), 16), parseInt(c.slice(3, 5), 16), parseInt(c.slice(5, 7), 16)];
}
function rnd(a, b) { return a + Math.random() * (b - a); }

// earth：土层本色（上浅下深再交错，取自六年代色系）；light：纯白低透明
const PALETTE_EARTH = ['#B98A44', '#8E4028', '#6E4A2B', '#332E29', '#8E4028', '#4E3B2A', '#B98A44', '#332E29', '#7A3A20', '#8E4028'].map(hex);

// 层带边界：随机高度 + 每列正弦+随机相位的水平波动
const boundaries = [];
let y = 0;
while (y < H) {
  y += rnd(30, 80);
  boundaries.push(Math.min(y, H));
}
const wave = boundaries.map(() => ({ amp: rnd(3, 8), freq: rnd(0.004, 0.012), phase: rnd(0, Math.PI * 2) }));

const raw = Buffer.alloc(H * (1 + W * 4));
let p = 0;
for (let py = 0; py < H; py++) {
  raw[p++] = 0; // filter: none
  for (let px = 0; px < W; px++) {
    let band = 0;
    for (let b = 0; b < boundaries.length; b++) {
      const by = boundaries[b] + wave[b].amp * Math.sin(wave[b].freq * px + wave[b].phase);
      if (py < by) { band = b; break; }
      band = b;
    }
    let r, g, bl, a;
    if (mode === 'earth') {
      const c = PALETTE_EARTH[band % PALETTE_EARTH.length];
      const n = rnd(-5, 5);
      r = Math.max(0, Math.min(255, c[0] + n));
      g = Math.max(0, Math.min(255, c[1] + n));
      bl = Math.max(0, Math.min(255, c[2] + n));
      a = 255;
      if (Math.random() < 0.004) { r = Math.max(0, r - 40); g = Math.max(0, g - 40); bl = Math.max(0, bl - 40); }
    } else {
      a = 26 + rnd(-6, 8); // 白色 ~10% 上下
      r = 245; g = 239; bl = 226; // #F5EFE2
      if (Math.random() < 0.03) a = 40 + rnd(0, 20);
    }
    raw[p++] = r; raw[p++] = g; raw[p++] = bl; raw[p++] = Math.max(0, Math.min(255, a));
  }
}

function crc32(buf) {
  let table = crc32.table;
  if (!table) {
    table = crc32.table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      table[n] = c >>> 0;
    }
  }
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = table[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4);
ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  chunk('IHDR', ihdr),
  chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(out, png);
console.log('written', out, W + 'x' + H, png.length + 'B');
