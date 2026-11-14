// entry/src/main/ets/service/import/ImportPlan.ets —— 把导出的档案 JSON 变成可落库的写入计划
//
// 纯函数，禁 @kit。为什么导入必须是纯函数：导出把内容写到用户磁盘上，
// 导入则把外部文件写进同步域——两件事都属于「一旦写错就很难撤回」的动作，
// 能被 Node 单测逐字段比对，比在模拟器里点一遍可靠得多。
//
// 与 LWW 的对齐（README「已知限制」承诺过「将来加导入不必改格式」）：
//   导入的每条记录保留导出时的 updateTime 作为同步版本号，**不用本机当前时间
//   重新盖章**。这样：
//   - 本机在导出之后又编辑/删除过同一条 → 本机版本号更新 → LWW 保本机；
//   - 两台设备各导入同一份档案 → 版本号相同、内容相同 → 无论谁赢都收敛；
//   - 本机时钟若慢于导出设备，后续写入会因高水位吸收（observeExternalTime）
//     仍大于导入版本，不会被导入内容整批压住。
//   版本号语义之外的安全规则见各 plan 函数注释：能靠「内容相同」判等的一律
//   跳过，不做无意义的覆盖写入。
import type { FavoriteDO, NoteView, ProgressDO } from '../../model/UserDataModels';
import { SECTIONS } from '../../model/UserDataModels';

// 与 ExportFormat.EXPORT_SCHEMA 同源：只导回本应用自己导出的格式。
// ExportFormat.ets 是导出侧（含渲染），导入侧只认 schema 常量，不引渲染代码。
export const IMPORT_SCHEMA: string = 'huanghe-memory/archive@1';

// 单文件上限：档案只含用户文本，正常远小于 1MB；设 5MB 是防呆
// （选中了别的超大 JSON 时给出明确报错，而不是把解析器撑死）。
export const IMPORT_MAX_BYTES: number = 5 * 1024 * 1024;

export class ImportNote {
  targetKey: string = '';
  text: string = '';
  tags: string[] = [];
  createTime: number = 0;
  updateTime: number = 0;
}

export class ImportFavorite {
  targetKey: string = '';
  tags: string[] = [];
  createTime: number = 0;
}

export class ImportProgress {
  targetKey: string = '';
  section: string = '';
  updateTime: number = 0;
}

export class ImportTag {
  name: string = '';
  isPreset: boolean = false;
  updateTime: number = 0;
  deviceId: string = '';
}

export class ImportGraphNode {
  id: string = '';
  label: string = '';
  kind: string = '';
}

export class ImportGraphEdge {
  a: string = '';
  b: string = '';
}

export class ImportGraph {
  nodes: ImportGraphNode[] = [];
  edges: ImportGraphEdge[] = [];
  stat: string = '';
}

export class ImportParseResult {
  ok: boolean = false;
  // ok=false 时是给人看的一句话，页面直接展示
  error: string = '';
  // 导出档案的设备号：导入记录的 deviceId 用它，平局决胜按原作者算
  deviceId: string = '';
  notes: ImportNote[] = [];
  favorites: ImportFavorite[] = [];
  progress: ImportProgress[] = [];
  tags: ImportTag[] = [];
  graph: ImportGraph = new ImportGraph();
}

function reqNum(o: Record<string, Object>, k: string): number {
  const v = o[k];
  if (typeof v !== 'number' || !Number.isFinite(v) || v <= 0) {
    throw new Error(`字段 ${k} 缺失或不是正数`);
  }
  return v as number;
}

function reqStr(o: Record<string, Object>, k: string): string {
  const v = o[k];
  if (typeof v !== 'string') {
    throw new Error(`字段 ${k} 缺失或不是字符串`);
  }
  return v as string;
}

