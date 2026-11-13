// tools/merge-tests/logical_clock.test.mjs
//
// 逻辑时钟是「同步裁决正确性」的地基：本机写入必须严格单调，否则同一毫秒
// 连写两次会拿到并列时间戳，LWW 平局退到 deviceId 字典序，与真实因果无关。
// 这里只测纯函数（高水位持久化在 LocalRdbImpl，需要真机 RDB，不在 Node 覆盖范围）。
import test from 'node:test';
import assert from 'node:assert/strict';
import { monotonicNow, monotonicSeries } from '../.tsbuild/service/merge/LogicalClock.ts';

test('墙钟前进：直接取墙钟', () => {
  assert.equal(monotonicNow(1000, 2000), 2000);
});

test('墙钟回拨：取高水位 + 1，严格大于上次写入', () => {
  assert.equal(monotonicNow(5000, 1200), 5001);
});

test('墙钟与高水位相等：仍然严格递增（同一毫秒连写）', () => {
  assert.equal(monotonicNow(7000, 7000), 7001);
});

test('首次写入（高水位 0）：取墙钟', () => {
  assert.equal(monotonicNow(0, 1767225600000), 1767225600000);
});

test('连续写入序列严格递增，且每次都吃满「被回拨的墙钟」', () => {
  const series = monotonicSeries(1000, 50);
  for (let i = 1; i < series.length; i++) {
    assert.ok(series[i] > series[i - 1], `第 ${i} 项 ${series[i]} 未严格大于前一项 ${series[i - 1]}`);
  }
});

test('吸收远端更大的时间戳后，本地写入继续递增（LWW 不会反被压住）', () => {
  // 模拟：本机时钟 1000，从对端合并进来一条 updateTime=9000 的记录，
  // 高水位被抬到 9000，下一次本地写入必须 > 9000，否则会立刻输给那条记录。
  const observed = Math.max(1000, 9000);
  assert.equal(monotonicNow(observed, 1000), 9001);
});

test('合并进来的时间戳不大于高水位时，不回退', () => {
  const observed = Math.max(9000, 8000);
  assert.equal(observed, 9000);
  assert.equal(monotonicNow(observed, 9000), 9001);
});
