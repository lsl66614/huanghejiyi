// tools/merge-tests/importplan.test.mjs —— 档案导回：解析、判重与 LWW 对齐
//
// fixture 走「导出 → 导回」往返：用 ExportFormat.buildArchive + exportJson
// 生成档案 JSON，再交给 parseArchive 解析。单侧造数据容易和导出格式漂移，
// 往返测试保证两个方向永远对得上。
import test from 'node:test';
import assert from 'node:assert/strict';
import { TargetLabels } from '../.tsbuild/service/content/TargetLabel.ts';
import { buildArchive, exportJson } from '../.tsbuild/service/export/ExportFormat.ts';
import {
  IMPORT_SCHEMA, maxImportedTime, parseArchive,
  planFavoriteImports, planNoteImports, planProgressImports
} from '../.tsbuild/service/import/ImportPlan.ts';

const DAY = 86400000;
const NOW = new Date(2026, 9, 28, 15, 30, 0).getTime();

const LABELS = (() => {
  const l = new TargetLabels();
  l.build([
    { id: 'a', name: '小浪底遗址', relics: [{ id: 'r1', name: '彩陶罐' }] },
    { id: 'b', name: '大河村遗址', relics: [] }
  ]);
  return l;
})();

const NOTES = [
  { noteId: 'n1', targetKey: 'site:a:arch', text: '考古笔记', createTime: NOW - 10 * DAY, updateTime: NOW - 3 * DAY, tagIds: ['待实地探访'] },
  { noteId: 'n2', targetKey: 'site:a', text: '整条笔记', createTime: NOW - 9 * DAY, updateTime: NOW - DAY, tagIds: [] },
  { noteId: 'n3', targetKey: 'notebook:inbox', text: '   ', createTime: NOW, updateTime: NOW, tagIds: [] },
  { noteId: 'n4', targetKey: 'relic:r1', text: '器物笔记', createTime: NOW - 8 * DAY, updateTime: NOW - 5 * DAY, tagIds: ['研究资料'] }
];

const FAVS = [
  { targetKey: 'site:a', createTime: NOW - 2 * DAY, updateTime: NOW - 2 * DAY, deviceId: 'deviceA', isDeleted: false },
  { targetKey: 'relic:r1', createTime: NOW - 4 * DAY, updateTime: NOW - 4 * DAY, deviceId: 'deviceA', isDeleted: false }
];

const FAV_TAGS = [
  { targetKey: 'site:a', tagId: '待实地探访', updateTime: NOW },
  { targetKey: 'site:a', tagId: '研究资料', updateTime: NOW }
];

const PROGRESS = [
  { targetKey: 'site:a', section: 'arch', done: true, updateTime: NOW - 2 * DAY, deviceId: 'deviceA' },
  { targetKey: 'site:a', section: 'poems', done: false, updateTime: NOW - DAY, deviceId: 'deviceA' }
];

const archiveJson = () => exportJson(buildArchive(NOTES, FAVS, FAV_TAGS, PROGRESS, LABELS, 'deviceA', NOW));

test('parseArchive：导出 → 导回往返，计数与字段逐一对得上', () => {
  const raw = archiveJson();
  const r = parseArchive(raw);
  assert.equal(r.ok, true, r.error);
  assert.equal(r.deviceId, 'deviceA');
  // 导出丢过空正文（n3），解析侧同样口径：剩下的三条都在
  assert.equal(r.notes.length, 3);
  assert.equal(r.favorites.length, 2);
  assert.equal(r.progress.length, 1);
  const arch = r.notes.find((n) => n.targetKey === 'site:a:arch');
  assert.equal(arch.text, '考古笔记');
  assert.deepEqual(arch.tags, ['待实地探访']);
  assert.equal(arch.createTime, NOW - 10 * DAY);
  assert.equal(arch.updateTime, NOW - 3 * DAY);
  const fav = r.favorites.find((f) => f.targetKey === 'site:a');
  assert.deepEqual(fav.tags, ['待实地探访', '研究资料']);
  assert.equal(r.progress[0].targetKey, 'site:a');
  assert.equal(r.progress[0].section, 'arch');
  assert.equal(r.progress[0].updateTime, NOW - 2 * DAY);
});

test('parseArchive：不是本应用的文件要给出人话报错', () => {
  const bad = parseArchive('{"app": "别的应用"}');
  assert.equal(bad.ok, false);
  assert.ok(bad.error.includes('黄河记忆'));
  const broken = parseArchive('{not json');
  assert.equal(broken.ok, false);
  assert.ok(broken.error.includes('JSON'));
  // 字段缺列：报错指名道姓，不抛原始异常
  const missing = parseArchive(`{"schema": "${IMPORT_SCHEMA}", "notes": [{"targetKey": "site:a"}]}`);
  assert.equal(missing.ok, false);
  assert.ok(missing.error.includes('text'));
});