// 标签清单：只要字符串项，去空、去重；顺序保留（导出侧已按原序）
function tagList(o: Record<string, Object>, k: string): string[] {
  const out: string[] = [];
  const arr = o[k];
  if (!Array.isArray(arr)) { return out; }
  for (const t of arr as Object[]) {
    if (typeof t !== 'string') { continue; }
    const s = (t as string).trim();
    if (s !== '' && !out.includes(s)) { out.push(s); }
  }
  return out;
}

export function parseArchive(raw: string): ImportParseResult {
  const r = new ImportParseResult();
  let o: Record<string, Object>;
  try {
    o = JSON.parse(raw) as Record<string, Object>;
  } catch (_e) {
    r.error = '文件不是合法 JSON，无法识别。';
    return r;
  }
  const schema = o['schema'];
  if (typeof schema !== 'string' || (schema as string) !== IMPORT_SCHEMA) {
    r.error = '这不是「黄河记忆」导出的档案文件（schema 不符）。';
    return r;
  }
  try {
    const dev = o['deviceId'];
    r.deviceId = typeof dev === 'string' ? (dev as string) : '';

    const notes = o['notes'];
    if (Array.isArray(notes)) {
      for (const item of notes as Object[]) {
        const n = item as Record<string, Object>;
        const text = reqStr(n, 'text').trim();
        if (text === '') { continue; } // 与导出同口径：空正文不进档案
        const note = new ImportNote();
        note.targetKey = reqStr(n, 'targetKey');
        note.text = text;
        note.tags = tagList(n, 'tags');
        note.createTime = reqNum(n, 'createTime');
        note.updateTime = reqNum(n, 'updateTime');
        r.notes.push(note);
      }
    }

    const favs = o['favorites'];
    if (Array.isArray(favs)) {
      const seen: string[] = []; // 导出按 createTime 倒序，先见 = 更新
      for (const item of favs as Object[]) {
        const f = item as Record<string, Object>;
        const key = reqStr(f, 'targetKey');
        if (seen.includes(key)) { continue; }
        seen.push(key);
        const fav = new ImportFavorite();
        fav.targetKey = key;
        fav.tags = tagList(f, 'tags');
        fav.createTime = reqNum(f, 'createTime');
        r.favorites.push(fav);
      }
    }

    const progs = o['progress'];
    if (Array.isArray(progs)) {
      const seen: string[] = [];
      for (const item of progs as Object[]) {
        const p = item as Record<string, Object>;
        const key = `${reqStr(p, 'targetKey')}|${reqStr(p, 'section')}`;
        if (seen.includes(key)) { continue; }
        // 导出只含已读段；section 认不出的行跳过，不让一个坏键拖垮整次导入
        if (!SECTIONS.includes(reqStr(p, 'section'))) { continue; }
        seen.push(key);
        const prog = new ImportProgress();
        prog.targetKey = reqStr(p, 'targetKey');
        prog.section = reqStr(p, 'section');
        prog.updateTime = reqNum(p, 'updateTime');
        r.progress.push(prog);
      }
    }

    // 以下两段是 archive@1 后期新增的可选段：旧档案没有 tags/graph 键，
    // 走空数组即可，不能因为缺字段把整份旧档案判成损坏。
    const tags = o['tags'];
    if (Array.isArray(tags)) {
      const seen: string[] = [];
      for (const item of tags as Object[]) {
        const t = item as Record<string, Object>;
        const name = reqStr(t, 'name').trim();
        if (name === '' || seen.includes(name)) { continue; }
        seen.push(name);
        const tag = new ImportTag();
        tag.name = name;
        const preset = t['isPreset'];
        tag.isPreset = preset === true;
        tag.updateTime = reqNum(t, 'updateTime');
        const dev = t['deviceId'];
        tag.deviceId = typeof dev === 'string' ? dev as string : '';
        r.tags.push(tag);
      }
    }

    const g = o['graph'];
    if (g !== null && typeof g === 'object' && !Array.isArray(g)) {
      const go = g as Record<string, Object>;
      const stat = go['stat'];
      r.graph.stat = typeof stat === 'string' ? stat as string : '';
      const gns = go['nodes'];
      if (Array.isArray(gns)) {
        for (const item of gns as Object[]) {
          const n = item as Record<string, Object>;
          const gn = new ImportGraphNode();
          gn.id = reqStr(n, 'id');
          gn.label = reqStr(n, 'label');
          gn.kind = reqStr(n, 'kind');
          r.graph.nodes.push(gn);
        }
      }
      const ges = go['edges'];
      if (Array.isArray(ges)) {
        for (const item of ges as Object[]) {
          const e = item as Record<string, Object>;
          const ge = new ImportGraphEdge();
          ge.a = reqStr(e, 'a');
          ge.b = reqStr(e, 'b');
          r.graph.edges.push(ge);
        }
      }
    }
  } catch (e) {
    r.ok = false;
    const msg: string = e instanceof Error ? e.message : '未知解析错误';
    r.error = `档案内容不完整：${msg}`;
    return r;
  }
  r.ok = true;
  return r;
}

