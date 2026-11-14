// tools/merge-tests/conflict_label.test.mjs
// 冲突历史的可读标题：合并引擎的逻辑身份是给机器看的键，
// 直接显示用户看到的是「乱码 + 标签名」（␟ 是不可见控制符）。
import test from 'node:test';
import assert from 'node:assert/strict';
import { conflictTitle, conflictContent, conflictTableLabel, KEY_SEP }
  from '../.tsbuild/service/merge/ConflictLabel.ts';
import { mergeElementSets } from '../.tsbuild/service/merge/MergeEngine.ts';

const ver = (t, dev, payload = {}) => ({ updateTime: t, deviceId: dev, isDeleted: false, payload });
const entry = (key, table, w, l) => ({ key, table, winner: w, loser: l, reason: 'updateTime' });

test('关联表的复合键：␟ 拆成可读两部分，不留控制符', () => {
  const e = entry('nmvn75i6l5ql' + KEY_SEP + '研究资料', 'note_tag',
    ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  const t = conflictTitle(e);
  assert.equal(t.includes(KEY_SEP), false, '标题里不得残留 ␟');
  assert.match(t, /^笔记标签 · /);
  assert.match(t, /研究资料$/);
});

test('target_key 形式的段翻译成「对象·xxx」', () => {
  const e = entry('site:yangshao_village' + KEY_SEP + '研究资料', 'favorite_tag',
    ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  assert.match(conflictTitle(e), /遗址·yangshao_village/);
});

test('单列键（笔记/标签/收藏）标题带表名', () => {
  assert.match(conflictTitle(entry('n123', 'note', ver(2, 'B'), ver(1, 'A'))), /^笔记 · n123$/);
  assert.match(conflictTitle(entry('t1', 'tag', ver(2, 'B'), ver(1, 'A'))), /^标签 · t1$/);
  assert.match(conflictTitle(entry('site:x', 'favorite', ver(2, 'B'), ver(1, 'A'))), /^收藏 · /);
});

test('旧日志没有 table 字段时不崩，退回「冲突」', () => {
  const e = { key: 'n1', winner: ver(2, 'B'), loser: ver(1, 'A'), reason: 'updateTime' };
  assert.match(conflictTitle(e), /^冲突 · n1$/);
});

test('未知表名原样透出，不吞信息', () => {
  assert.equal(conflictTableLabel('mystery'), 'mystery');
});

test('冲突内容：胜方与败方正文都能读出来', () => {
  const e = entry('n1', 'note',
    ver(2, 'deviceB', { text: '新版本' }), ver(1, 'deviceA', { text: '旧版本' }));
  assert.equal(conflictContent(e), '旧版本 → 新版本');
});

test('冲突内容：载荷里没有可读列时返回空串（UI 据此不渲染该行）', () => {
  const e = entry('n1', 'note_tag', ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  assert.equal(conflictContent(e), '');
});

test('冲突内容：标签表取 name 列', () => {
  const e = entry('t1', 'tag', ver(2, 'B', { name: '研究资料' }), ver(1, 'A', { name: '待考' }));
  assert.equal(conflictContent(e), '待考 → 研究资料');
});

test('冲突内容：胜败同文时不重复显示箭头', () => {
  const e = entry('n1', 'note', ver(2, 'B', { text: '一样' }), ver(1, 'A', { text: '一样' }));
  assert.equal(conflictContent(e), '一样');
});

test('合并引擎把表名写进冲突条目', () => {
  const rec = (key, t, dev) => ({ key, updateTime: t, deviceId: dev, isDeleted: false, payload: {} });
  const r = mergeElementSets([rec('a', 1, 'A')], [rec('a', 2, 'B')], 'note_tag');
  assert.equal(r.conflicts.length, 1);
  assert.equal(r.conflicts[0].table, 'note_tag');
});

test('不传表名时 table 为空串（不猜）', () => {
  const rec = (key, t, dev) => ({ key, updateTime: t, deviceId: dev, isDeleted: false, payload: {} });
  const r = mergeElementSets([rec('a', 1, 'A')], [rec('a', 2, 'B')]);
  assert.equal(r.conflicts[0].table, '');
});

test('note_id 查得到笔记正文时，标题里显示正文而不是随机 id', () => {
  const map = new Map([['nmvn75i6l5ql', '仰韶探方笔记']]);
  const e = entry('nmvn75i6l5ql' + KEY_SEP + '研究资料', 'note_tag',
    ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  const t = conflictTitle(e, map);
  assert.match(t, /仰韶探方笔记/);
  assert.equal(t.includes('nmvn75i6l5ql'), false, '标题里不得残留 note_id');
});

test('note_id 查不到时退回原值（不吞信息，也不留空）', () => {
  const e = entry('n999' + KEY_SEP + '研究资料', 'note_tag',
    ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  assert.match(conflictTitle(e, new Map()), /n999/);
});

test('单列的 note 键也翻成正文（不只关联表）', () => {
  const map = new Map([['nmvn75i6l5ql', '仰韶探方笔记']]);
  const e = entry('nmvn75i6l5ql', 'note', ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  const t = conflictTitle(e, map);
  assert.match(t, /^笔记 · 仰韶探方笔记$/);
  assert.equal(t.includes('nmvn75i6l5ql'), false);
});

test('单列的 tag 键（标签名本身）不被笔记表误伤', () => {
  const map = new Map([['nmvn75i6l5ql', '仰韶探方笔记']]);
  const e = entry('研究资料', 'tag', ver(2, 'deviceB', {}), ver(1, 'deviceA', {}));
  assert.match(conflictTitle(e, map), /^标签 · 研究资料$/);
});
