// tools/merge-tests/relic_reco.test.mjs —— 文物级推荐（基于行为的相似文物）
//
// 赛题一主要功能第 5 条写的是"推荐用户可能感兴趣的遗址**或文物**"。
// 文物页原有三组相关文物（同遗址/同年代/同材质）是**静态关联**，与用户行为无关；
// 这里补的是"基于收藏与浏览行为"的那一路，所以判据必须能区分两者。
//
// 三条最容易写错的口径，每条都有用例钉住：
//   1. 文物的年代取**器物自己**的（语料 12 件跨代，如宋代巩义窑址出汉唐三彩）；
//   2. 材质「未记」不是一类，不能把缺材质字段的器物聚成"同材质"；
//   3. 候选必须排除自身与已收藏的文物。
import test from 'node:test';
import assert from 'node:assert/strict';
import { relicInputs, relicHistory, relicRecoFor } from '../.tsbuild/service/recommend/RecoSource.ts';

const site = (id, city, era, relics) => ({
  id, name: id, city, era, siteType: 'capital', tags: [], summary: '',
  sections: {}, images: [], relics
});
const relic = (id, siteId, era, material, name) => ({
  id, siteId, name: name ?? id, era, summary: '', material, images: []
});

const SITES = [
  site('s1', 'zhengzhou', 'yangshao', [
    relic('r1', 's1', 'yangshao', '陶'),
    relic('r2', 's1', 'hantang', '三彩'),      // 跨代：出土地是仰韶，器物属汉唐
    relic('r3', 's1', '', '')                   // 材质未记、年代未记
  ]),
  site('s2', 'luoyang', 'longshan', [
    relic('r4', 's2', 'yangshao', '陶'),
    relic('r5', 's2', 'longshan', '玉'),
  ]),
  site('s3', 'kaifeng', 'song', [
    relic('r6', 's3', 'hantang', '三彩')
  ])
];

const fav = (key, t) => ({ targetKey: key, createTime: t, updateTime: t, deviceId: 'deviceA', isDeleted: false });
const visit = (key) => ({ targetKey: key, createTime: 1 });

test('relicInputs：id 带 relic: 前缀，era 取器物自身而非遗址年代', () => {
  const inputs = relicInputs(SITES);
  assert.equal(inputs.length, 6);
  const r2 = inputs.find((i) => i.id === 'relic:r2');
  assert.equal(r2.era, 'hantang', 'r2 出土地是仰韶，但器物属汉唐——取器物自身');
  const r1 = inputs.find((i) => i.id === 'relic:r1');
  assert.equal(r1.era, 'yangshao');
});

test('relicInputs：city 取自所属遗址，siteType 位放材质', () => {
  const inputs = relicInputs(SITES);
  const r1 = inputs.find((i) => i.id === 'relic:r1');
  assert.equal(r1.city, 'zhengzhou', '所属遗址 s1 在郑州');
  assert.equal(r1.siteType, '陶');
});

test('relicRecoFor：以一件仰韶陶器为种子，同年代同材质的 r4 排在前面', () => {
  const seed = SITES[0].relics[0];               // r1 仰韶·陶·郑州
  const rows = relicRecoFor(seed, SITES, [], 6);
  const ids = rows.map((r) => r.id);
  assert.ok(ids.includes('relic:r4'), 'r4 同为仰韶陶器，必须在候选里');
  const r4 = rows.find((r) => r.id === 'relic:r4');
  assert.ok(r4.reasons.includes('同年代'), 'r4 应带「同年代」理由');
  assert.ok(r4.reasons.includes('同材质'), 'r4 应带「同材质」理由');
  assert.equal(r4.name, 'r4', '行上要能直接显示器物名');
  assert.ok(r4.meta.includes('陶'), 'meta 应含材质');
  assert.ok(r4.meta.includes('s2'), 'meta 应含所属遗址');
  assert.ok(r4.rank === '01' || r4.rank === '02' || r4.rank === '03', '行号已生成');
});

test('relicRecoFor：排除自身', () => {
  const seed = SITES[0].relics[0];
  const rows = relicRecoFor(seed, SITES, [], 6);
  assert.ok(!rows.some((r) => r.id === 'relic:r1'), '不能推荐自己');
});

test('relicRecoFor：排除已收藏的文物', () => {
  const seed = SITES[0].relics[0];
  const rows = relicRecoFor(seed, SITES, [fav('relic:r4', 10)], 6);
  assert.ok(!rows.some((r) => r.id === 'relic:r4'), 'r4 已收藏，不应再推');
});

test('材质「未记」不聚成一类：r3 不会因为都缺材质而被当成同材质推荐', () => {
  const seed = SITES[0].relics[2];               // r3 材质空、年代空
  const rows = relicRecoFor(seed, SITES, [], 6);
  for (const r of rows) {
    assert.ok(!r.reasons.includes('同材质') || r.id !== 'relic:r3');
  }
  // 更直接的判据：r3 自身没有材质，任何"同材质"理由都不该出现在结果里
  assert.ok(!rows.some((r) => r.reasons.includes('同材质')),
    '种子材质为空时不该给出「同材质」理由');
});

test('relicHistory：收藏与浏览里的文物键能转成行为序列', () => {
  const h = relicHistory([fav('relic:r1', 5)], [visit('relic:r6')], SITES);
  const ids = h.map((i) => i.id);
  assert.ok(ids.includes('relic:r1'), '收藏里的文物应进行为史');
  assert.ok(ids.includes('relic:r6'), '浏览过的文物应进行为史');
  assert.ok(!ids.includes('site:s1'), '遗址键不该混进文物行为史');
});

test('行为为空时退化为静态相似，不报错', () => {
  const seed = SITES[0].relics[0];
  const rows = relicRecoFor(seed, SITES, [], 6, []);
  assert.ok(Array.isArray(rows));
  assert.ok(rows.length > 0, '没有行为也要能给出静态相似');
});
