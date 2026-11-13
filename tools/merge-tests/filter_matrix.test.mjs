// tools/merge-tests/filter_matrix.test.mjs
// T1:三维筛选矩阵全量遍历 —— 6 年代 × 4 类型 × 5 城市 = 120 组合逐一验证
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { ERAS, CITIES, SITE_TYPES } from '../.tsbuild/model/ContentModels.ts';
import { parseAll, filterSites, searchSites } from '../.tsbuild/service/content/ContentParse.ts';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');

function loadSites() {
  return parseAll(readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8')));
}

// 独立于 filterSites 的朴素实现，作为完备性参照
function naive(sites, eras, types, cities) {
  return sites.filter((s) =>
    (eras.length === 0 || eras.includes(s.era)) &&
    (types.length === 0 || types.includes(s.siteType)) &&
    (cities.length === 0 || cities.includes(s.city)));
}

const sites = loadSites();

test('T1 全矩阵 120 组合：结果既不漏报也不误报，空组合与语料实际分布一致', () => {
  let nonEmpty = 0;
  const emptyCombos = [];
  for (const era of ERAS) {
    for (const type of SITE_TYPES) {
      for (const city of CITIES) {
        const got = filterSites(sites, [era], [type], [city]);
        const expect = naive(sites, [era], [type], [city]);
        // 健全性：返回的每一条都必须同时满足三个维度
        for (const s of got) {
          assert.equal(s.era, era, `${era}/${type}/${city} 混入年代 ${s.era}`);
          assert.equal(s.siteType, type, `${era}/${type}/${city} 混入类型 ${s.siteType}`);
          assert.equal(s.city, city, `${era}/${type}/${city} 混入城市 ${s.city}`);
        }
        // 完备性：与独立朴素实现逐条对齐（id 集合相等）
        assert.deepEqual(got.map((s) => s.id).sort(), expect.map((s) => s.id).sort(),
          `${era}/${type}/${city} 与朴素过滤结果不一致`);
        if (got.length === 0) emptyCombos.push(`${era}/${type}/${city}`);
        else nonEmpty += 1;
      }
    }
  }
  // 当前 42 条语料：非空组合不少于 30（防止数据回填后矩阵再次塌缩无人察觉）
  assert.ok(nonEmpty >= 30, `非空组合仅 ${nonEmpty}`);
  assert.equal(nonEmpty + emptyCombos.length, ERAS.length * SITE_TYPES.length * CITIES.length);
  console.log(`矩阵遍历:${nonEmpty} 个非空组合,${emptyCombos.length} 个语料空缺组合(UI 走空态)`);
});

test('T1 每个单维枚举值单独使用时都有结果（一级筛选不进死路）', () => {
  for (const era of ERAS) {
    assert.ok(filterSites(sites, [era], [], []).length >= 1, `年代 ${era} 无条目`);
  }
  for (const type of SITE_TYPES) {
    assert.ok(filterSites(sites, [], [type], []).length >= 1, `类型 ${type} 无条目`);
  }
  for (const city of CITIES) {
    assert.ok(filterSites(sites, [], [], [city]).length >= 1, `城市 ${city} 无条目`);
  }
});

test('T1 空维度不过滤；组内并集、组间交集', () => {
  assert.equal(filterSites(sites, [], [], []).length, sites.length);
  const union = filterSites(sites, ['yangshao', 'zhou'], [], []);
  assert.ok(union.every((s) => s.era === 'yangshao' || s.era === 'zhou'));
  assert.equal(union.length,
    filterSites(sites, ['yangshao'], [], []).length + filterSites(sites, ['zhou'], [], []).length);
  const cross = filterSites(sites, ['hantang'], ['kiln'], []);
  for (const s of cross) {
    assert.equal(s.era, 'hantang');
    assert.equal(s.siteType, 'kiln');
  }
});

test('T1 关键词在三维过滤后的集合内检索：每条遗址可被自身名称/首标签找回', () => {
  for (const era of ERAS) {
    const scoped = filterSites(sites, [era], [], []);
    for (const s of scoped) {
      const byName = searchSites(scoped, s.name);
      assert.ok(byName.some((x) => x.id === s.id), `${s.id} 名称检索丢失`);
      if (s.tags.length > 0) {
        const byTag = searchSites(scoped, s.tags[0]);
        assert.ok(byTag.some((x) => x.id === s.id), `${s.id} 标签 ${s.tags[0]} 检索丢失`);
      }
    }
  }
});
