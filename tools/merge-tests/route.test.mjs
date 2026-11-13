// tools/merge-tests/route.test.mjs —— P2-3：主题路线的解析、剪枝与完成度
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  parseRoutes, pruneRoutes, routeDoneCount, routePercent, nextStopId
} from '../.tsbuild/service/content/RouteParse.ts';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const RAW = join(ROOT, 'app/entry/src/main/resources/rawfile');

const doc = (routes) => JSON.stringify({ routes });

test('parseRoutes：缺 id / 无站的条目跳过；坏 JSON 返回空表', () => {
  const rs = parseRoutes(doc([
    { id: 'a', title: '甲', stops: [{ site: 'x', note: 'note-x' }] },
    { title: '没有 id', stops: [{ site: 'x' }] },
    { id: 'b', title: '乙', stops: [] },
    { id: 'c', title: '丙', stops: [{ site: 'y' }] }
  ]));
  assert.deepEqual(rs.map((r) => r.id), ['a', 'c']);
  assert.equal(rs[0].stops[0].note, 'note-x');
  assert.deepEqual(parseRoutes('{ oops'), []);
  assert.deepEqual(parseRoutes(''), []);
});

test('pruneRoutes：未知遗址与重复站被摘掉，摘完不足两站整条丢弃', () => {
  const rs = parseRoutes(doc([
    { id: 'a', title: '甲', stops: [{ site: 'x' }, { site: 'missing' }, { site: 'y' }, { site: 'x' }] },
    { id: 'b', title: '乙', stops: [{ site: 'x' }, { site: 'missing' }] }
  ]));
  const out = pruneRoutes(rs, ['x', 'y']);
  assert.equal(out.length, 1);
  assert.deepEqual(out[0].stops.map((s) => s.siteId), ['x', 'y']);
  // 原对象不被改写：剪枝返回副本，页面重复进入时不会越剪越少
  assert.equal(rs[0].stops.length, 4);
});

test('完成度按「读完的站」计数，下一站取第一个未读，全读完返回空串', () => {
  const r = parseRoutes(doc([
    { id: 'a', title: '甲', stops: [{ site: 'x' }, { site: 'y' }, { site: 'z' }] }
  ]))[0];
  assert.equal(routeDoneCount(r, ['x']), 1);
  assert.equal(routePercent(r, ['x']), 33);
  assert.equal(routePercent(r, []), 0);
  assert.equal(nextStopId(r, ['x']), 'y');
  assert.equal(nextStopId(r, ['x', 'z']), 'y');
  assert.equal(nextStopId(r, ['x', 'y', 'z']), '');
});

test('rawfile/routes.json：6–8 条线，每条 4–8 站，站点 id 全部存在于语料', () => {
  const parsed = parseRoutes(readFileSync(join(RAW, 'routes.json'), 'utf8'));
  assert.ok(parsed.length >= 6 && parsed.length <= 8, `路线条数 ${parsed.length}`);

  const siteDir = join(RAW, 'sites');
  const ids = readdirSync(siteDir)
    .filter((n) => n.endsWith('.json'))
    .map((n) => JSON.parse(readFileSync(join(siteDir, n), 'utf8')).id);

  for (const r of parsed) {
    assert.ok(r.title !== '' && r.subtitle !== '' && r.era !== '' && r.duration !== '',
      `${r.id}: 标题/副题/年代/时长不得为空`);
    assert.ok(r.stops.length >= 4 && r.stops.length <= 8, `${r.id}: 站数 ${r.stops.length}`);
    for (const st of r.stops) {
      assert.ok(ids.includes(st.siteId), `${r.id}: 引用了不存在的遗址 ${st.siteId}`);
      assert.ok(st.note !== '', `${r.id}/${st.siteId}: 缺「为什么排在这里」的说明`);
    }
  }
  // 一条都不该被剪掉——被剪说明 id 写错或重复
  assert.equal(pruneRoutes(parsed, ids).length, parsed.length);
});
