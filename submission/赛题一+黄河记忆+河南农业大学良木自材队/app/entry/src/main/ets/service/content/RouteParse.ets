// entry/src/main/ets/service/content/RouteParse.ets —— 纯函数，禁 @kit
//
// 路线是「内容」不是「行为」：它和 site/*.json 一样放在 rawfile 里人工整编，
// 不写库、不参与同步。这样做的代价是用户不能自建路线；好处是路线本身
// 可以被审校——一条把二里头和开封铁塔排在一起的“路线”没有阅读价值。
import { RouteInfo, RouteStop } from '../../model/ContentModels';

function str(o: Record<string, Object>, k: string): string {
  const v = o[k];
  return typeof v === 'string' ? v : '';
}

// 容错口径与 parseAllReport 一致：一段坏数据只丢它自己，
// 不让整份路线表变成空白。缺 id / title / stops 的条目直接跳过——
// 没有标题的路线在列表里只是一条无法辨认的横线。
export function parseRoutes(raw: string): RouteInfo[] {
  const out: RouteInfo[] = [];
  if (raw.trim() === '') { return out; }
  let root: Record<string, Object>;
  try {
    root = JSON.parse(raw) as Record<string, Object>;
  } catch (_e) {
    return out;
  }
  const arr = root['routes'];
  if (!Array.isArray(arr)) { return out; }
  for (const item of arr as Record<string, Object>[]) {
    const id = str(item, 'id');
    const title = str(item, 'title');
    const stops = item['stops'];
    if (id === '' || title === '' || !Array.isArray(stops)) { continue; }
    const r = new RouteInfo();
    r.id = id;
    r.title = title;
    r.subtitle = str(item, 'subtitle');
    r.era = str(item, 'era');
    r.duration = str(item, 'duration');
    for (const sj of stops as Record<string, Object>[]) {
      const siteId = str(sj, 'site');
      if (siteId === '') { continue; }
      const st = new RouteStop();
      st.siteId = siteId;
      st.note = str(sj, 'note');
      r.stops.push(st);
    }
    if (r.stops.length === 0) { continue; }
    out.push(r);
  }
  return out;
}

// 路线写的是未来可能新增的站点；语料里还没有的 id 只能先摘掉。
// 摘完不足两站的路线不显示：一站不成线，留着只会让人点进去看到孤零零一条。
export function pruneRoutes(routes: RouteInfo[], siteIds: string[]): RouteInfo[] {
  const out: RouteInfo[] = [];
  for (const r of routes) {
    const kept: RouteStop[] = [];
    const seen: string[] = [];
    for (const st of r.stops) {
      if (!siteIds.includes(st.siteId) || seen.includes(st.siteId)) { continue; }
      seen.push(st.siteId);
      kept.push(st);
    }
    if (kept.length < 2) { continue; }
    const c = new RouteInfo();
    c.id = r.id;
    c.title = r.title;
    c.subtitle = r.subtitle;
    c.era = r.era;
    c.duration = r.duration;
    c.stops = kept;
    out.push(c);
  }
  return out;
}

// 完成度只数「五段全部读完」的站点，与首页年代卡的完成度同一口径。
// 只读过一段也算一站，会让 1/5 与 5/5 在进度条上毫无区别。
export function routeDoneCount(route: RouteInfo, readSiteIds: string[]): number {
  let n = 0;
  for (const st of route.stops) {
    if (readSiteIds.includes(st.siteId)) { n++; }
  }
  return n;
}

export function routePercent(route: RouteInfo, readSiteIds: string[]): number {
  if (route.stops.length === 0) { return 0; }
  return Math.round(routeDoneCount(route, readSiteIds) / route.stops.length * 100);
}

// 「下一站」：顺序上第一个没读完的站点。全读完了就返回空串，
// 页面据此把按钮文案换成「再走一遍」，而不是假装还有下一站。
export function nextStopId(route: RouteInfo, readSiteIds: string[]): string {
  for (const st of route.stops) {
    if (!readSiteIds.includes(st.siteId)) { return st.siteId; }
  }
  return '';
}