test('parseArchive：重复收藏/进度只取一份，认不出的 section 跳过', () => {
  const raw = JSON.stringify({
    schema: IMPORT_SCHEMA, deviceId: 'deviceX', exportedAt: NOW,
    notes: [],
    favorites: [
      { targetKey: 'site:b', tags: [], createTime: NOW - DAY },
      { targetKey: 'site:b', tags: [], createTime: NOW - 2 * DAY } // 旧的一行不要
    ],
    progress: [
      { targetKey: 'site:b', section: 'arch', done: true, updateTime: NOW - DAY },
      { targetKey: 'site:b', section: 'arch', done: true, updateTime: NOW - 2 * DAY },
      { targetKey: 'site:b', section: 'nope', done: true, updateTime: NOW } // 坏键拖不垮整次导入
    ]
  });
  const r = parseArchive(raw);
  assert.equal(r.ok, true, r.error);
  assert.equal(r.deviceId, 'deviceX');
  assert.equal(r.favorites.length, 1);
  assert.equal(r.favorites[0].createTime, NOW - DAY);
  assert.equal(r.progress.length, 1);
});

test('planNoteImports：正文判重——批量内与本机现存都算重复', () => {
  const incoming = [
    { targetKey: 'site:a', text: '新笔记', tags: [], createTime: NOW, updateTime: NOW },
    { targetKey: 'site:a', text: '新笔记', tags: [], createTime: NOW, updateTime: NOW }, // 批量内重复
    { targetKey: 'site:a', text: '考古笔记', tags: [], createTime: NOW, updateTime: NOW } // 本机已有
  ];
  const existing = [
    { noteId: 'n1', targetKey: 'site:a', text: '考古笔记', createTime: 1, updateTime: 2, tagIds: [] }
  ];
  const r = planNoteImports(incoming, existing, 'deviceX');
  assert.equal(r.planned.length, 1);
  assert.equal(r.skipped, 2);
  assert.equal(r.planned[0].text, '新笔记');
  // 版本号保留导出值：同步版本不因导入重新盖章
  assert.equal(r.planned[0].updateTime, NOW);
  assert.equal(r.planned[0].deviceId, 'deviceX');
});

test('planFavoriteImports：存活行与墓碑行都跳过，防复活防覆盖', () => {
  const incoming = [
    { targetKey: 'site:a', tags: [], createTime: NOW },        // 本机存活
    { targetKey: 'relic:r1', tags: [], createTime: NOW },      // 本机已删（墓碑）
    { targetKey: 'site:b', tags: ['新标签'], createTime: NOW - DAY } // 全新
  ];
  const live = [
    { targetKey: 'site:a', createTime: NOW - 9 * DAY, updateTime: NOW - 9 * DAY, deviceId: 'deviceA', isDeleted: false }
  ];
  const tombs = [
    { targetKey: 'relic:r1', createTime: NOW - 4 * DAY, updateTime: NOW - 3 * DAY, deviceId: 'deviceA', isDeleted: true }
  ];
  const r = planFavoriteImports(incoming, live, tombs, 'deviceX');
  assert.equal(r.planned.length, 1);
  assert.equal(r.skipped, 2);
  assert.equal(r.planned[0].targetKey, 'site:b');
  assert.equal(r.planned[0].deviceId, 'deviceX');
});

test('planProgressImports：已读不重写；未读本机行更新才导入；平局保本机', () => {
  const incoming = [
    { targetKey: 'site:a', section: 'arch', updateTime: NOW - DAY },      // 本机已读
    { targetKey: 'site:b', section: 'arch', updateTime: NOW - 3 * DAY },  // 本机未读但行更新（导出后本机动过）
    { targetKey: 'site:b', section: 'poems', updateTime: NOW - 5 * DAY }, // 本机未读且导出更新 → 导入
    { targetKey: 'site:c', section: 'intro', updateTime: NOW - DAY },     // 本机没有 → 导入
    { targetKey: 'site:c', section: 'arch', updateTime: NOW - 5 * DAY }   // 平局 → 保本机
  ];
  const local = [
    { targetKey: 'site:a', section: 'arch', done: true, updateTime: NOW - DAY, deviceId: 'A' },
    { targetKey: 'site:b', section: 'arch', done: false, updateTime: NOW - 2 * DAY, deviceId: 'A' },
    { targetKey: 'site:b', section: 'poems', done: false, updateTime: NOW - 6 * DAY, deviceId: 'A' },
    { targetKey: 'site:c', section: 'arch', done: false, updateTime: NOW - 5 * DAY, deviceId: 'A' }
  ];
  const r = planProgressImports(incoming, local, 'deviceX');
  assert.deepEqual(r.planned.map((p) => `${p.targetKey}|${p.section}`), ['site:b|poems', 'site:c|intro']);
  assert.equal(r.planned[0].updateTime, NOW - 5 * DAY);
  assert.equal(r.skipped, 3);
});

test('maxImportedTime：取全部时间字段的最大值，供高水位吸收', () => {
  const r = parseArchive(archiveJson());
  assert.equal(r.ok, true, r.error);
  assert.equal(maxImportedTime(r, NOW), NOW); // exportedAt 本身就是最大
  // 空档案且无 exportedAt：高水位 0，页面侧据此跳过吸收
  const empty = parseArchive(`{"schema": "${IMPORT_SCHEMA}"}`);
  assert.equal(empty.ok, true, empty.error);
  assert.equal(maxImportedTime(empty, 0), 0);
});
