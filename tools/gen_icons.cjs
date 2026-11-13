// 生成单线描边图标族（与爵形剪影同笔法：round cap/join、细描边）。
// 用法: node tools/gen_icons.cjs
// 输出: app/entry/src/main/resources/rawfile/icons/ic_<名>_<色>.svg（ink=墨 #2B2622 / red=赭红 #8E4028）
// 图标语义：nianlun 年轮(年代) / tanfang 探方(收藏) / jiandu 简牍(笔记) / yin 印(我的) / sinan 司南(检索) / genxi 根系
const fs = require('fs');
const path = require('path');

const ICONS = {
  // 年轮：同心圆 + 开口弧 + 芯
  nianlun: '<circle cx="24" cy="24" r="15"/><path d="M24 16 A8 8 0 0 1 32 24"/><circle cx="24" cy="24" r="2.6" fill="FILLC" stroke="none"/>',
  // 探方：方格
  tanfang: '<rect x="10" y="10" width="28" height="28"/><path d="M10 24 H38 M24 10 V38"/>',
  // 简牍：三牍两编
  jiandu: '<rect x="12" y="9" width="7" height="30" rx="2"/><rect x="20.5" y="9" width="7" height="30" rx="2"/><rect x="29" y="9" width="7" height="30" rx="2"/><path d="M9 19 H39 M9 29 H39"/>',
  // 印：双框
  yin: '<rect x="11" y="11" width="26" height="26"/><rect x="18" y="18" width="12" height="12"/>',
  // 司南：罗盘 + 指针
  sinan: '<circle cx="24" cy="24" r="16"/><path d="M24 24 L32.5 15.5"/><circle cx="24" cy="24" r="2.6" fill="FILLC" stroke="none"/>',
  // 根系：主干 + 三须
  genxi: '<circle cx="24" cy="14" r="2.6" fill="FILLC" stroke="none"/><path d="M24 17 V26 M24 26 C18 30 16 34 15 39 M24 26 C30 30 32 34 33 39 M24 26 V39"/>'
};

const COLORS = { ink: '#2B2622', red: '#8E4028' };
const outDir = path.join(__dirname, '..', 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'icons');
fs.mkdirSync(outDir, { recursive: true });

for (const name of Object.keys(ICONS)) {
  for (const ck of Object.keys(COLORS)) {
    const svg = '<?xml version="1.0" encoding="utf-8"?>\n' +
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" width="48" height="48">\n' +
      '  <g fill="none" stroke="' + COLORS[ck] + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
      ICONS[name].split('FILLC').join(COLORS[ck]) +
      '</g>\n</svg>\n';
    fs.writeFileSync(path.join(outDir, 'ic_' + name + '_' + ck + '.svg'), svg);
  }
}
console.log('written ' + Object.keys(ICONS).length * 2 + ' icons to ' + outDir);
