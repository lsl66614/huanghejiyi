// tools/merge-tests/scheduler.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { runSync } from '../.tsbuild/service/sync/SyncScheduler.ts';
import { LoopbackAdapter } from '../.tsbuild/repository/LoopbackAdapter.ts';

const rec = (key, t, dev, del = false) => ({ key, updateTime: t, deviceId: dev, isDeleted: del, payload: {} });

class FakeRepo {
  constructor(tables, metas = new Map()) { this.tables = tables; this.metas = metas; }
  async snapshotSyncTables() { const m = new Map(); Object.entries(this.tables).forEach(([k, v]) => m.set(k, v)); return m; }
  async applyMerged(table, records) { this.tables[table] = records.map((r) => r); }
  async getMeta(k) { return this.metas.get(k) ?? ''; }
  async setMeta(k, v) { this.metas.set(k, v); }
}

test('A/B 各改同一条笔记 → 同步 → 胜者正确且冲突历史可见败版本 (T3 算法部分)', async () => {
  const repoA = new FakeRepo({ favorite: [rec('n1', 1, 'deviceA')], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const repoB = new FakeRepo({ favorite: [rec('n1', 2, 'deviceB')], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  await runSync('deviceB', repoB, bus); // 播种：B 先把档案推给总线，A 首轮才能看到 n1@2（首轮无冲突）
  const conflicts = await runSync('deviceA', repoA, bus);
  assert.equal(conflicts.length, 1);
  assert.equal(repoA.tables.favorite[0].deviceId, 'deviceB'); // B 时间戳大
  await runSync('deviceB', repoB, bus);
  assert.deepEqual(repoB.tables.favorite.map((r) => [r.key, r.updateTime]), [['n1', 2]]); // 收敛
  const log = JSON.parse(repoA.metas.get('conflictLogJson'));
  assert.equal(log[0].loser.deviceId, 'deviceA');
  assert.ok(Number(repoA.metas.get('lastSyncTime')) > 0);
});

test('首轮对端为空 → 单方纳入无冲突', async () => {
  const repoA = new FakeRepo({ favorite: [rec('f1', 1, 'A')], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  const conflicts = await runSync('deviceA', repoA, bus);
  assert.equal(conflicts.length, 0);
  assert.equal(repoA.tables.favorite.length, 1);
});

test('onProgress 每表回调一次且 total 单调', async () => {
  const repoA = new FakeRepo({ favorite: [], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  const seen = [];
  await runSync('deviceA', repoA, bus, (table, done, total) => { seen.push([table, done, total]); });
  assert.equal(seen.length, 6);
  assert.equal(seen[0][2], 6);
});

test('favorite_tag 复合主键关系行随同步域收敛（F2 分类跨端一致）', async () => {
  // 复合键 (target_key, tag_id) 序列化为 key，双方各贴不同标签 → 并集保留
  const row = (target, tagId, t) => ({ key: `${target}\u001f${tagId}`, updateTime: t, deviceId: 'A', isDeleted: false, payload: { target_key: target, tag_id: tagId } });
  const repoA = new FakeRepo({ favorite: [], favorite_tag: [row('site:bancun', '待实地探访', 1)], note: [], note_tag: [], tag: [], progress: [] });
  const repoB = new FakeRepo({ favorite: [], favorite_tag: [row('site:bancun', '已去过', 2)], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  await runSync('deviceB', repoB, bus);
  await runSync('deviceA', repoA, bus);
  assert.equal(repoA.tables.favorite_tag.length, 2);
  const keys = repoA.tables.favorite_tag.map((r) => r.key).sort();
  assert.deepEqual(keys, [`site:bancun\u001f已去过`, `site:bancun\u001f待实地探访`]);
});

test('同一冲突在后续轮次仍可再次记录（双档案不复历史）', async () => {
  // 回归：早期 LoopbackAdapter.notifyAfterSync 把合并结果同时写回两份 profile，
  // 导致本机下次 sync 取到「已收敛的自己」，同一冲突只出现一次。
  // 现在 profiles 只由对方 exchange 播种，败方版本始终留在历史里。
  const mk = (t, dev) => new FakeRepo(
    { favorite: [rec('n1', t, dev)], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const repoA = mk(1, 'deviceA');
  const repoB = mk(2, 'deviceB');
  const bus = new LoopbackAdapter();
  await runSync('deviceB', repoB, bus);           // 播种
  const c1 = await runSync('deviceA', repoA, bus);
  assert.equal(c1.length, 1);
  // 双方各自再改一次同一条（时间戳仍不同），再次同步应再次产生冲突记录
  repoA.tables.favorite = [rec('n1', 3, 'deviceA')];
  repoB.tables.favorite = [rec('n1', 4, 'deviceB')];
  await runSync('deviceA', repoA, bus);
  const c2 = await runSync('deviceB', repoB, bus);
  assert.equal(c2.length, 1);
  // B 只在自己那次同步里见到分歧（第 3 步 B 未同步），故其历史为 1 条；
  // 关键在于这一条确实产生——旧实现下此时已无冲突可记。
  const log = JSON.parse(repoB.metas.get('conflictLogJson'));
  assert.equal(log.length, 1, 'B 视角应记录本轮冲突');
  // B@4 晚于 A@3，故 B 采信自己、A 的版本落选
  assert.equal(log[0].winner.deviceId, 'deviceB');
  assert.equal(log[0].loser.deviceId, 'deviceA');
});

test('hasPeerProfile：首轮同步前为 false，交换后为 true', async () => {
  const repoA = new FakeRepo({ favorite: [rec('f1', 1, 'A')], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  assert.equal(bus.hasPeerProfile('deviceA'), false);
  await runSync('deviceA', repoA, bus);
  // A 首轮同步只把档案播种给 B；A 自己的对端档案要等 B 同步后才存在
  assert.equal(bus.hasPeerProfile('deviceA'), false);
  assert.equal(bus.hasPeerProfile('deviceB'), true);
});

test('reset 后档案清空，下一轮回到「首轮无冲突」语义', async () => {
  const repoA = new FakeRepo({ favorite: [rec('f1', 1, 'A')], favorite_tag: [], note: [], note_tag: [], tag: [], progress: [] });
  const bus = new LoopbackAdapter();
  await runSync('deviceA', repoA, bus);
  assert.equal(bus.hasPeerProfile('deviceB'), true);
  bus.reset();
  assert.equal(bus.hasPeerProfile('deviceB'), false);
  const c = await runSync('deviceA', repoA, bus);
  assert.equal(c.length, 0);
});
