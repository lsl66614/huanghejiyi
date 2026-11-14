// entry/src/main/ets/service/network/NetworkSource.ets —— 根系图数据装配，纯函数，禁 @kit
//
// 本文件只负责「图里有什么」：节点、边、统计、按年代归拢的清单。
// 「节点放哪里」归 service/network/ForceLayout.ets（力导向）。
// 早期版本把两者混在一起，布局字段（angle/ring）写死在构建过程里，
// 换成力导向时要连数据结构一起改，故拆开。
import { ERAS, SiteInfo } from '../../model/ContentModels';
import type { NoteView } from '../../model/UserDataModels';
import { eraName } from '../../common/EraTheme';
// ForceEdge 是**值**导入而非 type：NetworkSource 要 new 出实例填进
// graph.forces。写成 import type 时 Node 侧 type-stripping 会把它整条删掉，
// 运行期报 ReferenceError（tools/merge-tests 实测）。
import { ForceEdge } from './ForceLayout';

export const RING_ROOT: number = 0;
export const RING_ERA: number = 0.30;
export const RING_SITE: number = 0.64;
export const RING_LEAF: number = 0.95;

export class NetNode {
  id: string = '';
  label: string = '';
  kind: string = ''; // 'root' | 'era' | 'site' | 'relic' | 'tag'
  era: string = '';
  angle: number = 0; // 弧度，0 = 正右方；坐标由环半径 × (cos, sin) 换算
  ring: number = 0;
  size: number = 1;  // 由连边数派生的视觉权重
  meta: string = '';
}

export class NetEdge {
  a: string = '';
  b: string = '';
  kind: string = ''; // 'root' 中心→年代 | 'branch' 年代→遗址 | 'leaf' 遗址→文物/标签
}

export class NetGraph {
  nodes: NetNode[] = [];
  edges: NetEdge[] = [];
  // 力导向用的边（带共现权重）。与 edges 同源，但 weight 决定引力与线宽。
  forces: ForceEdge[] = [];
  // 每条力边的共现标签清单，供 Tooltip/无障碍播报「因哪些标签相连」
  forceTags: Map<string, string[]> = new Map();
  rows: NetRow[] = [];
  empty: boolean = true;
  stat: string = '';
}

// 环上标签会互相压字，故图下方另出一份按年代归拢的清单，与节点同源
export class NetRow {
  era: string = '';
  name: string = '';
  count: number = 0;
  names: string = '';
}

function siteOfRelic(sites: SiteInfo[], relicId: string): SiteInfo | null {
  for (const s of sites) {
    for (const r of s.relics) {
      if (r.id === relicId) { return s; }
    }
  }
  return null;
}

function siteOfKey(sites: SiteInfo[], key: string): SiteInfo | null {
  const parts: string[] = key.split(':');
  if (parts[0] === 'site') {
    for (const s of sites) {
      if (s.id === parts[1]) { return s; }
    }
    return null;
  }
  if (parts[0] === 'relic') { return siteOfRelic(sites, parts[1]); }
  return null;
}

function edge(a: string, b: string, kind: string): NetEdge {
  const e = new NetEdge();
  e.a = a; e.b = b; e.kind = kind;
  return e;
}

function eraIndex(era: string): number {
  const i = ERAS.indexOf(era);
  return i < 0 ? ERAS.length : i;
}

