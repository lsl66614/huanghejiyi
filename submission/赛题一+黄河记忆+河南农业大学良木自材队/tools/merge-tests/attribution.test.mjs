// tools/merge-tests/attribution.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import {
  parseAttribution, requiresCredit, creditLine, findByPath,
  groupByLicence, changeStatement, aiStatement, licenceUrl
} from '../.tsbuild/service/content/Attribution.ts';

const RES = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile');
const attr = () => parseAttribution(readFileSync(join(RES, 'attribution.json'), 'utf8'));

test('requiresCredit：BY 系列判真，CC0 与公有 domain 判假', () => {
  assert.equal(requiresCredit('CC BY-SA 4.0'), true);
  assert.equal(requiresCredit('CC BY-SA 3.0'), true);
  assert.equal(requiresCredit('CC BY 4.0'), true);
  assert.equal(requiresCredit('CC0'), false);
  assert.equal(requiresCredit('Public domain'), false);
  assert.equal(requiresCredit(''), false);
});

test('licenceUrl：BY-SA 4.0 第 3.a 条要求的许可链接，在包出现的许可全部给得出', () => {
  assert.equal(licenceUrl('CC BY-SA 4.0'), 'https://creativecommons.org/licenses/by-sa/4.0/');
  assert.equal(licenceUrl('CC BY-SA 3.0'), 'https://creativecommons.org/licenses/by-sa/3.0/');
  assert.equal(licenceUrl('CC BY 4.0'), 'https://creativecommons.org/licenses/by/4.0/');
  assert.equal(licenceUrl('CC0'), 'https://creativecommons.org/publicdomain/zero/1.0/');
  assert.equal(licenceUrl('Public domain'), '');   // 认不出来就留空，不猜 URL
  for (const lic of new Set(attr().images.map((r) => r.licence))) {
    assert.ok(licenceUrl(lic).startsWith('https://creativecommons.org/'), `许可 ${lic} 无链接`);
  }
});

test('attribution.json 可解析且字段齐全', () => {
  const d = attr();
  assert.ok(d.policy.length > 0);
  assert.ok(d.images.length >= 70, `实拍署名记录过少：${d.images.length}`);
  for (const r of d.images) {
    assert.match(r.path, /^images\/[a-z0-9_]+\/real_[a-z0-9_]+\.webp$/, r.path);
    assert.ok(r.file && r.author && r.licence && r.source && r.adapted, `字段不全: ${r.path}`);
    assert.ok(r.source.startsWith('https://commons.wikimedia.org/wiki/File:'), r.source);
  }
  assert.equal(new Set(d.images.map((r) => r.path)).size, d.images.length, 'path 重复');
});

test('按许可分组：需署名排前、组内按文件名稳定排序', () => {
  const d = attr();
  const gs = groupByLicence(d.images);
  const flags = gs.map((g) => (g.requiresCredit ? 0 : 1));
  assert.deepEqual(flags, [...flags].sort((a, b) => a - b), '需署名组没排在前面');
  for (const g of gs) {
    const files = g.records.map((r) => r.file);
    assert.deepEqual(files, [...files].sort(), `组 ${g.licence} 内未按文件名排序`);
    assert.ok(g.records.every((r) => r.licence === g.licence));
  }
  // 稳定性：同一份数据两次分组顺序一致（版权页不做随机排布）
  assert.deepEqual(groupByLicence(d.images).map((g) => `${g.licence}:${g.records.length}`),
    gs.map((g) => `${g.licence}:${g.records.length}`));
  assert.equal(gs.reduce((n, g) => n + g.records.length, 0), d.images.length, '分组丢图');
});

test('findByPath / creditLine / changeStatement / aiStatement', () => {
  const d = attr();
  const first = d.images[0];
  assert.equal(findByPath(d.images, first.path), first);
  assert.equal(findByPath(d.images, 'images/none/real_none.webp'), null);
  assert.equal(creditLine(first), `${first.author} · ${first.licence}`);
  assert.equal(creditLine({ author: 'A', licence: '', path: '', file: '', source: '', adapted: '' }), 'A');
  assert.equal(creditLine({ author: '', licence: 'CC0', path: '', file: '', source: '', adapted: '' }), 'CC0');
  const stmt = changeStatement(d.images);
  assert.ok(stmt.includes('WebP'), stmt);
  assert.equal(d.aiIllustrations.length, 6, '首页示意图声明张数应为 6（与 EraTheme 硬编码同步）');
  assert.ok(aiStatement(d.aiIllustrations).includes('6 张'));
  assert.equal(aiStatement([]), '');
});

test('每张 AI 示意图都仍在包里且被 EraTheme 引用', () => {
  const d = attr();
  const ets = readFileSync(
    join(import.meta.dirname, '../../app/entry/src/main/ets/common/EraTheme.ets'), 'utf8');
  for (const a of d.aiIllustrations) {
    assert.ok(existsSync(join(RES, a.path)), `声明的示意图不在包: ${a.path}`);
    assert.ok(ets.includes(a.path), `EraTheme 未引用该示意图: ${a.path}`);
  }
});

test('字体记录：OFL 1.1，许可原文确在包里，且覆盖 rawfile/font 全部字面', () => {
  const d = attr();
  const fontDir = join(RES, 'font');
  const onDisk = readdirSync(fontDir).filter((f) => /\.(ttf|otf|woff2?)$/i.test(f));
  assert.equal(d.fonts.length, onDisk.length, `字体记录 ${d.fonts.length} ≠ 在包字体 ${onDisk.length}`);
  const named = new Set(d.fonts.map((f) => f.file));
  for (const f of onDisk) assert.ok(named.has(f), `字体 ${f} 无许可记录`);
  for (const f of d.fonts) {
    assert.match(f.licence, /Open Font License/);
    assert.match(f.copyright, /^Copyright /);
    assert.ok(existsSync(join(RES, f.licenceFile)), `许可原文不在包: ${f.licenceFile}`);
    assert.ok(f.source.startsWith('https://'), f.source);
    assert.ok(f.family && f.licenceUrl, `${f.file} 缺 family/licenceUrl`);
  }
});

test('逐张实拍文件在盘上且被内容引用', () => {
  const d = attr();
  const sitesDir = join(RES, 'sites');
  const refs = new Set();
  for (const f of readdirSync(sitesDir).filter((x) => x.endsWith('.json'))) {
    const raw = readFileSync(join(sitesDir, f), 'utf8');
    for (const m of raw.matchAll(/images\/[A-Za-z0-9_]+\/(real_[A-Za-z0-9_]+\.webp)/g)) {
      refs.add(m[0]);
    }
  }
  for (const r of d.images) {
    assert.ok(existsSync(join(RES, r.path)), `署名记录指向的文件不在包: ${r.path}`);
    assert.ok(refs.has(r.path), `署名记录对应的图未被任何遗址引用: ${r.path}`);
  }
});
