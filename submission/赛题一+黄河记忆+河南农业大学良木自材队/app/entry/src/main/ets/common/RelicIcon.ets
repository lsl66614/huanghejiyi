// entry/src/main/ets/common/RelicIcon.ets
// 文物剪影的分类线稿：材质决定图标，不再让 104 件文物共用一只「爵」。
// 图标只表达"这是哪一类器物"，不冒充实物影像；缺料时回落到 jue.svg。
//
// 同时承担**材质归一化**：语料的 material 字段有 38 种写法（含 'mixed'、
// '复合堆积'、'路土、夯土、淤泥等叠压文化层' 这类描述句），直接展示会
// 让「材质章」读作一堆噪声。materialKind() 把它收敘到 7 类，
// 与图标分类同一套关键词——展示与图标因此永不矛盾。
class IconRule {
  keys: string[] = [];
  src: string = '';
  // 归一化后的中文类名（材质章展示用）
  kind: string = '';
  constructor(keys: string[], src: string, kind: string) {
    this.keys = keys;
    this.src = src;
    this.kind = kind;
  }
}

const RULES: IconRule[] = [
  new IconRule(['陶', '瓷', '釉'], 'icons/relic_pottery.svg', '陶'),
  new IconRule(['铜', '金', '铁'], 'icons/relic_metal.svg', '金属'),
  new IconRule(['夯土', '土', '砖', '瓦', '灰', '遗迹', '泥', '琉璃', '堆积'], 'icons/relic_earth.svg', '土'),
  new IconRule(['玉', '绿松石'], 'icons/relic_jade.svg', '玉'),
  new IconRule(['石'], 'icons/relic_stone.svg', '石'),
  new IconRule(['骨', '蚌', '牙', '角'], 'icons/relic_bone.svg', '骨'),
  new IconRule(['丝', '木', '漆'], 'icons/relic_organic.svg', '有机')
];

function hit(material: string, keys: string[]): boolean {
  for (const k of keys) {
    if (material.indexOf(k) >= 0) { return true; }
  }
  return false;
}

export function relicIconSrc(material: string): string {
  for (const rule of RULES) {
    if (hit(material, rule.keys)) { return rule.src; }
  }
  return 'icons/jue.svg';
}

// 归一化类名。空值与 'mixed' 这类无语料信息的值落到 '未记'，
// 不硬塞进某一类——冒充分类比承认没记更糟。
export function materialKind(material: string): string {
  if (material === '' || material === 'mixed') { return '未记'; }
  for (const rule of RULES) {
    if (hit(material, rule.keys)) { return rule.kind; }
  }
  return '未记';
}

// Facts 卡片位窄：复合材质只取第一项（「夯土/石」→「夯土」）。
// 仅用于「材质」这一行的原文展示，与 materialKind 的分类章是两件事。
export function materialShort(material: string): string {
  const slash: number = material.indexOf('/');
  if (slash > 0) { return material.substring(0, slash); }
  const dun: number = material.indexOf('、');
  if (dun > 0) { return material.substring(0, dun); }
  return material;
}