// 中心 → 年代根 → 遗址 → 文物 / 标签叶；同心圆环按度数均分角度，故图形与数据一一对应而非随机撒点
export function buildGraph(sites: SiteInfo[], favKeys: string[], notes: NoteView[]): NetGraph {
  const g = new NetGraph();
  const siteIds: string[] = [];
  for (const k of favKeys) {
    const parts: string[] = k.split(':');
    if (parts[0] === 'site') {
      if (!siteIds.includes(parts[1])) { siteIds.push(parts[1]); }
    } else if (parts[0] === 'relic') {
      // 只收藏文物时，所属遗址也要入图，否则这条叶会凭空消失
      const owner = siteOfRelic(sites, parts[1]);
      if (owner !== null && !siteIds.includes(owner.id)) { siteIds.push(owner.id); }
    }
  }
  const picked: SiteInfo[] = [];
  for (const id of siteIds) {
    for (const s of sites) {
      if (s.id === id) { picked.push(s); break; }
    }
  }
  picked.sort((m: SiteInfo, n: SiteInfo): number => {
    const e = eraIndex(m.era) - eraIndex(n.era);
    if (e !== 0) { return e; }
    return m.id < n.id ? -1 : (m.id > n.id ? 1 : 0);
  });
  const root = new NetNode();
  root.id = 'root';
  root.label = '我的黄河';
  root.kind = 'root';
  root.ring = RING_ROOT;
  root.size = 2.4;
  g.nodes.push(root);
  if (picked.length === 0) {
    g.stat = '尚无收藏，先去遗址页点 ☆';
    return g;
  }
  const ang = new Map<string, number>();
  const step = 6.28318 / picked.length;
  for (let i = 0; i < picked.length; i++) {
    const a = -1.5708 + i * step;
    ang.set(picked[i].id, a);
    const n = new NetNode();
    n.id = `site:${picked[i].id}`;
    n.label = picked[i].name;
    n.kind = 'site';
    n.era = picked[i].era;
    n.angle = a;
    n.ring = RING_SITE;
    n.meta = eraName(picked[i].era);
    g.nodes.push(n);
  }
  // 年代根：取所属遗址角度的均值，落在中心与遗址之间
  const eraMembers = new Map<string, string[]>();
  for (const s of picked) {
    const cur = eraMembers.get(s.era);
    if (cur === undefined) { eraMembers.set(s.era, [s.id]); }
    else { cur.push(s.id); }
  }
  eraMembers.forEach((ids: string[], era: string) => {
    let sum = 0;
    for (const id of ids) {
      const a = ang.get(id);
      if (a !== undefined) { sum += a; }
    }
    const e = new NetNode();
    e.id = `era:${era}`;
    e.label = eraName(era);
    e.kind = 'era';
    e.era = era;
    e.angle = sum / ids.length;
    e.ring = RING_ERA;
    e.size = 1 + ids.length * 0.25;
    e.meta = `${ids.length} 处`;
    g.nodes.push(e);
    g.edges.push(edge('root', e.id, 'root'));
    for (const id of ids) {
      g.edges.push(edge(e.id, `site:${id}`, 'branch'));
    }
  });
  // 文物叶：挂在所属遗址角度两侧
  const relicPerSite = new Map<string, number>();
  for (const k of favKeys) {
    const parts: string[] = k.split(':');
    if (parts[0] !== 'relic') { continue; }
    const owner = siteOfRelic(sites, parts[1]);
    if (owner === null) { continue; }
    if (ang.get(owner.id) === undefined) { continue; } // 只连已入图的遗址
    const used = relicPerSite.get(owner.id);
    const j = used === undefined ? 0 : used;
    relicPerSite.set(owner.id, j + 1);
    const pa = ang.get(owner.id);
    const node = new NetNode();
    if (pa === undefined) { continue; }
    node.id = `relic:${parts[1]}`;
    node.label = relicName(sites, parts[1]);
    node.kind = 'relic';
    node.era = owner.era;
    node.angle = pa + (j === 0 ? -0.075 : 0.075 * (j - 0.5));
    node.ring = (j % 2 === 1) ? 1.06 : RING_LEAF; // 同遗址第二件外推一环，避免两点叠在一起
    node.size = 0.8;
    g.nodes.push(node);
    g.edges.push(edge(`site:${owner.id}`, node.id, 'leaf'));
  }
  // 标签叶：笔记标签把散落的遗址缝在一起
  const tagLinks = new Map<string, string[]>();
  for (const note of notes) {
    const owner = siteOfKey(sites, note.targetKey);
    if (owner === null) { continue; }
    const sid = `site:${owner.id}`;
    if (ang.get(owner.id) === undefined) { continue; }
    for (const t of note.tagIds) {
      const cur = tagLinks.get(t);
      if (cur === undefined) { tagLinks.set(t, [sid]); }
      else if (!cur.includes(sid)) { cur.push(sid); }
    }
  }
  tagLinks.forEach((ids: string[], tag: string) => {
    let sum = 0;
    for (const id of ids) {
      const a = ang.get(id.split(':')[1]);
      if (a !== undefined) { sum += a; }
    }
    const n = new NetNode();
    n.id = `tag:${tag}`;
    n.label = tag;
    n.kind = 'tag';
    n.angle = sum / ids.length;
    n.ring = RING_LEAF;
    n.size = 0.7 + ids.length * 0.2;
    n.meta = `${ids.length} 处`;
    g.nodes.push(n);
    for (const id of ids) {
      g.edges.push(edge(id, n.id, 'leaf'));
    }
  });

  // 力导向边：站点两两之间按共享标签数加权。共现越多引力越强，
  // 同主题的收藏自然成团——这是力导向相对同心圆唯一真正多出来的信息。
  const sitePairTags: Map<string, string[]> = new Map();
  tagLinks.forEach((ids: string[], tag: string) => {
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const a = ids[i];
        const b = ids[j];
        const key: string = a < b ? `${a}|${b}` : `${b}|${a}`;
        const cur = sitePairTags.get(key);
        if (cur === undefined) { sitePairTags.set(key, [tag]); }
        else if (!cur.includes(tag)) { cur.push(tag); }
      }
    }
  });
  sitePairTags.forEach((tags: string[], key: string) => {
    const parts: string[] = key.split('|');
    const e = new ForceEdge();
    e.a = parts[0];
    e.b = parts[1];
    e.weight = tags.length;
    g.forces.push(e);
    g.forceTags.set(key, tags);
  });
  // 中心根连每个年代根：让孤立的收藏也被拉回中心，不漂出画布
  for (const n of g.nodes) {
    if (n.kind !== 'era') { continue; }
    const e = new ForceEdge();
    e.a = 'root';
    e.b = n.id;
    e.weight = 1;
    g.forces.push(e);
  }
  const deg = new Map<string, number>();
  for (const e of g.edges) {
    const c = deg.get(e.b);
    deg.set(e.b, c === undefined ? 1 : c + 1);
  }
  for (const n of g.nodes) {
    const c = deg.get(n.id);
    if (c !== undefined) { n.size += c * 0.18; }
  }
  let nEra = 0;
  let nRelic = 0;
  let nTag = 0;
  for (const n of g.nodes) {
    if (n.kind === 'era') { nEra += 1; }
    if (n.kind === 'relic') { nRelic += 1; }
    if (n.kind === 'tag') { nTag += 1; }
  }
  const rowOrder: string[] = [];
  const rowNames = new Map<string, string[]>();
  for (const s of picked) {
    const cur = rowNames.get(s.era);
    if (cur === undefined) { rowNames.set(s.era, [s.name]); rowOrder.push(s.era); }
    else { cur.push(s.name); }
  }
  for (const era of rowOrder) {
    const arr = rowNames.get(era);
    const r = new NetRow();
    r.era = era;
    r.name = eraName(era);
    r.count = arr === undefined ? 0 : arr.length;
    r.names = arr === undefined ? '' : arr.join('、');
    g.rows.push(r);
  }
  g.empty = false;
  g.stat = `遗址 ${picked.length} · 文物 ${nRelic} · 标签 ${nTag} · 年代 ${nEra}`;
  return g;
}

