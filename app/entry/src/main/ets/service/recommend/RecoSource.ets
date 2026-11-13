// entry/src/main/ets/service/recommend/RecoSource.ets —— 纯函数装配层，禁 @kit
import type { RelicInfo, SiteInfo } from '../../model/ContentModels';
import type { FavoriteDO, VisitDO } from '../../model/UserDataModels';
import { RecoInput, RecoResult, recommend, diversify } from './RecommendService';

import { cityName, typeName } from '../../common/Labels';
import { eraName } from '../../common/EraTheme';

// 冷启动兴趣：用户没留下任何浏览/收藏时，用 2–3 个年代或 1–2 个类型当种子。
// 只存 id，不存名字——语料改名后偏好不会跟着变成一串过期中文。
export class InterestPrefs {
  eras: string[] = [];
  types: string[] = [];

  isEmpty(): boolean {
    return this.eras.length === 0 && this.types.length === 0;
  }
}

// 负反馈与“已看过”过滤。三条通道分开存：
// id 通道直接不出现；年代/类型通道是“少看这类”，只排除对应维度。
export class RecoFilter {
  excludeIds: string[] = [];
  excludeEras: string[] = [];
  excludeTypes: string[] = [];
}

export function parsePrefs(json: string): InterestPrefs {
  const p = new InterestPrefs();
  if (json === '') { return p; }
  try {
    const raw = JSON.parse(json) as Record<string, string[]>;
    const eras = raw['eras'];
    const types = raw['types'];
    if (Array.isArray(eras)) { p.eras = eras; }
    if (Array.isArray(types)) { p.types = types; }
  } catch (_e) {
    // 坏 JSON 当成没选过：宁可让用户重选，也不要拿半截偏好去筛
  }
  return p;
}

export function serializePrefs(p: InterestPrefs): string {
  return JSON.stringify({ 'eras': p.eras, 'types': p.types } as Record<string, string[]>);
}

function filteredInputs(sites: SiteInfo[], f: RecoFilter): RecoInput[] {
  const out: RecoInput[] = [];
  for (const i of toInputs(sites)) {
    if (f.excludeIds.includes(i.id)) { continue; }
    if (f.excludeEras.includes(i.era)) { continue; }
    if (f.excludeTypes.includes(i.siteType)) { continue; }
    out.push(i);
  }
  return out;
}

function sortScored(out: RecoResult[]): RecoResult[] {
  out.sort((x: RecoResult, y: RecoResult): number => {
    if (y.score !== x.score) { return y.score - x.score; }
    return x.id < y.id ? -1 : 1;
  });
  return out;
}

// 兴趣种子：命中所选年代 +0.4、所选类型 +0.3，理由直接写明是哪一项选择。
// 不复用 recommend()：那个函数以“某一处遗址”为参照，冷启动时并没有这处遗址。
export function interestRows(sites: SiteInfo[], prefs: InterestPrefs, topN: number,
  filter?: RecoFilter): RecoRow[] {
  const f = filter === undefined ? new RecoFilter() : filter;
  const cands = filteredInputs(sites, f);
  const scored: RecoResult[] = [];
  for (const c of cands) {
    let score = 0;
    const reasons: string[] = [];
    if (prefs.eras.includes(c.era)) {
      score += 0.4;
      reasons.push(`你选了「${eraName(c.era)}」`);
    }
    if (prefs.types.includes(c.siteType)) {
      score += 0.3;
      reasons.push(`你选了「${typeName(c.siteType)}」`);
    }
    if (score <= 0) { continue; }
    const r = new RecoResult();
    r.id = c.id;
    r.score = Math.round(score * 1000) / 1000;
    r.reasons = reasons;
    scored.push(r);
  }
  sortScored(scored);
  return rowsFrom(diversify(scored, cands, 5, 5, topN), sites);
}

export function toInputs(sites: SiteInfo[]): RecoInput[] {
  const out: RecoInput[] = [];
  for (const s of sites) {
    const r = new RecoInput();
    r.id = s.id;
    r.era = s.era;
    r.siteType = s.siteType;
    r.city = s.city;
    r.tags = s.tags;
    out.push(r);
  }
  return out;
}