// 导入版本号的最高水位：全部写完后页面调 observeExternalTime 把它吸收进
// 本机单调时钟，保证「导入之后本机再写一笔」的版本号仍严格大于导入内容。
export function maxImportedTime(r: ImportParseResult, exportedAt: number): number {
  let m = exportedAt > 0 ? exportedAt : 0;
  for (const n of r.notes) {
    if (n.updateTime > m) { m = n.updateTime; }
    if (n.createTime > m) { m = n.createTime; }
  }
  for (const f of r.favorites) {
    if (f.createTime > m) { m = f.createTime; }
  }
  for (const p of r.progress) {
    if (p.updateTime > m) { m = p.updateTime; }
  }
  for (const t of r.tags) {
    if (t.updateTime > m) { m = t.updateTime; }
  }
  return m;
}

export class PlannedNote {
  targetKey: string = '';
  text: string = '';
  tags: string[] = [];
  createTime: number = 0;
  updateTime: number = 0;
  // 写入方补：note_id 落库时才生成（依赖本机单调时钟），计划阶段不掺随机量
  deviceId: string = '';
}

export class PlanNotesResult {
  planned: PlannedNote[] = [];
  // 与本机现存内容相同而跳过的条数：给导入报告用
  skipped: number = 0;
}

// 笔记导出时不含 note_id（格式保持稳定的代价），导入按「targetKey + 正文」判重：
//   相同 → 跳过（同一段话没必要存两份，重复导入同一文件因此幂等）；
//   不同 → 视为新笔记新建。导出后被编辑过的笔记导入后会并存两个版本——
//   两个版本都是真实存在过的内容，删哪份应由用户决定，而不是导入替他选。
export function planNoteImports(incoming: ImportNote[], existing: NoteView[],
  deviceId: string): PlanNotesResult {
  const r = new PlanNotesResult();
  const batchSeen: string[] = [];
  for (const n of incoming) {
    const sig = `${n.targetKey}|${n.text}`;
    if (batchSeen.includes(sig)) { r.skipped += 1; continue; }
    batchSeen.push(sig);
    let dup = false;
    for (const e of existing) {
      if (e.targetKey === n.targetKey && e.text.trim() === n.text) { dup = true; break; }
    }
    if (dup) { r.skipped += 1; continue; }
    const p = new PlannedNote();
    p.targetKey = n.targetKey;
    p.text = n.text;
    p.tags = n.tags.slice();
    p.createTime = n.createTime;
    p.updateTime = n.updateTime;
    p.deviceId = deviceId;
    r.planned.push(p);
  }
  return r;
}

export class PlannedFavorite {
  targetKey: string = '';
  tags: string[] = [];
  createTime: number = 0;
  deviceId: string = '';
}

export class PlanFavResult {
  planned: PlannedFavorite[] = [];
  skipped: number = 0;
}

