// service/notes/NoteReview.ets —— 笔记回顾与相关笔记的选取规则
//
// 两条规则都是纯函数，页面只负责画：
//
//   回顾：从「放旧了的」笔记里按日期挑一条。同一自然日必须挑到同一条，
//         否则用户刷新一次就换一条，回顾变成抽奖，也就没人把它当回顾。
//         所以哈希的输入只有日期字符串，笔记池先按 noteId 排好序——
//         读取顺序、插入顺序都不影响结果。
//
//   相关：同一处遗址的笔记排在前面，其次是共享标签的笔记。
//         排序先看重叠标签数、再看更新时间，理由能直接写在行里
//         （「本页笔记」/「同标签 · 待实地探访」），不做黑箱推荐。
// 只做类型引用：用 import type，转译成 .ts 交给 Node 跑单测时不会被当成运行时导入。
import type { NoteView } from '../../model/UserDataModels';

export const DAY_MS: number = 86400000;

// 「放旧」的门槛。低于这个时长的笔记还在用户手边，翻出来没有价值。
export const REVIEW_STALE_DAYS: number = 14;
// 「记住了」：一个月内不再翻到同一条。足够长，但不等于永久删除。
// 「下次再说」没有独立常量——它到当晚 24:00 失效，由 dayEnd() 给出，见页面。
export const REVIEW_KEEP_DAYS: number = 30;

class ScoredNote {
  note: NoteView | null = null;
  overlap: number = 0;
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

// 本地日期键。不用 toISOString：那是 UTC，晚上八点之后会跳到第二天，
// 东八区用户会在同一天的晚上看到「今天的回顾」被换掉。
export function dayKeyOf(now: number): string {
  const d = new Date(now);
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

// 当天 24:00 的毫秒数。用于「明天再说」这种到点失效的搁置。
export function dayEnd(now: number): number {
  const d = new Date(now);
  d.setHours(24, 0, 0, 0);
  return d.getTime();
}

export function hashText(s: string): number {
  let h: number = 7;
  for (let i = 0; i < s.length; i++) {
    h = (h * 31 + s.charCodeAt(i)) % 1000000007;
  }
  return h;
}

// ---------------------------------------------------------------- 搁置记录
// 存成纯文本行，不存 JSON：这条记录只有「谁、到什么时候」两个字段，
// 上 JSON 只是把解析失败的可能性也一起存进去。格式：id|until，一行一条。
export function dismissedIds(raw: string, now: number): string[] {
  const out: string[] = [];
  const lines: string[] = raw.split('\n');
  for (const line of lines) {
    const parts: string[] = line.split('|');
    if (parts.length !== 2 || parts[0] === '') { continue; }
    const until = Number(parts[1]);
    if (!Number.isFinite(until) || until <= now) { continue; }
    out.push(parts[0]);
  }
  return out;
}

export function withDismissed(raw: string, noteId: string, until: number, now: number): string {
  const lines: string[] = [];
  const kept = raw.split('\n');
  for (const line of kept) {
    const parts: string[] = line.split('|');
    if (parts.length !== 2 || parts[0] === '' || parts[0] === noteId) { continue; }
    const t = Number(parts[1]);
    if (!Number.isFinite(t) || t <= now) { continue; }
    lines.push(`${parts[0]}|${t}`);
  }
  lines.push(`${noteId}|${until}`);
  return lines.join('\n');
}

// ---------------------------------------------------------------- 今日回顾
export function dailyReviewNote(notes: NoteView[], day: string, now: number,
  dismissed: string[]): NoteView | null {
  const pool: NoteView[] = [];
  for (const n of notes) {
    if (n.text.trim() === '') { continue; }
    if (dismissed.indexOf(n.noteId) >= 0) { continue; }
    pool.push(n);
  }
  if (pool.length === 0) { return null; }

  // 先挑「放旧了」的；都是新笔记时退回全池——新用户也该有东西可翻。
  const stale: NoteView[] = [];
  for (const n of pool) {
    if (now - n.updateTime >= REVIEW_STALE_DAYS * DAY_MS) { stale.push(n); }
  }
  const from: NoteView[] = stale.length > 0 ? stale : pool;
  const sorted: NoteView[] = from.slice();
  sorted.sort((a: NoteView, b: NoteView): number => {
    if (a.noteId < b.noteId) { return -1; }
    if (a.noteId > b.noteId) { return 1; }
    return 0;
  });
  return sorted[hashText(day) % sorted.length];
}

// ---------------------------------------------------------------- 相关笔记
export function isSameTarget(targetKey: string, prefix: string): boolean {
  if (prefix === '') { return false; }
  return targetKey === prefix || targetKey.indexOf(`${prefix}:`) === 0;
}

function newestFirst(a: NoteView, b: NoteView): number {
  if (a.updateTime !== b.updateTime) { return b.updateTime - a.updateTime; }
  if (a.noteId < b.noteId) { return -1; }
  if (a.noteId > b.noteId) { return 1; }
  return 0;
}

// 同一处遗址（含五段分节）的笔记上挂过的标签集合。
// 行里的「同标签 · X」就是从这里取的，取不到就不写这条理由。
export function sameTargetTags(notes: NoteView[], prefix: string): string[] {
  const out: string[] = [];
  for (const n of notes) {
    if (!isSameTarget(n.targetKey, prefix)) { continue; }
    for (const t of n.tagIds) {
      if (out.indexOf(t) < 0) { out.push(t); }
    }
  }
  return out;
}

export function relatedNotes(notes: NoteView[], prefix: string, max: number): NoteView[] {
  if (prefix === '' || max <= 0) { return []; }
  const same: NoteView[] = [];
  const others: NoteView[] = [];
  for (const n of notes) {
    if (n.text.trim() === '') { continue; }
    if (isSameTarget(n.targetKey, prefix)) {
      same.push(n);
    } else {
      others.push(n);
    }
  }
  same.sort(newestFirst);

  const tags: string[] = sameTargetTags(notes, prefix);
  const scored: ScoredNote[] = [];
  for (const n of others) {
    let overlap: number = 0;
    for (const t of n.tagIds) {
      if (tags.indexOf(t) >= 0) { overlap++; }
    }
    if (overlap > 0) {
      const s = new ScoredNote();
      s.note = n;
      s.overlap = overlap;
      scored.push(s);
    }
  }
  scored.sort((a: ScoredNote, b: ScoredNote): number => {
    if (a.overlap !== b.overlap) { return b.overlap - a.overlap; }
    return newestFirst(a.note as NoteView, b.note as NoteView);
  });

  const out: NoteView[] = [];
  for (const n of same) {
    if (out.length >= max) { return out; }
    out.push(n);
  }
  for (const s of scored) {
    if (out.length >= max) { break; }
    out.push(s.note as NoteView);
  }
  return out;
}
