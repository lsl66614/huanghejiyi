// entry/src/main/ets/service/content/ContentParse.ets —— 纯函数，禁 @kit
import { SiteInfo, RelicInfo, PoemRef, SiteEvent, TourismInfo, TourismGuide,
  ERAS, CITIES, SITE_TYPES } from '../../model/ContentModels';

function reqStr(o: Record<string, Object>, k: string): string {
  const v = o[k];
  if (typeof v !== 'string') { throw new Error(`字段 ${k} 缺失或非字符串`); }
  return v as string;
}

// 事件与文旅为可选增强层：语料未升级时回落为旧版单段文本，保证向后兼容
function optArr(o: Record<string, Object>, k: string): Record<string, Object>[] | null {
  const v = o[k];
  return Array.isArray(v) ? v as Record<string, Object>[] : null;
}

function parseEvent(ej: Record<string, Object>): SiteEvent {
  const e = new SiteEvent();
  e.year = reqStr(ej, 'year');
  e.title = reqStr(ej, 'title');
  e.summary = reqStr(ej, 'summary');
  const opt = (k: string): string => {
    const v = ej[k];
    return typeof v === 'string' ? v : '';
  };
  e.background = opt('background');
  e.process = opt('process');
  e.impact = opt('impact');
  e.furtherReading = opt('furtherReading');
  const figs = ej['figures'];
  if (Array.isArray(figs)) {
    for (const f of figs as string[]) {
      if (typeof f === 'string' && f !== '') { e.figures.push(f); }
    }
  }
  return e;
}

function parseTourism(tj: Record<string, Object>, fallback: string): TourismInfo {
  const t = new TourismInfo();
  const ov = tj['overview'];
  if (typeof ov !== 'string') {
    // 旧版单段文案：整段作为概览，指引与行程留空由 UI 隐藏
    t.overview = fallback;
    return t;
  }
  t.overview = ov;
  const g = tj['guide'];
  if (g !== undefined && g !== null) {
    const go = g as Record<string, Object>;
    const gopt = (k: string): string => {
      const v = go[k];
      return typeof v === 'string' ? v : '';
    };
    t.guide.hours = gopt('hours');
    t.guide.tickets = gopt('tickets');
    t.guide.address = gopt('address');
  }
  const it = tj['itinerary'];
  if (typeof it === 'string') { t.itinerary = it; }
  return t;
}

export function parseSiteJson(raw: string): SiteInfo {
  const o = JSON.parse(raw) as Record<string, Object>;
  const s = new SiteInfo();
  s.id = reqStr(o, 'id'); s.name = reqStr(o, 'name');
  s.city = reqStr(o, 'city'); s.era = reqStr(o, 'era'); s.siteType = reqStr(o, 'site_type');
  s.summary = reqStr(o, 'summary');
  if (!ERAS.includes(s.era) || !CITIES.includes(s.city) || !SITE_TYPES.includes(s.siteType)) {
    throw new Error(`${s.id}: 枚举值非法`);
  }
  const tags = o['tags'] as string[]; s.tags = tags;
  const sec = o['sections'] as Record<string, Object>;
  s.intro = reqStr(sec, 'intro'); s.archaeology = reqStr(sec, 'arch');
  const evs = optArr(sec, 'events');
  if (evs !== null) {
    for (const ej of evs) { s.events.push(parseEvent(ej)); }
  } else {
    s.events.push(parseEvent({
      'year': '', 'title': '', 'summary': reqStr(sec, 'events')
    }));
  }
  const poems = sec['poems'] as Record<string, Object>[];
  for (const p of poems) {
    const pr = new PoemRef();
    pr.text = reqStr(p, 'text'); pr.author = reqStr(p, 'author'); pr.source = reqStr(p, 'source');
    s.poems.push(pr);
  }
  const tj = sec['tourism'];
  s.tourism = parseTourism(
    (tj !== undefined && tj !== null) ? tj as Record<string, Object> : {},
    typeof tj === 'string' ? tj : '');
  s.images = o['images'] as string[];
  const relics = o['relics'] as Record<string, Object>[];
  for (const rj of relics) {
    const r = new RelicInfo();
    r.id = reqStr(rj, 'id'); r.siteId = s.id; r.name = reqStr(rj, 'name');
    r.era = reqStr(rj, 'era'); r.summary = reqStr(rj, 'summary');
    r.material = reqStr(rj, 'material'); r.images = rj['images'] as string[];
    s.relics.push(r);
  }
  return s;
}

// 逐文件解析报告：一份坏 JSON 不应该让 41 份好内容一起消失。
// names 与 raws 一一对应，仅用于把失败文件报给用户/日志。
export class ParseReport {
  sites: SiteInfo[] = [];
  failed: string[] = [];
}

export function parseAllReport(raws: string[], names: string[]): ParseReport {
  const out = new ParseReport();
  for (let i = 0; i < raws.length; i++) {
    try {
      out.sites.push(parseSiteJson(raws[i]));
    } catch (e) {
      const name = i < names.length ? names[i] : `${i + 1}`;
      out.failed.push(name);
    }
  }
  return out;
}

// 兼容旧调用（Node 纯函数测试仍按数组断言）：坏文件跳过，不抛。
export function parseAll(raws: string[]): SiteInfo[] {
  return parseAllReport(raws, []).sites;
}

export function filterSites(sites: SiteInfo[], eras: string[], types: string[], cities: string[]): SiteInfo[] {
  return sites.filter((s: SiteInfo): boolean =>
    (eras.length === 0 || eras.includes(s.era)) &&
    (types.length === 0 || types.includes(s.siteType)) &&
    (cities.length === 0 || cities.includes(s.city)));
}

export function searchSites(sites: SiteInfo[], keyword: string): SiteInfo[] {
  const kw = keyword.toLowerCase();
  if (kw.length === 0) { return sites; }
  return sites.filter((s: SiteInfo): boolean =>
    s.name.toLowerCase().includes(kw) || s.summary.toLowerCase().includes(kw) ||
    s.tags.some((t: string): boolean => t.toLowerCase().includes(kw)));
}
