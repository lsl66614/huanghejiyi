// tools/merge-tests/merge_engine.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { mergeElementSets, appendConflictLog } from '../.tsbuild/service/merge/MergeEngine.ts';

const rec = (key, t, dev, del = false, extra = {}) => ({
  key, updateTime: t, deviceId: dev, isDeleted: del, payload: extra,
});

test('单方有 → 直接纳入', () => {
  const r = mergeElementSets([rec('a', 1, 'A')], [rec('b', 1, 'B')]);
  assert.deepEqual(r.finalRecords.map((x) => x.key).sort(), ['a', 'b']);
  assert.equal(r.conflicts.length, 0);
});

test('双方均有 → updateTime 大者胜，记冲突', () => {
  const r = mergeElementSets([rec('a', 1, 'A', false, { v: 'old' })], [rec('a', 2, 'B', false, { v: 'new' })]);
  assert.equal(r.finalRecords.length, 1);
  assert.equal(r.finalRecords[0].payload.v, 'new');
  assert.equal(r.conflicts.length, 1);
  assert.equal(r.conflicts[0].loser.payload.v, 'old');
  assert.equal(r.conflicts[0].reason, 'updateTime');
});

test('时间戳相等 → deviceId 字典序大者胜，reason=tie_break_deviceId', () => {
  const r = mergeElementSets([rec('a', 5, 'deviceA')], [rec('a', 5, 'deviceB')]);
  assert.equal(r.finalRecords[0].deviceId, 'deviceB');
  assert.equal(r.conflicts[0].reason, 'tie_break_deviceId');
});

test('完全相同记录（同 deviceId 同时间同墓碑态）→ 无冲突', () => {
  const r = mergeElementSets([rec('a', 5, 'A')], [rec('a', 5, 'A')]);
  assert.equal(r.conflicts.length, 0);
  assert.equal(r.finalRecords.length, 1);
});

test('墓碑 vs 存活 → 仍按时间戳裁决（删除是最后一次编辑）', () => {
  const r = mergeElementSets([rec('a', 3, 'A', false)], [rec('a', 4, 'B', true)]);
  assert.equal(r.finalRecords[0].isDeleted, true);
  const r2 = mergeElementSets([rec('a', 9, 'A', false)], [rec('a', 4, 'B', true)]);
  assert.equal(r2.finalRecords[0].isDeleted, false);
});

// 回归：合并终态必须是 local ∪ remote 的键集，墓碑行也算“存在的行”。
// applyMerged 曾经按「终态里没有的 key」删本地行；只要终态漏掉一个键
// （或该键是快照拍完之后新写入的），这条规则就会静默删数据。
// 删除语义靠 isDeleted 表达，不靠“行不存在”，此测试锁住并集与墓碑。
test('合并终态覆盖双方全部 key，且保留墓碑行', () => {
  const local = [rec('keep-local', 1, 'A'), rec('gone-local', 2, 'A', true)];
  const remote = [rec('keep-remote', 1, 'B'), rec('gone-remote', 2, 'B', true)];
  const r = mergeElementSets(local, remote, 'note');
  const keys = new Set(r.finalRecords.map((x) => x.key));
  for (const k of ['keep-local', 'gone-local', 'keep-remote', 'gone-remote']) {
    assert.ok(keys.has(k), `合并终态漏掉 ${k}`);
  }
  const tomb = r.finalRecords.find((x) => x.key === 'gone-remote');
  assert.equal(tomb.isDeleted, true);
});

test('输出按 key 字典序确定排列', () => {
  const r = mergeElementSets([rec('z', 1, 'A'), rec('a', 1, 'A')], [rec('m', 1, 'B')]);
  assert.deepEqual(r.finalRecords.map((x) => x.key), ['a', 'm', 'z']);
});

test('appendConflictLog 滚动上限 50，新条目在尾部', () => {
  const e = (k) => ({ key: k, winner: rec(k, 2, 'B'), loser: rec(k, 1, 'A'), reason: 'updateTime' });
  let json = '[]';
  for (let i = 0; i < 60; i++) json = appendConflictLog(json, [e('k' + i)], 50);
  const log = JSON.parse(json);
  assert.equal(log.length, 50);
  assert.equal(log[49].key, 'k59');
  assert.equal(log[0].key, 'k10');
});

test('appendConflictLog 容忍空/坏 existingJson', () => {
  const one = [{ key: 'x', winner: rec('x', 2, 'B'), loser: rec('x', 1, 'A'), reason: 'updateTime' }];
  assert.equal(JSON.parse(appendConflictLog('', one, 50)).length, 1);
  assert.equal(JSON.parse(appendConflictLog('not-json', one, 50)).length, 1);
});

test('appendConflictLog 容忍非数组 JSON（损坏的 sync_meta 行按空日志处理）', () => {
  const one = [{ key: 'x', winner: rec('x', 2, 'B'), loser: rec('x', 1, 'A'), reason: 'updateTime' }];
  assert.equal(JSON.parse(appendConflictLog('{"a":1}', one, 50)).length, 1);
  assert.equal(JSON.parse(appendConflictLog('"str"', one, 50)).length, 1);
  assert.equal(JSON.parse(appendConflictLog('null', one, 50)).length, 1);
});