// 收藏按 targetKey 判重：本机已有任何一行（存活或墓碑）都跳过。
//   - 存活行：内容已经收敛（都是「已收藏」），没有可导入的增量；
//   - 墓碑行：本机在导出之后删过它。墓碑版本号 > 导出里的收藏时间
//     （删除必发生在收藏之后），LWW 本来就会保墓碑——导入提前跳过，
//     顺便避免 setFavoriteTags 用旧版本号把标签行写赢墓碑。
export function planFavoriteImports(incoming: ImportFavorite[], live: FavoriteDO[],
  tombstones: FavoriteDO[], deviceId: string): PlanFavResult {
  const r = new PlanFavResult();
  for (const f of incoming) {
    let exists = false;
    for (const l of live) {
      if (l.targetKey === f.targetKey) { exists = true; break; }
    }
    if (!exists) {
      for (const t of tombstones) {
        if (t.targetKey === f.targetKey) { exists = true; break; }
      }
    }
    if (exists) { r.skipped += 1; continue; }
    const p = new PlannedFavorite();
    p.targetKey = f.targetKey;
    p.tags = f.tags.slice();
    p.createTime = f.createTime;
    p.deviceId = deviceId;
    r.planned.push(p);
  }
  return r;
}

export class PlannedProgress {
  targetKey: string = '';
  section: string = '';
  updateTime: number = 0;
  deviceId: string = '';
}

export class PlanProgressResult {
  planned: PlannedProgress[] = [];
  skipped: number = 0;
}

// 进度按 (targetKey, section) 逐行 LWW：
//   - 本机已读过同段 → 内容相同，跳过（无论谁的版本号新）；
//   - 本机行更新（导出后本机又标了已读再取消？取消是 done=false 的新编辑）→ 跳过；
//   - 导出版本严格更新、或本机没有这一行 → 导入 done=true。
// 平局（版本号相同）保本机：多写一笔没有信息量。
export function planProgressImports(incoming: ImportProgress[], local: ProgressDO[],
  deviceId: string): PlanProgressResult {
  const r = new PlanProgressResult();
  for (const p of incoming) {
    let row: ProgressDO | null = null;
    for (const l of local) {
      if (l.targetKey === p.targetKey && l.section === p.section) { row = l; break; }
    }
    if (row !== null && row.done) { r.skipped += 1; continue; }
    if (row !== null && p.updateTime <= row.updateTime) { r.skipped += 1; continue; }
    const plan = new PlannedProgress();
    plan.targetKey = p.targetKey;
    plan.section = p.section;
    plan.updateTime = p.updateTime;
    plan.deviceId = deviceId;
    r.planned.push(plan);
  }
  return r;
}

// ---------------------------------------------------------------- 标签定义
// 笔记/收藏的 tags 字段里只有名字，tag 表本身（含 isPreset / 版本号）也要跟着走。
// 同名即跳过：标签按名字作主键，本机已有的不该被旧版本覆盖。
export class PlannedTag {
  name: string = '';
  isPreset: boolean = false;
  updateTime: number = 0;
  deviceId: string = '';
}

export class PlanTagsResult {
  planned: PlannedTag[] = [];
  skipped: number = 0;
}

export function planTagImports(imported: ImportTag[], localNames: string[],
  deviceId: string): PlanTagsResult {
  const r = new PlanTagsResult();
  // 复制一份再记新名字：调用方传的常是 listTags() 的直接结果，
  // 就地 push 会把本机名单改脏，同一次导入里后面的判重就跟着错。
  const known: string[] = localNames.slice();
  for (const t of imported) {
    if (known.includes(t.name)) { r.skipped += 1; continue; }
    const p = new PlannedTag();
    p.name = t.name;
    p.isPreset = t.isPreset;
    p.updateTime = t.updateTime; // 与笔记同口径：保留导出版本，不重新盖章
    p.deviceId = t.deviceId !== '' ? t.deviceId : deviceId;
    r.planned.push(p);
    known.push(t.name);
  }
  return r;
}
