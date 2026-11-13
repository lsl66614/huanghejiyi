// tools/merge-tests/recommend.test.mjs —— F5：浏览+收藏混合行为序列与全局推荐
import test from 'node:test';
import assert from 'node:assert/strict';
import { mixedHistory, globalRows, recoRowsFor, interestRows } from '../.tsbuild/service/recommend/RecoSource.ts';
import { diversify, recommend } from '../.tsbuild/service/recommend/RecommendService.ts';

const site = (id, era, city = 'luoyang', siteType = 'capital', tags = []) =>
  ({ id, name: id, era, city, siteType, tags, relics: [] });
const fav = (targetKey, updateTime) => ({ targetKey, updateTime });
const visit = (targetKey, createTime) => ({ targetKey, createTime });

test('mixedHistory：浏览优先于收藏、站点去重、文物键被忽略', () => {
  const sites = [site('a', 'song'), site('b', 'zhou'), site('c', 'hantang')];
  const visits = [visit('site:b', 200), visit('relic:r1', 190), visit('site:a', 180), visit('site:b', 170)];
  const favs = [fav('site:a', 100), fav('site:c', 90)];
  const h = mixedHistory(favs, visits, sites);
  assert.deepEqual(h.map((x) => x.id), ['b', 'a', 'c']);
});

test('globalRows：有浏览时以最近浏览遗址为种子；无任何行为时回落语料首条', () => {
  // 两条同年代：零分候选已不进结果，若两条毫无共性，这里会得到空列表
  // 而测不到“种子自身不入推荐”这句话。
  const sites = [site('a', 'zhou'), site('b', 'zhou')];
  const g1 = globalRows(sites, [], [visit('site:b', 200)], 5);
  assert.equal(g1.hasBehavior, true);
  assert.equal(g1.seedId, 'b');
  assert.ok(g1.rows.length > 0);
  assert.ok(!g1.rows.some((r) => r.id === 'b')); // 种子自身不入推荐

  const g2 = globalRows(sites, [], [], 5);
  assert.equal(g2.hasBehavior, false);
  assert.equal(g2.seedId, 'a');
});

test('interestRows：只返回所选年代/类型，理由写明选择，条子按最高分归一', () => {
  const sites = [
    site('a', 'yangshao', 'sanmenxia', 'kiln'),
    site('b', 'song', 'kaifeng', 'capital'),
    site('c', 'yangshao', 'luoyang', 'capital')
  ];
  const rows = interestRows(sites, { eras: ['yangshao'], types: [] }, 10);
  assert.deepEqual(rows.map((r) => r.id), ['a', 'c']);
  assert.ok(rows[0].reasons[0].includes('仰韶'));
  assert.equal(rows[0].bar, 100);   // 同分并列时都归一为满格
});

test('interestRows：负反馈排除整类后不再出现', () => {
  const sites = [site('a', 'yangshao'), site('b', 'longshan')];
  const rows = interestRows(sites, { eras: ['yangshao', 'longshan'], types: [] }, 10,
    { excludeIds: [], excludeEras: ['yangshao'], excludeTypes: [] });
  assert.deepEqual(rows.map((r) => r.id), ['b']);
});

test('零分候选不进结果；配额不足时按分数序放宽补足', () => {
  const src = site('s', 'zhou', 'luoyang', 'capital');
  const cands = [
    site('x', 'song', 'kaifeng', 'kiln'),     // 零分：与种子无任何共性
    site('a1', 'zhou', 'luoyang', 'burial'),
    site('a2', 'zhou', 'luoyang', 'burial'),
    site('a3', 'zhou', 'luoyang', 'burial'),
    site('b1', 'zhou', 'kaifeng', 'burial'),
    site('b2', 'zhou', 'kaifeng', 'burial'),
    site('b3', 'zhou', 'kaifeng', 'burial')
  ];
  const list = recommend(src, cands, [], [], 10);
  assert.ok(!list.some((r) => r.id === 'x'), '零分候选必须被过滤');

  // 城市各 3 条、配额 2：先各留 2 条，再按分数序放宽补足 6 条
  const picked = diversify(list, cands, 5, 2, 6);
  assert.equal(picked.length, 6);
  const luoyang = picked.filter((r) => r.id.startsWith('a')).length;
  const kaifeng = picked.filter((r) => r.id.startsWith('b')).length;
  assert.equal(luoyang, 3);
  assert.equal(kaifeng, 3);
});

test('浏览行为给同年代候选加权（F5 行为加权 ≤0.15）', () => {
  // 种子在洛阳周城；近期浏览大量宋代条目 → 宋代候选应获得行为加分
  const sites = [
    site('seed', 'zhou', 'luoyang'),
    site('song1', 'song', 'kaifeng'),
    site('song2', 'song', 'kaifeng'),
    site('song3', 'song', 'kaifeng'),
    site('song4', 'song', 'kaifeng')
  ];
  const visits = ['song1', 'song2', 'song3', 'song4'].map((id) => visit(`site:${id}`, 100));
  const rows = recoRowsFor(sites[0], sites, [], 4, visits);
  const top = rows[0];
  // 与种子仅同类型(0.3)，行为命中 3 个维度/条 → 上限 0.15
  assert.ok(top.reasons.some((r) => r.includes('近期行为加权')), '应出现行为加权重因');
  assert.ok(Number(top.score) > 0.3, `行为加权后应高于 0.3，实际 ${top.score}`);
});
