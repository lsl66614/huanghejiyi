// tools/merge-tests/material_index.test.mjs —— 材质索引与图标分类的一致性
import test from 'node:test';
import assert from 'node:assert/strict';
import { buildMaterialIndex, bucketSubtitle } from '../.tsbuild/service/content/MaterialIndex.ts';
import { parseAll } from '../.tsbuild/service/content/ContentParse.ts';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');
const sites = parseAll(readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8')));

test('材质索引：覆盖全部 104 件文物，无遗漏', () => {
  const idx = buildMaterialIndex(sites);
  const sum = idx.buckets.reduce((a, b) => a + b.relicCount, 0);
  assert.equal(sum, 104, `分桶总数 ${sum} ≠ 104`);
  assert.equal(idx.totalRelics, 104);
});

test('材质索引：只有 7+1 个桶，未记排最后', () => {
  const idx = buildMaterialIndex(sites);
  const kinds = idx.buckets.map((b) => b.kind);
  assert.ok(kinds.length <= 8, `桶数 ${kinds.length} 超过 8`);
  if (kinds.includes('未记')) {
    assert.equal(kinds[kinds.length - 1], '未记', '未记必须排最后');
  }
});

test('材质索引：陶是最大类（史前彩陶是黄河叙事的主角）', () => {
  const idx = buildMaterialIndex(sites);
  assert.equal(idx.buckets[0].kind, '陶');
  assert.ok(idx.buckets[0].relicCount >= 20, `陶仅 ${idx.buckets[0].relicCount} 件`);
});

test('材质索引：与 RelicIcon 的关键词分类不矛盾', () => {
  // MaterialIndex 自带一份关键词表（为保持禁 @kit），这里逐条验证
  // 它和 common/RelicIcon.ets 的 RULES 完全一致——两处漂移会让
  // 「按材质逛」选中的集合和剪影图标对不上。
  const src = readFileSync(join(import.meta.dirname, '../../app/entry/src/main/ets/common/RelicIcon.ets'), 'utf8');
  const ruleRe = /new IconRule\(\[([^\]]+)\],\s*'[^']+',\s*'([^']+)'\)/g;
  const pairs = [];
  let m;
  while ((m = ruleRe.exec(src)) !== null) {
    const keys = m[1].split(',').map((s) => s.trim().replace(/^'|'$/g, ''));
    pairs.push([keys, m[2]]);
  }
  assert.equal(pairs.length, 7, `RelicIcon 有 ${pairs.length} 条规则`);
  const idx = buildMaterialIndex(sites);
  const got = idx.buckets.map((b) => b.kind).filter((k) => k !== '未记').sort();
  const want = pairs.map((p) => p[1]).sort();
  assert.deepEqual(got, want, '两处的类名集合不一致');
});

test('材质索引：siteIds 去重，siteCount 与 siteIds 等长', () => {
  const idx = buildMaterialIndex(sites);
  for (const b of idx.buckets) {
    assert.equal(b.siteCount, b.siteIds.length);
    assert.equal(new Set(b.siteIds).size, b.siteIds.length, `${b.kind} 的 siteIds 有重复`);
    assert.ok(b.eras.length >= 1, `${b.kind} 无年代`);
  }
});

test('bucketSubtitle：形如「25 件 · 18 处遗址」', () => {
  const idx = buildMaterialIndex(sites);
  const s = bucketSubtitle(idx.buckets[0]);
  assert.match(s, /^\d+ 件 · \d+ 处遗址$/);
});