// 行为序列 = 最近 20 条收藏中的遗址项（listFavorites 已按 updateTime 倒序）
export function behaviorHistory(favs: FavoriteDO[], sites: SiteInfo[]): RecoInput[] {
  const inputs = toInputs(sites);
  const out: RecoInput[] = [];
  const recent = favs.slice(0, 20);
  for (const f of recent) {
    const parts: string[] = f.targetKey.split(':');
    if (parts[0] !== 'site') { continue; }
    for (const i of inputs) {
      if (i.id === parts[1]) {
        out.push(i);
        break;
      }
    }
  }
  return out;
}

export function favoredSiteIds(favs: FavoriteDO[]): string[] {
  const out: string[] = [];
  for (const f of favs) {
    const parts: string[] = f.targetKey.split(':');
    if (parts[0] === 'site' && !out.includes(parts[1])) { out.push(parts[1]); }
  }
  return out;
}

function siteIdOf(targetKey: string): string {
  const parts: string[] = targetKey.split(':');
  return parts[0] === 'site' ? parts[1] : '';
}

// F5：行为序列合并最近浏览（createTime 倒序）与最近收藏，站点去重；浏览优先
export function mixedHistory(favs: FavoriteDO[], visits: VisitDO[], sites: SiteInfo[]): RecoInput[] {
  const inputs = toInputs(sites);
  const seen: string[] = [];
  const out: RecoInput[] = [];
  const pushId = (id: string): void => {
    if (id === '' || seen.includes(id)) { return; }
    for (const i of inputs) {
      if (i.id === id) {
        seen.push(id);
        out.push(i);
        break;
      }
    }
  };
  for (const v of visits.slice(0, 20)) { pushId(siteIdOf(v.targetKey)); }
  for (const f of favs.slice(0, 20)) { pushId(siteIdOf(f.targetKey)); }
  return out.slice(0, 20);
}

export function recoFor(srcSite: SiteInfo, sites: SiteInfo[], favs: FavoriteDO[],
  topN: number, visits: VisitDO[] = [], filter?: RecoFilter): RecoResult[] {
  const src = new RecoInput();
  src.id = srcSite.id;
  src.era = srcSite.era;
  src.siteType = srcSite.siteType;
  src.city = srcSite.city;
  src.tags = srcSite.tags;
  const f = filter === undefined ? new RecoFilter() : filter;
  const cands = filteredInputs(sites, f);
  const exclude = favoredSiteIds(favs);
  for (const id of f.excludeIds) {
    if (!exclude.includes(id)) { exclude.push(id); }
  }
  const history = visits.length > 0 ? mixedHistory(favs, visits, sites) : behaviorHistory(favs, sites);
  // 先多取一些再按配额收：只取 topN 时，配额一削就凑不满，
  // 页面会出现“12 个位置只来了 7 条”的空档。
  const pool = recommend(src, cands, exclude, history, 24);
  return diversify(pool, cands, 5, 5, topN);
}

// 全局模式（无 from 入参）：以最近浏览/收藏的遗址为种子；
// 无行为时用冷启动偏好；偏好也没有时取语料首条（仅用于兜底，页面会先让用户选）。
export class GlobalReco {
  seedId: string = '';
  seedName: string = '';
  seedEra: string = '';
  hasBehavior: boolean = false;
  fromInterest: boolean = false;
  rows: RecoRow[] = [];
}