function relicName(sites: SiteInfo[], relicId: string): string {
  for (const s of sites) {
    for (const r of s.relics) {
      if (r.id === relicId) { return r.name; }
    }
  }
  return relicId;
}

// 文物节点自己不带所属遗址（id 只有 relic:{id}），从图上那条
// site → relic 的叶边反查。找不到返回空串。
export function ownerSiteOf(g: NetGraph, relicNodeId: string): string {
  for (const e of g.edges) {
    if (e.b !== relicNodeId) { continue; }
    if (e.a.startsWith('site:')) { return e.a.substring('site:'.length); }
  }
  return '';
}

// ---------------------------------------------------------------- 拓展推荐
// 赛题创新拓展第 1 条：「生成个人知识节点网络……并推荐拓展内容」。
// 网络图本身只描述"已收藏的东西如何相连"，拓展内容 = 顺着这条脉络还能看什么。
// 算法不在这里重写：调用方拿这个种子 id 去 RecoSource.recoRowsFor()，
// 再用 unseenSiteIds() 滤掉图上已有的，剩下的就是"还没进这张图的邻居"。

/**
 * 推荐种子：选中遗址就用它；选中文物退回所属遗址；
 * 选中标签/年代/根、或没选时，取连边最多的遗址（平局按 id 字典序，结果稳定）。
 * 图里没有遗址节点返回空串——此时调用方不该给推荐区，免得凭空冒出一屏无关内容。
 */
export function expansionSeed(g: NetGraph, picked: string): string {
  if (picked.startsWith('site:') && hasSiteNode(g, picked)) {
    return picked;
  }
  if (picked.startsWith('relic:')) {
    const owner: string = ownerSiteOf(g, picked);
    if (owner !== '') { return `site:${owner}`; }
  }
  let bestId: string = '';
  let bestEdges: number = -1;
  for (const n of g.nodes) {
    if (!n.id.startsWith('site:')) { continue; }
    let count = 0;
    for (const e of g.edges) {
      if (e.a === n.id || e.b === n.id) { count++; }
    }
    if (count > bestEdges || (count === bestEdges && n.id < bestId)) {
      bestEdges = count;
      bestId = n.id;
    }
  }
  return bestId;
}

// 按 id 前缀判而不是 kind：kind 只是渲染用的分类，同步/路由/边全用 id。
function hasSiteNode(g: NetGraph, id: string): boolean {
  for (const n of g.nodes) {
    if (n.id === id && n.id.startsWith('site:')) { return true; }
  }
  return false;
}

/** 推荐结果里还没进图的遗址 id，保持输入顺序。 */
export function unseenSiteIds(g: NetGraph, ids: string[]): string[] {
  const inGraph: Set<string> = new Set();
  for (const n of g.nodes) {
    if (n.id.startsWith('site:')) { inGraph.add(n.id.substring('site:'.length)); }
  }
  const out: string[] = [];
  for (const id of ids) {
    if (!inGraph.has(id)) { out.push(id); }
  }
  return out;
}
