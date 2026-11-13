// entry/src/main/ets/service/merge/ConflictLabel.ets —— 纯函数，禁 @kit
//
// 为什么需要它：合并引擎认的「逻辑身份」是给机器看的键——
//   note_tag / favorite_tag / progress 三张关联表的 row_id 是
//   两个业务列用 ␟（U+001F）拼接（见 LocalRdbImpl 的 DDL）。
// 直接把 ConflictEntry.key 显示给用户，屏上会出现
//   nmvn75i6l5ql<␟>研究资料
// ␟ 是不可见控制符，人眼看到的是「一串乱码 + 标签名」，
// 既不知道冲突的是哪张表，也不知道那串乱码是什么。
//
// 这里把键翻译成一句人能读懂的话：表名 + 业务标识 + 改动的正文。
import type { ConflictEntry, ConflictVersion } from '../../model/SyncModels';

// 内部逻辑身份的分隔符：两个业务列以它拼接（LocalRdbImpl 的 PAIR_SEP）。
export const KEY_SEP: string = '\u001f';

// 同步域六表的中文名。表名取自 SYNC_TABLES（model/SyncModels）。
const TABLE_LABELS: Record<string, string> = {
  'favorite': '收藏',
  'favorite_tag': '收藏标签',
  'note': '笔记',
  'note_tag': '笔记标签',
  'tag': '标签',
  'progress': '学习进度'
};

// target_key 的两段式：'site:{id}' | 'relic:{id}' | 'notebook:inbox' | 'site:{id}:intro'
// 只取前两段，第三段（分区名）丢掉——用户关心的是「哪个东西」。
function targetLabel(targetKey: string): string {
  const parts: string[] = targetKey.split(':');
  if (parts.length >= 2) {
    const kind: string = parts[0] === 'site' ? '遗址' : (parts[0] === 'relic' ? '文物' : '对象');
    return `${kind}·${parts[1]}`;
  }
  if (targetKey === '') { return ''; }
  return targetKey;
}

// 载荷里能直接当人话看的那一列。笔记是正文、标签是名字、
// 收藏与进度是挂载对象。找不到就返回空串。
function payloadText(v: ConflictVersion): string {
  const p: Record<string, string | number | boolean> = v.payload;
  const text: string = String(p['text'] ?? '');
  if (text !== '') { return text; }
  const name: string = String(p['name'] ?? '');
  if (name !== '') { return name; }
  const target: string = String(p['target_key'] ?? '');
  if (target !== '') { return targetLabel(target); }
  return '';
}

// 一条冲突的标题：表名 + 业务标识。
// 例：「笔记标签 · 仰韶探方笔记 / 研究资料」
//
// noteTexts 把 note_id 翻成笔记正文：note_id 是 'n' + 随机串
// （nmvn75i6l5ql），直接显示用户无从知道是哪条笔记。
export function conflictTitle(entry: ConflictEntry,
  noteTexts: Map<string, string> = new Map()): string {
  // 旧日志（存于 sync_meta 的历史条目）没有 table 字段，取不到就退回「冲突」。
  const table: string = TABLE_LABELS[entry.table] ??
    (entry.table === undefined || entry.table === '' ? '冲突' : entry.table);
  const parts: string[] = entry.key.split(KEY_SEP);
  if (parts.length === 1) {
    // 单列键：note 表的键就是 note_id（随机串），要翻成正文；
    // tag 表的键是标签名、favorite 表的键是 target_key，都已可读。
    return `${table} · ${partLabel(parts[0], noteTexts)}`;
  }
  // 关联表：note_tag(note_id,tag_id) / favorite_tag(target_key,tag_id) / progress(target_key,section)
  const head: string = partLabel(parts[0], noteTexts);
  return `${table} · ${head} / ${parts[1]}`;
}

// 复合键的第一段：target_key 形式翻译成「对象·xxx」，
// note_id 形式查笔记正文表；查不到就退回原值（不吞信息）。
function partLabel(part: string, noteTexts: Map<string, string>): string {
  if (part.indexOf(':') >= 0) { return targetLabel(part); }
  const found: string | undefined = noteTexts.get(part);
  if (found !== undefined && found !== '') { return found; }
  return part;
}

// 冲突改动的正文（胜方与败方的实际内容）。没有可读内容时返回空串。
export function conflictContent(entry: ConflictEntry): string {
  const win: string = payloadText(entry.winner);
  const lose: string = payloadText(entry.loser);
  if (win === '' && lose === '') { return ''; }
  if (win === lose) { return win; }
  return `${lose} → ${win}`;
}

// 表名（中文），用于副标。
export function conflictTableLabel(table: string): string {
  return TABLE_LABELS[table] ?? table;
}
