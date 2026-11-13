// tools/merge-tests/autosync_gate.test.mjs —— 自动同步闸门的节流/幂等判定
//
// AutoSync.ets 因 import NetworkKit 进不了转译体系，其判定逻辑抽到了
// AutoSyncGate.ets（纯函数）。这里逐分支验证，并锁住判定顺序：
// 顺序本身就是语义（冷却窗内的离线请求不该被标 offline，因为根本没到
// 该跑的时刻；in-flight 优先于冷却窗，跑着的时候谈不上冷却）。
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  AUTO_SYNC_COOLDOWN_MS, AutoSyncGateInput, decideAutoSync
} from '../.tsbuild/service/sync/AutoSyncGate.ts';

const NOW = 1_800_000_000_000;

function input(overrides) {
  const i = new AutoSyncGateInput();
  i.realMode = true;
  i.running = false;
  i.lastAt = 0;        // 从未跑过
  i.now = NOW;
  i.online = true;
  return Object.assign(i, overrides);
}

test('真机分布式 + 在线 + 从未跑过 → 放行', () => {
  const d = decideAutoSync(input());
  assert.equal(d.run, true);
  assert.equal(d.reason, 'go');
  assert.equal(d.markOffline, false);
});

test('仿真模式（realMode=false）→ 不跑，且不标离线', () => {
  const d = decideAutoSync(input({ realMode: false, online: false }));
  assert.equal(d.run, false);
  assert.equal(d.reason, 'mode');
  assert.equal(d.markOffline, false, '仿真切离线不该动状态条');
});

test('in-flight 优先于其余一切判定', () => {
  // running 且已过冷却窗且离线：仍是 inflight，不标 offline
  const d = decideAutoSync(input({ running: true, lastAt: NOW - AUTO_SYNC_COOLDOWN_MS - 1, online: false }));
  assert.equal(d.run, false);
  assert.equal(d.reason, 'inflight');
  assert.equal(d.markOffline, false);
});

test('冷却窗内 → 不跑（30 秒只自动同步一次）', () => {
  const d = decideAutoSync(input({ lastAt: NOW - AUTO_SYNC_COOLDOWN_MS + 1 }));
  assert.equal(d.run, false);
  assert.equal(d.reason, 'cooldown');
  // 恰好等于冷却窗的上一毫秒边界：now - lastAt == COOLDOWN_MS 时放行
  const edge = decideAutoSync(input({ lastAt: NOW - AUTO_SYNC_COOLDOWN_MS }));
  assert.equal(edge.run, true);
  assert.equal(edge.reason, 'go');
});

test('冷却窗已过 + 离线 → 不跑，且要标 offline（唯一副作用）', () => {
  const d = decideAutoSync(input({ lastAt: NOW - AUTO_SYNC_COOLDOWN_MS - 1, online: false }));
  assert.equal(d.run, false);
  assert.equal(d.reason, 'offline');
  assert.equal(d.markOffline, true);
});

test('lastAt=0（首次启动）不落冷却窗：真实墙钟下 now - 0 远大于 30 秒', () => {
  const d = decideAutoSync(input({ lastAt: 0 }));
  assert.equal(d.run, true);
  assert.equal(d.reason, 'go');
});

test('网络抖动序列：恢复 → 30 秒内再次触发 → 被冷却窗吃掉', () => {
  const first = decideAutoSync(input());
  assert.equal(first.run, true);
  // 第一次跑完后：running=false（已完成）、lastAt=触发时刻。
  // 5 秒后网络又抖一下 netAvailable：应被冷却。
  const again = decideAutoSync(input({ lastAt: NOW, now: NOW + 5000 }));
  assert.equal(again.run, false);
  assert.equal(again.reason, 'cooldown');
  // 31 秒后：放行
  const later = decideAutoSync(input({ lastAt: NOW, now: NOW + AUTO_SYNC_COOLDOWN_MS + 1000 }));
  assert.equal(later.run, true);
});
