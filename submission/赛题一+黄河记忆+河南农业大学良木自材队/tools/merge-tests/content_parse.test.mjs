// tools/merge-tests/content_parse.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parseSiteJson, parseAll, filterSites, searchSites } from '../.tsbuild/service/content/ContentParse.ts';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');

const readSites = () => parseAll(
  readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8')));

test('rawfile 全部 42 条可解析且枚举合法（含周代/古代工程）', () => {
  const raws = readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8'));
  const sites = parseAll(raws);
  assert.equal(sites.length, 42);
  for (const s of sites) {
    assert.ok(s.id && s.name && s.relics.length >= 2);
    assert.ok(!('source' in s));
    // F3 诗词层：42 处遗址均须有至少 1 首公有领域名篇，且三要素齐全
    assert.ok(s.poems.length >= 1, `${s.id} 缺诗词`);
    for (const p of s.poems) {
      assert.ok(p.text.length > 0 && p.author.length > 0 && p.source.length > 0, `${s.id} 诗词字段不全`);
    }
  }
  // 六年代 × 四类型维度在语料中均有代表条目
  const eras = new Set(sites.map((s) => s.era));
  const types = new Set(sites.map((s) => s.siteType));
  for (const e of ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song']) assert.ok(eras.has(e), `缺年代 ${e}`);
  for (const t of ['capital', 'burial', 'kiln', 'ancient_arch']) assert.ok(types.has(t), `缺类型 ${t}`);
});

test('三维筛选：组内并集组间交集', () => {
  const sites = readSites();
  const r = filterSites(sites, ['yangshao', 'longshan'], [], ['luoyang', 'puyang']);
  assert.ok(r.length >= 1);
  assert.ok(r.every((s) => ['yangshao', 'longshan'].includes(s.era)
    && ['luoyang', 'puyang'].includes(s.city)));
});

test('关键词检索命中 name/summary/tags 且大小写不敏感', () => {
  const sites = readSites();
  const hit = searchSites(sites, sites[0].name.toUpperCase());
  assert.ok(hit.some((s) => s.id === sites[0].id));
});

// 深度层：events 由字符串升级为对象数组后，解析器须逐字段落位且不丢语义
test('深度 events：对象数组解析出六层字段', () => {
  const s = parseSiteJson(JSON.stringify({
    id: 'probe_site', name: '探针', city: 'kaifeng', era: 'song', site_type: 'capital',
    summary: 'x'.repeat(30), tags: ['a'],
    sections: {
      intro: 'i'.repeat(30), arch: 'a'.repeat(30), poems: [],
      events: [{
        year: '1049年', title: '州桥贯通', summary: 's'.repeat(50),
        background: 'bg', process: 'pp', impact: 'im',
        figures: ['赵佶', ''], furtherReading: 'fr'
      }],
      tourism: { overview: 'ov'.repeat(10), guide: { hours: 'h', tickets: 't', address: 'ad' }, itinerary: 'it' }
    },
    images: ['images/probe_site/a.webp', 'images/probe_site/b.webp'],
    relics: [{ id: 'r1', name: 'r', era: 'song', summary: 'y'.repeat(30), material: 'm', images: ['images/probe_site/a.webp'] },
             { id: 'r2', name: 'r2', era: 'song', summary: 'y'.repeat(30), material: 'm', images: ['images/probe_site/a.webp'] }]
  }));
  assert.equal(s.events.length, 1);
  const e = s.events[0];
  assert.equal(e.year, '1049年');
  assert.equal(e.title, '州桥贯通');
  assert.equal(e.background, 'bg');
  assert.equal(e.process, 'pp');
  assert.equal(e.impact, 'im');
  assert.equal(e.furtherReading, 'fr');
  // 空字符串人物应被过滤，避免渲染出无名标签
  assert.deepEqual(e.figures, ['赵佶']);
  assert.equal(s.tourism.guide.hours, 'h');
  assert.equal(s.tourism.guide.address, 'ad');
  assert.equal(s.tourism.itinerary, 'it');
});

// 向后兼容：未升级的旧语料仍须解析成功，events 退化为单条无标题摘要
test('旧格式 events/tourism 字符串仍可解析（向后兼容）', () => {
  const s = parseSiteJson(JSON.stringify({
    id: 'legacy_site', name: '旧站', city: 'luoyang', era: 'yangshao', site_type: 'kiln',
    summary: 'x'.repeat(30), tags: ['a'],
    sections: {
      intro: 'i'.repeat(30), arch: 'a'.repeat(30), poems: [],
      events: '1959年发现遗址，此为旧版单段文案。',
      tourism: '遗址旁建有博物馆，对公众开放。'
    },
    images: ['images/legacy_site/a.webp', 'images/legacy_site/b.webp'],
    relics: [{ id: 'r1', name: 'r', era: 'yangshao', summary: 'y'.repeat(30), material: 'm', images: ['images/legacy_site/a.webp'] },
             { id: 'r2', name: 'r2', era: 'yangshao', summary: 'y'.repeat(30), material: 'm', images: ['images/legacy_site/a.webp'] }]
  }));
  assert.equal(s.events.length, 1);
  assert.equal(s.events[0].summary, '1959年发现遗址，此为旧版单段文案。');
  assert.equal(s.events[0].year, '');
  assert.equal(s.tourism.overview, '遗址旁建有博物馆，对公众开放。');
  // 旧单段文案没有指引与行程，UI 须能据此隐藏对应区块
  assert.equal(s.tourism.guide.hours, '');
  assert.equal(s.tourism.itinerary, '');
});

// events 缺失深层字段时应留空串而非 undefined，避免 UI 渲染出 undefined
test('深度 events 缺深层字段时回落空串', () => {
  const s = parseSiteJson(JSON.stringify({
    id: 'thin_site', name: '薄站', city: 'puyang', era: 'zhou', site_type: 'burial',
    summary: 'x'.repeat(30), tags: ['a'],
    sections: {
      intro: 'i'.repeat(30), arch: 'a'.repeat(30), poems: [],
      events: [{ year: '1958年', title: '发现', summary: 's'.repeat(50) }],
      tourism: { overview: 'ov'.repeat(10) }
    },
    images: ['images/thin_site/a.webp', 'images/thin_site/b.webp'],
    relics: [{ id: 'r1', name: 'r', era: 'zhou', summary: 'y'.repeat(30), material: 'm', images: ['images/thin_site/a.webp'] },
             { id: 'r2', name: 'r2', era: 'zhou', summary: 'y'.repeat(30), material: 'm', images: ['images/thin_site/a.webp'] }]
  }));
  assert.equal(s.events[0].background, '');
  assert.equal(s.events[0].process, '');
  assert.equal(s.events[0].figures.length, 0);
  assert.equal(s.tourism.guide.tickets, '');
});