export function globalRows(sites: SiteInfo[], favs: FavoriteDO[], visits: VisitDO[],
  topN: number, prefs?: InterestPrefs, filter?: RecoFilter): GlobalReco {
  const g = new GlobalReco();
  const f = filter === undefined ? new RecoFilter() : filter;
  let seed: SiteInfo | null = null;
  for (const v of visits) {
    const id = siteIdOf(v.targetKey);
    if (id === '' || f.excludeIds.includes(id)) { continue; }
    for (const s of sites) {
      if (s.id === id) { seed = s; break; }
    }
    if (seed !== null) { break; }
  }
  if (seed === null) {
    for (const fav of favs) {
      const id = siteIdOf(fav.targetKey);
      if (id === '' || f.excludeIds.includes(id)) { continue; }
      for (const s of sites) {
        if (s.id === id) { seed = s; break; }
      }
      if (seed !== null) { break; }
    }
  }
  g.hasBehavior = seed !== null;
  if (seed === null) {
    const p = prefs === undefined ? new InterestPrefs() : prefs;
    if (!p.isEmpty()) {
      g.fromInterest = true;
      g.rows = interestRows(sites, p, topN, f);
      return g;
    }
    if (sites.length === 0) { return g; }
    seed = sites[0];
  }
  g.seedId = seed.id;
  g.seedName = seed.name;
  g.seedEra = seed.era;
  // 发现场景不推荐“刚看过”的：只排除 id，不排除年代/类型，
  // 否则看完一处仰韶就再也看不到别的仰韶。
  const discovery = new RecoFilter();
  discovery.excludeIds = f.excludeIds.slice();
  for (const v of visits) {
    const id = siteIdOf(v.targetKey);
    if (id !== '' && !discovery.excludeIds.includes(id)) { discovery.excludeIds.push(id); }
  }
  discovery.excludeEras = f.excludeEras;
  discovery.excludeTypes = f.excludeTypes;
  g.rows = recoRowsFor(seed, sites, favs, topN, visits, discovery);
  if (g.rows.length === 0) {
    // 42 处都看过了就退一步：宁可推荐看过的，也不要给一屏空白。
    g.rows = recoRowsFor(seed, sites, favs, topN, visits, f);
  }
  return g;
}

// 展示行：把推荐结果与语料字段一次装配好，页面不再做二次查找
export class RecoRow {
  id: string = '';
  rank: string = '';
  name: string = '';
  meta: string = '';
  era: string = '';
  siteType: string = '';
  score: string = '';
  // 0–100：相对本次结果最高分的比例。原先页面按绝对分 ×80，
  // 冷启动/兴趣模式下最高分只有 0.4，条子一律半格，像“推荐得不行”。
  bar: number = 0;
  reasons: string[] = [];
}

function rowsFrom(list: RecoResult[], sites: SiteInfo[]): RecoRow[] {
  let max = 0;
  for (const r of list) {
    if (r.score > max) { max = r.score; }
  }
  const out: RecoRow[] = [];
  for (let i = 0; i < list.length; i++) {
    const r = list[i];
    const row = new RecoRow();
    row.id = r.id;
    row.rank = i < 9 ? `0${i + 1}` : `${i + 1}`;
    row.score = r.score.toFixed(2);
    row.bar = max <= 0 ? 0 : Math.max(8, Math.round(r.score / max * 100));
    row.reasons = r.reasons;
    row.name = r.id;
    for (const s of sites) {
      if (s.id !== r.id) { continue; }
      row.name = s.name;
      row.era = s.era;
      row.siteType = s.siteType;
      row.meta = `${eraName(s.era)} · ${cityName(s.city)} · ${typeName(s.siteType)}`;
      break;
    }
    out.push(row);
  }
  return out;
}

export function recoRowsFor(srcSite: SiteInfo, sites: SiteInfo[], favs: FavoriteDO[],
  topN: number, visits: VisitDO[] = [], filter?: RecoFilter): RecoRow[] {
  return rowsFrom(recoFor(srcSite, sites, favs, topN, visits, filter), sites);
}

// ── 文物级推荐（赛题一主要功能第 5 条："推荐用户可能感兴趣的遗址**或文物**"）
//
// 文物页原有的三组相关文物（同遗址/同年代/同材质）是**静态关联**：种子就是
// 当前这件文物，与用户看过什么无关。这里补的是"基于收藏与浏览行为"的那一路。
//
// 三维映射：文物没有 siteType/city，所以
//   era      ← 器物自己的年代（不是所属遗址的年代；语料 12 件跨代）
//   siteType ← material（复用 0.3 那一档权重）
//   city     ← 所属遗址的城市
// 材质为空或「未记」时留空串：不参与同材质计分，否则所有缺材质字段的
// 器物会被聚成一组"同材质"，比不给推荐更误导。

