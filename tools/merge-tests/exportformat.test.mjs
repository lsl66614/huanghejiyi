// tools/merge-tests/exportformat.test.mjs —— P3-1：导出内容的口径与排版
import test from 'node:test';
import assert from 'node:assert/strict';
import { TargetLabels } from '../.tsbuild/service/content/TargetLabel.ts';
import {
  EXPORT_SCHEMA, buildArchive, exportFileName, exportJson, exportMarkdown
} from '../.tsbuild/service/export/ExportFormat.ts';

const DAY = 86400000;
// 固定到本地某天 15:30，避免导出时间受运行时时区影响。
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
  // 只有空白的笔记不进导出：那是一条还没写的东西，不是内容。
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
  // done=false 是「还没读」，导出去会被当成待办清单。
  { targetKey: 'site:a', section: 'poems', done: false, updateTime: NOW - DAY, deviceId: 'deviceA' }
];

const ARCHIVE = () => buildArchive(NOTES, FAVS, FAV_TAGS, PROGRESS, LABELS, 'deviceA', NOW);

test('TargetLabels：遗址、分节、文物、随手笔记与未知键都有人话', () => {
  assert.equal(LABELS.label('site:a'), '小浪底遗址');
  assert.equal(LABELS.label('site:a:arch'), '小浪底遗址 · 考古');
  assert.equal(LABELS.label('site:a:nope'), '小浪底遗址 · nope');
  assert.equal(LABELS.label('relic:r1'), '彩陶罐');
  assert.equal(LABELS.label('notebook:inbox'), '随手笔记');
  // 语料里没有的 id / 认不出的键：退化为原文，不能空白
  assert.equal(LABELS.label('site:zz'), 'zz');
  assert.equal(LABELS.label('relic:zz'), 'zz');
  assert.equal(LABELS.label('weird'), 'weird');
  assert.equal(new TargetLabels().label('site:a'), 'a');
});

test('buildArchive：按更新时间倒序、丢空正文、只留已读段落、计数同源', () => {
  const a = ARCHIVE();
  assert.deepEqual(a.notes.map((n) => n.targetKey), ['site:a', 'site:a:arch', 'relic:r1']);
  assert.equal(a.counts.notes, 3);
  assert.equal(a.counts.favorites, 2);
  assert.equal(a.counts.progress, 1);
  assert.equal(a.notes[0].label, '小浪底遗址');
  assert.equal(a.notes[1].label, '小浪底遗址 · 考古');
  // 收藏标签按 targetKey 归并，一条收藏可以带多个标签
  assert.equal(a.favorites[0].targetKey, 'site:a');
  assert.deepEqual(a.favorites[0].tags, ['待实地探访', '研究资料']);
  assert.deepEqual(a.favorites[1].tags, []);
  assert.equal(a.progress[0].label, '小浪底遗址 · 考古');
  assert.equal(a.deviceId, 'deviceA');
  assert.equal(a.exportedAt, NOW);
});

test('exportMarkdown：三段齐全，正文用引用块，标题符号不会变成页面标题', () => {
  const md = exportMarkdown(ARCHIVE());
  assert.ok(md.startsWith('# 黄河记忆 · 我的档案\n'));
  assert.ok(md.includes('- 导出时间：2026-10-28 15:30'));
  assert.ok(md.includes('- 档案：手机'), 'deviceA 在导出件里读作「手机」，与赛题原文的手机/平板口径一致');
  assert.ok(md.includes('- 内容：笔记 3 条 · 收藏 2 条 · 已读 1 段'));
  assert.ok(md.includes('## 笔记'));
  assert.ok(md.includes('## 收藏'));
  assert.ok(md.includes('## 研读进度'));
  assert.ok(md.includes('### 小浪底遗址 · 考古'));
  assert.ok(md.includes('> 考古笔记'));
  assert.ok(md.includes('- 标签：待实地探访'));
  assert.ok(md.includes('- 关联：`site:a:arch`'));
  assert.ok(md.includes('- **小浪底遗址** —— 收于 2026-10-26 15:30'));
  assert.ok(md.includes('- 小浪底遗址 · 考古（2026-10-26 15:30）'));

  const withHeading = [
    { noteId: 'h', targetKey: 'site:a', text: '# 不是标题\n第二行', createTime: NOW, updateTime: NOW, tagIds: [] }
  ];
  const md2 = exportMarkdown(buildArchive(withHeading, [], [], [], LABELS, '', NOW));
  assert.ok(md2.includes('\n> # 不是标题\n> 第二行\n'));
  assert.ok(!/\n# 不是标题/.test(md2));
});

test('exportMarkdown / exportJson：空档案也有完整骨架，不出现缺字段', () => {
  const empty = buildArchive([], [], [], [], LABELS, '', NOW);
  const md = exportMarkdown(empty);
  assert.ok(md.includes('- 档案：本机'));
  assert.ok(md.includes('- 内容：笔记 0 条 · 收藏 0 条 · 已读 0 段'));
  assert.ok(md.includes('（没有笔记）'));
  assert.ok(md.includes('（没有收藏）'));
  assert.ok(md.includes('（还没有读过任何一段）'));

  const j = JSON.parse(exportJson(empty));
  assert.equal(j.schema, EXPORT_SCHEMA);
  assert.equal(j.app, '黄河记忆');
  // counts 多了一个 tags：自建标签定义随档案一起走（创新拓展第 2 条「完整迁移」）
  assert.deepEqual(j.counts, { notes: 0, favorites: 0, progress: 0, tags: 0 });
  assert.deepEqual(j.tags, []);
  assert.deepEqual(j.graph, { nodes: [], edges: [], stat: '' });
  assert.deepEqual(j.notes, []);
  assert.deepEqual(j.favorites, []);
  assert.deepEqual(j.progress, []);
});

test('exportJson：与 Markdown 同源，字段可原样取回', () => {
  const j = JSON.parse(exportJson(ARCHIVE()));
  assert.equal(j.counts.notes, 3);
  assert.deepEqual(j.notes.map((n) => n.targetKey), ['site:a', 'site:a:arch', 'relic:r1']);
  assert.equal(j.notes[1].label, '小浪底遗址 · 考古');
  assert.deepEqual(j.notes[1].tags, ['待实地探访']);
  assert.equal(j.favorites[0].label, '小浪底遗址');
  assert.equal(j.favorites[0].tags.length, 2);
  assert.equal(j.progress[0].section, 'arch');
  assert.equal(j.progress[0].done, true);
});

test('exportFileName：到分钟、可区分格式、连续导出不重名', () => {
  assert.equal(exportFileName(new Date(2026, 0, 5, 9, 7).getTime(), 'md'), 'huanghe-memory-20260105-0907.md');
  assert.equal(exportFileName(new Date(2026, 11, 31, 23, 59).getTime(), 'json'),
    'huanghe-memory-20261231-2359.json');
});
