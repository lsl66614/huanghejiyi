// service/content/TargetLabel.ets —— target_key → 人话
//
// 导出文件里不能出现 `site:xiaolangdi:arch` 这种键：用户打开自己导出的
// Markdown，第一眼要认出「小浪底遗址 · 考古」。这条映射原本在笔记中心、
// 最近删除、搜索页各写了一遍；导出让第四处出现，于是收在这里。
//
// 纯函数 + 纯类型：不碰 @kit，可进 Node 单测。
import type { SiteInfo } from '../../model/ContentModels';
import { itemLabel } from './ItemTarget';

export function sectionLabelOf(sec: string): string {
  if (sec === 'intro') { return '介绍'; }
  if (sec === 'arch') { return '考古'; }
  if (sec === 'events') { return '历史'; }
  if (sec === 'poems') { return '诗词'; }
  if (sec === 'tourism') { return '文旅'; }
  return sec;
}

export class TargetLabels {
  private siteNames: Map<string, string> = new Map();
  private relicNames: Map<string, string> = new Map();

  build(sites: SiteInfo[]): void {
    for (const s of sites) {
      this.siteNames.set(s.id, s.name);
      for (const r of s.relics) {
        this.relicNames.set(r.id, r.name);
      }
    }
  }

  // 语料没加载到、或键里是一个已不存在的 id 时，退化为原始 id：
  // 导出的文本宁可难看，也不能出现空白标题。
  label(key: string): string {
    if (key === 'notebook:inbox') { return '随手笔记'; }
    const parts: string[] = key.split(':');
    if (parts.length >= 2 && parts[0] === 'site') {
      const site = this.nameOr(this.siteNames, parts[1]);
      const item: string = itemLabel(key, site);
      if (item !== '') { return item; }
      if (parts.length >= 3 && parts[2] !== '') {
        return `${site} · ${sectionLabelOf(parts[2])}`;
      }
      return site;
    }
    if (parts.length >= 2 && parts[0] === 'relic') {
      return this.nameOr(this.relicNames, parts[1]);
    }
    return key;
  }

  private nameOr(map: Map<string, string>, id: string): string {
    const v: string | undefined = map.get(id);
    return v === undefined ? id : v;
  }
}
