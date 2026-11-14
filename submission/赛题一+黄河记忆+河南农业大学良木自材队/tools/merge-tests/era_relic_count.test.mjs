// tools/merge-tests/era_relic_count.test.mjs —— 年代 × 文物双轴计数（A 方案）
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildEraRelicStats, relicsOfEra } from '../.tsbuild/service/content/EraRelicCount.ts';
import { parseAll } from '../.tsbuild/service/content/ContentParse.ts';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');
const sites = parseAll(readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8')));

// ERAS 顺序与 model/ContentModels 一致：仰韶 龙山 夏商 周 汉唐 宋
const ERAS = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];

test('年代双轴：六层都在，层数与年代数一致', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  assert.equal(stats.length, 6);
  assert.deepEqual(stats.map((s) => s.era), ERAS);
});

test('年代双轴：六层遗址数之和 = 42（每处遗址只计一次）', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  const sum = stats.reduce((a, b) => a + b.siteCount, 0);
  assert.equal(sum, 42, `遗址总数 ${sum} ≠ 42`);
});

test('年代双轴：六层文物数之和 = 104（按器物年代，一件只落一层）', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  const sum = stats.reduce((a, b) => a + b.relicCount, 0);
  assert.equal(sum, 104, `文物总数 ${sum} ≠ 104`);
});

test('年代双轴：按器物年代计，跨代文物不被算进遗址所在层', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  // 巩义窑址（site era = song）出土唐三彩（relic era = hantang）：
  // 宋层不得因此多出唐三彩。
  const song = stats.find((s) => s.era === 'song');
  const hantang = stats.find((s) => s.era === 'hantang');
  // 语料实测：site=song/relic=hantang 有 2 件（唐三彩马俑、釉陶残片等）
  const crossCount = sites
    .filter((s) => s.era === 'song')
    .flatMap((s) => s.relics)
    .filter((r) => r.era === 'hantang').length;
  assert.equal(crossCount, 2, '语料里 song→hantang 的跨代件数应�� 2');
  assert.ok(hantang.relicCount >= 2, '汉唐层必须含这 2 件跨代文物');
  // 宋层的文物数应等于"宋层遗址里年代也为宋的文物"总数（不含跨代件）
  const songOwn = sites
    .filter((s) => s.era === 'song')
    .flatMap((s) => s.relics)
    .filter((r) => r.era === 'song').length;
  assert.equal(song.relicCount, songOwn, `宋层文物数 ${song.relicCount} ≠ ${songOwn}`);
});

test('年代双轴：遗址数按 site.era 归层，与语料直算一致', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  for (const e of ERAS) {
    const expect = sites.filter((s) => s.era === e).length;
    const got = stats.find((s) => s.era === e).siteCount;
    assert.equal(got, expect, `${e} 层遗址数 ${got} ≠ ${expect}`);
  }
});

test('年代双轴：各层文物数与语料直算一致', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  for (const e of ERAS) {
    const expect = sites.flatMap((s) => s.relics).filter((r) => r.era === e).length;
    const got = stats.find((s) => s.era === e).relicCount;
    assert.equal(got, expect, `${e} 层文物数 ${got} ≠ ${expect}`);
  }
});

test('年代双轴：没有任何一层是 0 文物（避免空层卡读作坏掉）', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  for (const s of stats) {
    assert.ok(s.siteCount > 0, `${s.era} 层没有遗址`);
    assert.ok(s.relicCount > 0, `${s.era} 层没有文物`);
  }
});

test('年代双轴：取某年代的文物，件数与该层计数一致（上限内）', () => {
  const stats = buildEraRelicStats(sites, ERAS);
  for (const e of ERAS) {
    const total = stats.find((s) => s.era === e).relicCount;
    const chips = relicsOfEra(sites, e, 999);
    assert.equal(chips.length, total, `${e} 层取出的文物数与计数不符`);
    // 每件的年代必须都是本层
    for (const c of chips) {
      assert.equal(c.era, e);
      assert.ok(c.siteName.length > 0, '文物必须带遗址名');
    }
  }
});

test('年代双轴：limit 生效且是前缀截断', () => {
  const all = relicsOfEra(sites, 'yangshao', 999);
  assert.ok(all.length > 3, '仰韶层应有多于 3 件文物');
  const few = relicsOfEra(sites, 'yangshao', 3);
  assert.equal(few.length, 3);
  assert.deepEqual(few.map((c) => c.id), all.slice(0, 3).map((c) => c.id));
});
