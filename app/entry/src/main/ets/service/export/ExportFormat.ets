// service/export/ExportFormat.ets —— 把本机档案格式化成可读文本 / 可留档 JSON
//
// 为什么要「先建中间结构，再分别渲染」：
//   Markdown 与 JSON 导出的必须是同一份内容，否则用户按格式各导一次会发现
//   条数对不上。buildArchive() 负责取数、排序、过滤，两种渲染只做排版。
//
// 为什么渲染必须是纯函数：导出是「一旦写错就写到用户磁盘上」的动作，
// 它能被 Node 单测逐字比对，比在模拟器里点一遍可靠得多。
import type { FavoriteDO, FavoriteTagDO, NoteView, ProgressDO } from '../../model/UserDataModels';
import { pad2, stamp } from '../../common/Time';
import { sectionLabelOf, TargetLabels } from '../content/TargetLabel';

export const EXPORT_SCHEMA: string = 'huanghe-memory/archive@1';
export const FORMAT_MD: string = 'md';
export const FORMAT_JSON: string = 'json';

export class ExportNote {
  targetKey: string = '';
  label: string = '';
  text: string = '';
  tags: string[] = [];
  createTime: number = 0;
  updateTime: number = 0;
}

export class ExportFavorite {
  targetKey: string = '';
  label: string = '';
  tags: string[] = [];
  createTime: number = 0;
}

export class ExportProgress {
  targetKey: string = '';
  label: string = '';
  section: string = '';
  done: boolean = false;
  updateTime: number = 0;
}

// 自建标签的定义：笔记/收藏的 tags 里只有名字，没有它的话导到另一台设备
// 只能看到标签名、却进不了「标签管理」。预置三标签也带上，便于对方核对。
export class ExportTag {
  name: string = '';
  isPreset: boolean = false;
  updateTime: number = 0;
  deviceId: string = '';
}

export class ExportGraphNode {
  id: string = '';
  label: string = '';
  kind: string = '';
}

export class ExportGraphEdge {
  a: string = '';
  b: string = '';
}

// 知识图谱快照：图本身由收藏/笔记/标签派生，落库时不需要逐节点重建，
// 但「完整迁移」要求档案能自带这张图的结构，供对端核对与展示。
export class ExportGraph {
  nodes: ExportGraphNode[] = [];
  edges: ExportGraphEdge[] = [];
  stat: string = '';
}

export class ExportCounts {
  notes: number = 0;
  favorites: number = 0;
  progress: number = 0;
  tags: number = 0;
}

export class ExportArchive {
  app: string = '黄河记忆';
  schema: string = EXPORT_SCHEMA;
  exportedAt: number = 0;
  deviceId: string = '';
  counts: ExportCounts = new ExportCounts();
  notes: ExportNote[] = [];
  favorites: ExportFavorite[] = [];
  progress: ExportProgress[] = [];
  tags: ExportTag[] = [];
  graph: ExportGraph = new ExportGraph();
}

export function archiveName(deviceId: string): string {
  // 设备类型词与赛题原文对齐（原文写"手机、平板等多设备间自动同步"）：
  // 仿真里 deviceA=手机、deviceB=平板，导出件与屏幕同一套说法。
  if (deviceId === 'deviceA') { return '手机'; }
  if (deviceId === 'deviceB') { return '平板'; }
  return deviceId === '' ? '本机' : deviceId;
}

function tagsText(tags: string[]): string {
  return tags.length === 0 ? '未贴标签' : tags.join('、');
}

function favoriteTagMap(rows: FavoriteTagDO[]): Map<string, string[]> {
  const m: Map<string, string[]> = new Map();
  for (const r of rows) {
    const cur: string[] | undefined = m.get(r.targetKey);
    if (cur === undefined) {
      m.set(r.targetKey, [r.tagId]);
    } else {
      cur.push(r.tagId);
    }
  }
  return m;
}