export function relicInputs(sites: SiteInfo[]): RecoInput[] {
  const out: RecoInput[] = [];
  for (const s of sites) {
    for (const r of s.relics) {
      const i = new RecoInput();
      i.id = `relic:${r.id}`;
      i.era = r.era;
      i.siteType = r.material === '' ? '' : r.material;
      i.city = s.city;
      i.tags = [];
      out.push(i);
    }
  }
  return out;
}

// 行为序列：收藏与浏览里的文物键，按时间倒序取前 20 条。
export function relicHistory(favs: FavoriteDO[], visits: VisitDO[], sites: SiteInfo[]): RecoInput[] {
  const inputs = relicInputs(sites);
  const seen: string[] = [];
  const out: RecoInput[] = [];
  const push = (key: string): void => {
    if (key === '' || seen.includes(key)) { return; }
    for (const i of inputs) {
      if (i.id === key) {
        seen.push(key);
        out.push(i);
        return;
      }
    }
  };
  for (const v of visits.slice(0, 20)) {
    if (v.targetKey.startsWith('relic:')) { push(v.targetKey); }
  }
  for (const f of favs.slice(0, 20)) {
    if (f.targetKey.startsWith('relic:')) { push(f.targetKey); }
  }
  return out.slice(0, 20);
}

// 以一件文物为种子，算相似文物。行为史只用来给候选加权，不做种子
// ——种子的语义是"我正在看的这件"，混进行为史会推荐到别处去。
export function relicRecoFor(srcRelic: RelicInfo, sites: SiteInfo[], favs: FavoriteDO[],
  topN: number, visits: VisitDO[] = []): RecoRow[] {
  const src = new RecoInput();
  src.id = `relic:${srcRelic.id}`;
  src.era = srcRelic.era;
  src.siteType = srcRelic.material === '' ? '' : srcRelic.material;
  for (const s of sites) {
    for (const r of s.relics) {
      if (r.id === srcRelic.id) { src.city = s.city; break; }
    }
  }
  const cands = relicInputs(sites);
  // 排除自身 + 已收藏的文物
  const exclude: string[] = [src.id];
  for (const f of favs) {
    if (f.targetKey.startsWith('relic:') && !exclude.includes(f.targetKey)) {
      exclude.push(f.targetKey);
    }
  }
  const history = relicHistory(favs, visits, sites);
  const pool = recommend(src, cands, exclude, history, 24);
  const rows = diversify(pool, cands, 5, 5, topN);
  // recommend() 的理由词是按遗址语义写死的（siteType 那一位叫"同类型"）。
  // 文物把材质塞进同一位，所以这里把词换过来——不去改 recommend 本身，
  // 否则遗址路径的"同类型"会被连坐改坏。
  for (const r of rows) {
    r.reasons = r.reasons.map((s: string): string =>
      s === '同类型' ? '同材质' : s);
  }
  return relicRows(rows, sites);
}

// 把文物推荐结果转成页面能直接渲染的行。
// meta 用"器物年代 · 材质 · 所属遗址"——不写遗址类型，那是遗址语义。
function relicRows(list: RecoResult[], sites: SiteInfo[]): RecoRow[] {
  let max = 0;
  for (const r of list) {
    if (r.score > max) { max = r.score; }
  }
  const out: RecoRow[] = [];
  for (let i = 0; i < list.length; i++) {
    const r = list[i];
    const row = new RecoRow();
    row.id = r.id;
    row.rank = i < 9 ? `0${i + 1}` : `${i + 1}`;
    row.score = r.score.toFixed(2);
    row.bar = max <= 0 ? 0 : Math.max(8, Math.round(r.score / max * 100));
    row.reasons = r.reasons;
    row.name = r.id.substring('relic:'.length);
    const rid: string = row.name;
    for (const s of sites) {
      let hit = false;
      for (const rel of s.relics) {
        if (rel.id !== rid) { continue; }
        row.name = rel.name;
        row.era = rel.era;
        row.siteType = rel.material;
        row.meta = `${eraName(rel.era)} · ${rel.material === '' ? '材质未记' : rel.material} · ${s.name}`;
        hit = true;
        break;
      }
      if (hit) { break; }
    }
    out.push(row);
  }
  return out;
}
