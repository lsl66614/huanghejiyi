// entry/src/main/ets/service/content/EraRelicCount.ets —— 年代 × 文物 双轴计数，纯函数，禁 @kit
//
// 为什么需要它（A 方案：双实体不做首页并列分段，做进年代轴）：
// 赛题 F1 点名「文物线是平级公民」，但首页做「遗址 ⇄ 文物」并列分段会
// 把首页读成仪表盘，且要推翻 Index 既有的减法决策。改成沿现有信息架构
// 往下长：每一张年代卡上同时给出「这一层有几处遗址」与「这一层有几件文物」，
// 两个数字并列——双实体因此有了首屏落点，却不必新增一层导航。
//
// 口径（关键，别踩）：
// **文物的年代取 RelicInfo.era（器物自己的年代），不是所属遗址的年代。**
// 语料里 104 件文物有 12 件与所属遗址不同代——宋代的巩义窑址出土汉唐唐三彩
// （site=song / relic=hantang），龙山遗址出仰韶陶片（site=longshan / relic=yangshao）。
// 若按遗址年代计，这 12 件会被算进错误的层，全站 104 件会被重复计到多个层，
// 分层总数 ≠ 104。按器物年代计则每件只落一层，六层之和恰为 104。
//
// 纯函数、禁 @kit：可被 Node 单测逐条比对，不依赖模拟器。
import type { SiteInfo } from '../../model/ContentModels';

export class EraRelicStat {
  era: string = '';
  // 该年代的遗址数
  siteCount: number = 0;
  // 该年代的文物数（按器物自己的年代）
  relicCount: number = 0;
}

// 按年代统计遗址与文物。eras 给定遍历顺序（须与 ERAS 同序）。
export function buildEraRelicStats(sites: SiteInfo[], eras: string[]): EraRelicStat[] {
  const out: EraRelicStat[] = [];
  for (const e of eras) {
    const st = new EraRelicStat();
    st.era = e;
    out.push(st);
  }
  for (const s of sites) {
    // 遗址计一次。site.era 必在 eras 内；不在则跳过（语料越界，不静默吞掉——
    // 调用方可对比 siteCount 总数与 sites.length 发现）。
    const siteStat = out.find((x: EraRelicStat): boolean => x.era === s.era);
    if (siteStat !== undefined) {
      siteStat.siteCount++;
    }
    // 文物按自己的年代落层，一件只落一层。
    for (const r of s.relics) {
      const relicStat = out.find((x: EraRelicStat): boolean => x.era === r.era);
      if (relicStat !== undefined) {
        relicStat.relicCount++;
      }
    }
  }
  return out;
}

// 某一层里的文物条目（按器物年代过滤），供年代视图直接渲染缩略图条。
export interface EraRelicChip {
  id: string;
  name: string;
  siteId: string;
  siteName: string;
  material: string;
  era: string;
}

// 取某年代的文物，最多数量上限由调用方给。顺序按站点内语料序（siteOrder），
// 与 RelicIndex 的默认排法一致——同一处的器物自然相邻。
export function relicsOfEra(sites: SiteInfo[], era: string, limit: number): EraRelicChip[] {
  const out: EraRelicChip[] = [];
  for (const s of sites) {
    for (const r of s.relics) {
      if (r.era !== era) { continue; }
      if (out.length >= limit) { return out; }
      out.push({
        id: r.id,
        name: r.name,
        siteId: s.id,
        siteName: s.name,
        material: r.material,
        era: r.era
      });
    }
  }
  return out;
}
