// entry/src/main/ets/service/content/RelicIndex.ets —— 文物扁平索引，纯函数，禁 @kit
//
// 语料里文物挂在 sites[].relics[] 下，之前只有「从遗址进文物」一条路：
// 104 件文物没有全局入口，用户想找一件具体的器物只能先猜它在哪个遗址。
// 本文件把树压平，给图录页、搜索页、今日一物共用一份稳定顺序。
//
// 不新增表、不改同步域：索引每次从 ContentRepo 的语料现算，随内容更新自动变化。
import type { SiteInfo } from '../../model/ContentModels';

export class RelicEntry {
  id: string = '';
  name: string = '';
  siteId: string = '';
  siteName: string = '';
  era: string = '';
  material: string = '';
  summary: string = '';
  images: string[] = [];
  // 语料顺序：同遗址内 relics[] 的下标。图录默认按年代 + 遗址 + 序位排，
  // 让「同一层、同一处」的器物自然相邻，而不是按 id 字典序乱跳。
  siteOrder: number = 0;
}

export class RelicIndex {
  entries: RelicEntry[] = [];
  siteIds: string[] = [];
  siteNames: string[] = [];
}

// 按语料顺序压平；年代顺序由调用方按 ERAS 再排（本文件不 import 任何常量，
// 保持可单独做 Node 断言）。
export function buildRelicIndex(sites: SiteInfo[]): RelicIndex {
  const idx = new RelicIndex();
  for (const s of sites) {
    for (let i = 0; i < s.relics.length; i++) {
      const r = s.relics[i];
      const e = new RelicEntry();
      e.id = r.id;
      e.name = r.name;
      e.siteId = s.id;
      e.siteName = s.name;
      e.era = r.era;
      e.material = r.material;
      e.summary = r.summary;
      e.images = r.images;
      e.siteOrder = i;
      idx.entries.push(e);
    }
    if (s.relics.length > 0 && !idx.siteIds.includes(s.id)) {
      idx.siteIds.push(s.id);
      idx.siteNames.push(s.name);
    }
  }
  return idx;
}

// 关键词命中：文物名、遗址名、材质、提要。统一小写，中文不受影响。
export function relicHit(e: RelicEntry, keyword: string): boolean {
  const kw: string = keyword.trim().toLowerCase();
  if (kw === '') { return true; }
  return e.name.toLowerCase().includes(kw) ||
    e.siteName.toLowerCase().includes(kw) ||
    e.material.toLowerCase().includes(kw) ||
    e.summary.toLowerCase().includes(kw);
}