// 最近删除的墓碑不进导出：用户已经把那条划掉了，导出的应该是「现在留下的」。
export function buildArchive(notes: NoteView[], favorites: FavoriteDO[], favTags: FavoriteTagDO[],
  progress: ProgressDO[], labels: TargetLabels, deviceId: string, now: number,
  tags: ExportTag[] = [], graph: ExportGraph | null = null): ExportArchive {
  const a = new ExportArchive();
  a.exportedAt = now;
  a.deviceId = deviceId;

  const ns: ExportNote[] = [];
  for (const n of notes) {
    if (n.text.trim() === '') { continue; }
    const e = new ExportNote();
    e.targetKey = n.targetKey;
    e.label = labels.label(n.targetKey);
    e.text = n.text.trim();
    e.tags = n.tagIds.slice();
    e.createTime = n.createTime;
    e.updateTime = n.updateTime;
    ns.push(e);
  }
  ns.sort((x: ExportNote, y: ExportNote): number => y.updateTime - x.updateTime);
  a.notes = ns;

  const tagMap: Map<string, string[]> = favoriteTagMap(favTags);
  const fs: ExportFavorite[] = [];
  for (const f of favorites) {
    const e = new ExportFavorite();
    e.targetKey = f.targetKey;
    e.label = labels.label(f.targetKey);
    const t: string[] | undefined = tagMap.get(f.targetKey);
    e.tags = t === undefined ? [] : t.slice();
    e.createTime = f.createTime;
    fs.push(e);
  }
  fs.sort((x: ExportFavorite, y: ExportFavorite): number => y.createTime - x.createTime);
  a.favorites = fs;

  // 只导「已读」的段：done=false 的行是「还没读」的占位，
  // 导出去会让读者以为那是一份待办清单。
  const ps: ExportProgress[] = [];
  for (const p of progress) {
    if (!p.done) { continue; }
    const e = new ExportProgress();
    e.targetKey = p.targetKey;
    e.label = `${labels.label(p.targetKey)} · ${sectionLabelOf(p.section)}`;
    e.section = p.section;
    e.done = p.done;
    e.updateTime = p.updateTime;
    ps.push(e);
  }
  ps.sort((x: ExportProgress, y: ExportProgress): number => y.updateTime - x.updateTime);
  a.progress = ps;

  const c = new ExportCounts();
  c.notes = ns.length;
  c.favorites = fs.length;
  c.progress = ps.length;
  c.tags = tags.length;
  a.counts = c;
  a.tags = tags.slice();
  a.graph = graph === null ? new ExportGraph() : graph;
  return a;
}

// 紧凑 JSON：字段顺序由类的声明顺序固定，跨版本 diff 时不会整篇错位。
export function exportJson(a: ExportArchive): string {
  return JSON.stringify(a);
}

export function exportMarkdown(a: ExportArchive): string {
  const L: string[] = [];
  L.push('# 黄河记忆 · 我的档案');
  L.push('');
  L.push(`- 导出时间：${stamp(a.exportedAt)}`);
  L.push(`- 档案：${archiveName(a.deviceId)}`);
  L.push(`- 内容：笔记 ${a.counts.notes} 条 · 收藏 ${a.counts.favorites} 条 · 已读 ${a.counts.progress} 段`);
  L.push('');
  L.push('本文件由「黄河记忆」在本机生成，只含你写下的内容；预置语料不在其中。');
  L.push('');

  L.push('## 笔记');
  L.push('');
  if (a.notes.length === 0) {
    L.push('（没有笔记）');
    L.push('');
  }
  for (const n of a.notes) {
    L.push(`### ${n.label}`);
    L.push('');
    L.push(`- 更新：${stamp(n.updateTime)}`);
    L.push(`- 标签：${tagsText(n.tags)}`);
    L.push(`- 关联：\`${n.targetKey}\``);
    L.push('');
    // 正文用引用块：笔记里若有一行以 # 开头，直接铺成段落会被渲染成标题，
    // 整篇结构就乱了；引用块按行前缀，多行与空行都能原样保留。
    for (const line of n.text.split('\n')) {
      L.push(line === '' ? '>' : `> ${line}`);
    }
    L.push('');
  }

  L.push('## 收藏');
  L.push('');
  if (a.favorites.length === 0) {
    L.push('（没有收藏）');
    L.push('');
  }
  for (const f of a.favorites) {
    L.push(`- **${f.label}** —— 收于 ${stamp(f.createTime)}`);
    L.push(`  - 标签：${tagsText(f.tags)}`);
    L.push(`  - 关联：\`${f.targetKey}\``);
  }
  L.push('');

  L.push('## 研读进度');
  L.push('');
  if (a.progress.length === 0) {
    L.push('（还没有读过任何一段）');
    L.push('');
  }
  for (const p of a.progress) {
    L.push(`- ${p.label}（${stamp(p.updateTime)}）`);
  }
  L.push('');
  return L.join('\n');
}

// 文件名带本地时间到分：连续导出两次不会互相覆盖，也看得出是哪一版。
export function exportFileName(now: number, format: string): string {
  const d = new Date(now);
  const date: string = `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
  const time: string = `${pad2(d.getHours())}${pad2(d.getMinutes())}`;
  return `huanghe-memory-${date}-${time}.${format}`;
}
