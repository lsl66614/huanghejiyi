// tools/merge-tests/notereview.test.mjs —— P2-4：今日回顾的稳定性与相关笔记的排序
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DAY_MS, REVIEW_KEEP_DAYS, REVIEW_STALE_DAYS, dailyReviewNote, dayEnd, dayKeyOf,
  dismissedIds, hashText, isSameTarget, relatedNotes, sameTargetTags, withDismissed
} from '../.tsbuild/service/notes/NoteReview.ts';

const NOTE = (id, targetKey, text, updateTime, tagIds = []) =>
  ({ noteId: id, targetKey, text, createTime: updateTime, updateTime, tagIds });

// 固定到某个本地日期，避免测试跑在午夜前后时 dayKey 变化。
const NOON = new Date(2026, 9, 28, 12, 0, 0, 0).getTime();

test('dayKeyOf：按本地日期，不受 UTC 偏移影响', () => {
  assert.equal(dayKeyOf(NOON), '2026-10-28');
  // 当天 23:30 仍属于 28 日；用 toISOString 会跳到 29 日
  assert.equal(dayKeyOf(new Date(2026, 9, 28, 23, 30).getTime()), '2026-10-28');
  assert.equal(dayKeyOf(new Date(2026, 0, 1, 0, 0).getTime()), '2026-01-01');
});

test('dayEnd：当天最后一毫秒之后才是次日', () => {
  const end = dayEnd(NOON);
  assert.equal(dayKeyOf(end - 1), '2026-10-28');
  assert.equal(dayKeyOf(end), '2026-10-29');
});

test('dailyReviewNote：同一天同一池必得同一条，与输入顺序无关', () => {
  const notes = [
    NOTE('n3', 'site:a', '三', NOON - 40 * DAY_MS),
    NOTE('n1', 'site:b', '一', NOON - 30 * DAY_MS),
    NOTE('n2', 'notebook:inbox', '二', NOON - 20 * DAY_MS)
  ];
  const first = dailyReviewNote(notes, '2026-10-28', NOON, []);
  const reversed = dailyReviewNote(notes.slice().reverse(), '2026-10-28', NOON, []);
  assert.ok(first !== null);
  assert.equal(first.noteId, reversed.noteId);
  // 结果落在「放旧」的子池里，不会翻到还在手边的新笔记
  assert.ok(['n1', 'n2', 'n3'].includes(first.noteId));
});

test('dailyReviewNote：优先放旧的笔记；新笔记只在没有旧笔记时入选', () => {
  const oldNote = NOTE('old', 'site:a', '很久以前', NOON - (REVIEW_STALE_DAYS + 1) * DAY_MS);
  const fresh = NOTE('fresh', 'site:a', '刚写完', NOON - DAY_MS);
  for (const day of ['2026-10-28', '2026-10-29', '2026-10-30', '2026-11-01']) {
    const pick = dailyReviewNote([fresh, oldNote], day, NOON, []);
    assert.equal(pick.noteId, 'old', `${day} 不该翻到新笔记`);
  }
  // 池里只有新笔记时退回全池，而不是空手
  assert.equal(dailyReviewNote([fresh], '2026-10-28', NOON, []).noteId, 'fresh');
});

test('dailyReviewNote：搁置中的笔记不出现；全被搁置时返回 null；空正文跳过', () => {
  const notes = [
    NOTE('n1', 'site:a', '一', NOON - 30 * DAY_MS),
    NOTE('n2', 'site:a', '二', NOON - 30 * DAY_MS),
    NOTE('n3', 'site:a', '   ', NOON - 30 * DAY_MS)
  ];
  const one = dailyReviewNote(notes, '2026-10-28', NOON, ['n2']);
  assert.notEqual(one.noteId, 'n2');
  assert.equal(dailyReviewNote(notes, '2026-10-28', NOON, ['n1', 'n2', 'n3']), null);
  assert.deepEqual(dailyReviewNote([], '2026-10-28', NOON, []), null);
});

test('dismissedIds / withDismissed：解析容错、过期清理、同 id 覆盖', () => {
  const now = NOON;
  const raw = `n1|${now + DAY_MS}\nbroken\nn2|${now - DAY_MS}\n|${now + DAY_MS}`;
  assert.deepEqual(dismissedIds(raw, now), ['n1']);

  const next = withDismissed(raw, 'n3', now + 7 * DAY_MS, now);
  assert.deepEqual(dismissedIds(next, now).sort(), ['n1', 'n3']);
  // 过期条目在写入时一并清掉，不做无界增长
  assert.ok(!next.includes('n2'));

  const replaced = withDismissed(next, 'n1', now + 2 * DAY_MS, now);
  assert.deepEqual(dismissedIds(replaced, now).sort(), ['n1', 'n3']);
  assert.ok(replaced.includes(`n1|${now + 2 * DAY_MS}`));
  // 「记住了」的 30 天档确实还在有效期内
  const kept = withDismissed('', 'n9', now + REVIEW_KEEP_DAYS * DAY_MS, now);
  assert.deepEqual(dismissedIds(kept, now), ['n9']);
});

test('hashText：同串同值，且为非负整数（可直接取模）', () => {
  assert.equal(hashText('2026-10-28'), hashText('2026-10-28'));
  for (const s of ['2026-10-28', '2026-01-01', 'x', '']) {
    const h = hashText(s);
    assert.ok(Number.isInteger(h) && h >= 0, `${s} → ${h}`);
  }
});

test('isSameTarget：整条与分节都算同一处，前缀相同但不是分节的不算', () => {
  assert.equal(isSameTarget('site:a', 'site:a'), true);
  assert.equal(isSameTarget('site:a:arch', 'site:a'), true);
  assert.equal(isSameTarget('site:ab', 'site:a'), false);
  assert.equal(isSameTarget('relic:a', 'site:a'), false);
  assert.equal(isSameTarget('site:a', ''), false);
});

test('relatedNotes：本页笔记在前，其次按标签重叠数与时间排，最多三条', () => {
  const notes = [
    NOTE('x1', 'site:a:arch', '本页考古', NOON - 3 * DAY_MS, ['待实地探访']),
    NOTE('x2', 'site:a', '本页整条', NOON - DAY_MS, ['研究资料']),
    NOTE('t2', 'site:b', '共享一个标签', NOON - 2 * DAY_MS, ['待实地探访']),
    NOTE('t1', 'site:c', '共享两个标签', NOON - 9 * DAY_MS, ['待实地探访', '研究资料']),
    NOTE('u1', 'site:d', '没有共同标签', NOON, ['已去过']),
    NOTE('e1', 'site:a', '   ', NOON, ['待实地探访'])
  ];
  const out = relatedNotes(notes, 'site:a', 3);
  assert.deepEqual(out.map((n) => n.noteId), ['x2', 'x1', 't1']);
  assert.deepEqual(sameTargetTags(notes, 'site:a').sort(), ['研究资料', '待实地探访'].sort());

  // max 小于本页笔记数时只取最近的几条；未知条目、空前缀都安全返回
  assert.deepEqual(relatedNotes(notes, 'site:a', 1).map((n) => n.noteId), ['x2']);
  assert.deepEqual(relatedNotes(notes, 'site:none', 3).map((n) => n.noteId), []);
  assert.deepEqual(relatedNotes(notes, '', 3), []);
  assert.deepEqual(relatedNotes(notes, 'site:a', 0), []);
});
