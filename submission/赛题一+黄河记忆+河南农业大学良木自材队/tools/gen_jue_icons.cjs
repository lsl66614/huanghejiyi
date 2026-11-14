// 生成爵形剪影 SVG（6 个年代墨色版本 + 1 个兜底版本），供 SilhouettePlate 用 Image 渲染。
// 用法: node tools/gen_jue_icons.cjs
// 输出: app/entry/src/main/resources/rawfile/icons/jue_<era>.svg + jue.svg
// 墨色与 EraTheme.ERA_INKS 一致；线稿坐标空间 84×84（与 SilhouettePlate 注释一致）。
const fs = require('fs');
const path = require('path');

const D = 'M12 32 L40 32 L66 20 M40 32 L44 46 C44 58 36 62 30 62 C24 62 16 58 16 46 L20 32 ' +
  'M27 32 L27 23 M27 23 A2 2 0 1 1 27.1 23 M37 32 L37 25 M37 25 A2 2 0 1 1 37.1 25 ' +
  'M16 44 L9 48 L11 56 L18 53 M24 62 L21 78 M36 62 L39 78 M30 62 L30 78';

// era → 墨色（与 EraTheme.ERA_INKS 同步维护）
const INKS = {
  yangshao: '#F5EFE2', longshan: '#F5EFE2', xiashang: '#F5EFE2',
  zhou: '#1F1B16', hantang: '#1F1B16', song: '#1F1B16'
};

function svg(ink) {
  return '<?xml version="1.0" encoding="utf-8"?>\n' +
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 84 84" width="84" height="84">\n' +
    '  <path d="' + D + '" fill="none" stroke="' + ink + '" stroke-width="1.6" stroke-linecap="round"/>\n' +
    '</svg>\n';
}

const outDir = path.join(__dirname, '..', 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'icons');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'jue.svg'), svg('#F5EFE2'));
for (const era of Object.keys(INKS)) {
  fs.writeFileSync(path.join(outDir, 'jue_' + era + '.svg'), svg(INKS[era]));
}
console.log('written jue.svg + ' + Object.keys(INKS).length + ' era variants to ' + outDir);
