// entry/src/main/ets/service/content/MaterialIndex.ets —— 材质索引，纯函数，禁 @kit
//
// 为什么加这一层：现有检索是「年代 × 类型 × 城市」的属性矩阵，非专业用户
// （评审现场）面对三组 chip 要先想清楚自己要什么。Google Arts & Culture
// 验证过更直觉的入口是「按颜色/材质逛」——「我想看陶器」是一句自然的诉求。
//
// 本文件把 104 件文物的材质归一化到 7 类（口径见 common/RelicIcon.ets 的
// materialKind），并算出每类覆盖多少遗址/文物，供 UI 生成材质入口。
import type { SiteInfo } from '../../model/ContentModels';

export class MaterialBucket {
  kind: string = '';       // 归一化类名：陶/金属/土/玉/石/骨/有机/未记
  siteCount: number = 0;   // 覆盖几处遗址
  relicCount: number = 0;  // 几件文物
  siteIds: string[] = [];  // 覆盖的遗址 id（点进去能跳检索页）
  eras: string[] = [];     // 跨了哪几个年代（入口上展示「跨越 4 个年代」）
}

export class MaterialIndex {
  buckets: MaterialBucket[] = [];
  totalRelics: number = 0;
}

// 与 RelicIcon.RULES 同一套关键词与类名。这里重复一份而不是 import：
// RelicIcon 会 import DesignTokens（反依赖），而本文件要保持「纯函数、禁 @kit」
// 以进 Node 测试。两处的一致性由 tools/merge-tests/material_index.test.mjs 断言。
const MATERIAL_RULES: Array<[string[], string]> = [
  [['陶', '瓷', '釉'], '陶'],
  [['铜', '金', '铁'], '金属'],
  [['夯土', '土', '砖', '瓦', '灰', '遗迹', '泥', '琉璃', '堆积'], '土'],
  [['玉', '绿松石'], '玉'],
  [['石'], '石'],
  [['骨', '蚌', '牙', '角'], '骨'],
  [['丝', '木', '漆'], '有机']
];

function kindOf(material: string): string {
  if (material === '' || material === 'mixed') { return '未记'; }
  for (const rule of MATERIAL_RULES) {
    const keys: string[] = rule[0];
    for (const k of keys) {
      if (material.indexOf(k) >= 0) { return rule[1]; }
    }
  }
  return '未记';
}

// 入口的展示顺序：按文物数从多到少。「陶」是黄河史前的主角，理应排第一。
// 未记永远排最后——它不是一类材质，是数据缺口。
export function buildMaterialIndex(sites: SiteInfo[]): MaterialIndex {
  const idx = new MaterialIndex();
  const map: Map<string, MaterialBucket> = new Map();
  for (const s of sites) {
    for (const r of s.relics) {
      idx.totalRelics += 1;
      const kind: string = kindOf(r.material);
      let b = map.get(kind);
      if (b === undefined) {
        b = new MaterialBucket();
        b.kind = kind;
        map.set(kind, b);
      }
      b.relicCount += 1;
      if (!b.siteIds.includes(s.id)) {
        b.siteIds.push(s.id);
        b.siteCount += 1;
      }
      if (!b.eras.includes(r.era)) { b.eras.push(r.era); }
    }
  }
  const all: MaterialBucket[] = [];
  map.forEach((b: MaterialBucket) => { all.push(b); });
  all.sort((m: MaterialBucket, n: MaterialBucket): number => {
    if (m.kind === '未记') { return 1; }
    if (n.kind === '未记') { return -1; }
    if (n.relicCount !== m.relicCount) { return n.relicCount - m.relicCount; }
    return m.kind < n.kind ? -1 : (m.kind > n.kind ? 1 : 0);
  });
  idx.buckets = all;
  return idx;
}

// 入口副标题：「25 件 · 18 处遗址」
export function bucketSubtitle(b: MaterialBucket): string {
  return `${b.relicCount} 件 · ${b.siteCount} 处遗址`;
}

// 跨越年代数：≥2 才值得念，否则只说「陶」就够了
export function bucketEraNote(b: MaterialBucket, eraNames: Map<string, string>): string {
  if (b.eras.length < 2) { return ''; }
  const names: string[] = [];
  for (const e of b.eras) {
    const n = eraNames.get(e);
    if (n !== undefined) { names.push(n); }
  }
  return `跨越 ${b.eras.length} 个年代`;
}
