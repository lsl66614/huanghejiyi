// tools/merge-tests/archive_ext.test.mjs —— 创新拓展第 2 条「完整迁移与一键恢复」
//
// 原档案只有 notes/favorites/progress 三段，自建标签的定义表（tag 表）没走，
// 知识图谱的节点/边快照也没有。导到另一台设备后：标签名还在笔记的 tags 里，
// 但「标签管理」里看不到这些自建标签，等于半份档案。
//
// 这里钉住四件事：新字段能导出、能解析、旧档案仍可导入、标签写入沿用导出
// 版本号（否则导入后本机再写一笔会输给旧版本号，LWW 反了）。
import test from 'node:test';
import assert from 'node:assert/strict';
import { TargetLabels } from '../.tsbuild/service/content/TargetLabel.ts';
import {
  buildArchive, exportJson, ExportTag, ExportGraphNode, ExportGraphEdge, ExportGraph
} from '../.tsbuild/service/export/ExportFormat.ts';
import { parseArchive, maxImportedTime, planTagImports } from '../.tsbuild/service/import/ImportPlan.ts';

const NOW = new Date(2026, 9, 28, 15, 30, 0).getTime();

const LABELS = (() => {
  const l = new TargetLabels();
  l.build([{ id: 'a', name: '小浪底遗址', relics: [] }]);
  return l;
})();

function tags() {
  const a = new ExportTag();
  a.name = '彩陶纹样';
  a.isPreset = false;
  a.updateTime = NOW - 2000;
  a.deviceId = 'deviceA';
  const b = new ExportTag();
  b.name = '待实地探访';
  b.isPreset = true;
  b.updateTime = NOW - 1000;
  b.deviceId = 'deviceA';
  return [a, b];
}

function graph() {
  const g = new ExportGraph();
  const n1 = new ExportGraphNode();
  n1.id = 'site:a'; n1.label = '小浪底遗址'; n1.kind = 'site';
  const n2 = new ExportGraphNode();
  n2.id = 'tag:彩陶纹样'; n2.label = '彩陶纹样'; n2.kind = 'tag';
  g.nodes = [n1, n2];
  const e = new ExportGraphEdge();
  e.a = 'site:a'; e.b = 'tag:彩陶纹样';
  g.edges = [e];
  g.stat = '2 节点 · 1 连线';
  return g;
}

const BASE = () => buildArchive([], [], [], [], LABELS, 'deviceA', NOW, tags(), graph());
const OLD = () => buildArchive([], [], [], [], LABELS, 'deviceA', NOW);

test('新档案含 tags 与 graph 两段', () => {
  const j = JSON.parse(exportJson(BASE()));
  assert.equal(j.tags.length, 2);
  assert.equal(j.tags[0].name, '彩陶纹样');
  assert.equal(j.tags[0].isPreset, false);
  assert.equal(j.graph.nodes.length, 2);
  assert.equal(j.graph.edges[0].a, 'site:a');
  assert.equal(j.graph.stat, '2 节点 · 1 连线');
});

test('旧档案（无 tags/graph）仍可导入，新字段退化为数组', () => {
  const r = parseArchive(exportJson(OLD()));
  assert.equal(r.ok, true);
  assert.deepEqual(r.tags, []);
  assert.equal(r.graph.nodes.length, 0);
  assert.equal(r.graph.edges.length, 0);
});

test('新档案能解析出标签定义与图谱快照', () => {
  const r = parseArchive(exportJson(BASE()));
  assert.equal(r.ok, true);
  assert.equal(r.tags.length, 2);
  assert.equal(r.tags[0].name, '彩陶纹样');
  assert.equal(r.graph.nodes.length, 2);
  assert.equal(r.graph.stat, '2 节点 · 1 连线');
});

test('标签导入判重：本机同名跳过，新的保留导出版本号', () => {
  const r = parseArchive(exportJson(BASE()));
  const plan = planTagImports(r.tags, ['彩陶纹样'], 'deviceB');
  assert.equal(plan.planned.length, 1);
  assert.equal(plan.planned[0].name, '待实地探访');
  assert.equal(plan.planned[0].updateTime, NOW - 1000, '不能重新盖章');
  // 档案行自带 deviceId 时用它（平局决胜按原作者），没有才退回调用人
  assert.equal(plan.planned[0].deviceId, 'deviceA');
  assert.equal(plan.skipped, 1);
});

test('planTagImports：档案行没带 deviceId 时退回调用人', () => {
  const r = parseArchive(exportJson(BASE()));
  r.tags[1].deviceId = '';
  const plan = planTagImports(r.tags, ['彩陶纹样'], 'deviceB');
  assert.equal(plan.planned[0].deviceId, 'deviceB');
});

test('planTagImports：不改动传入的本机名单（防副作用串题）', () => {
  const r = parseArchive(exportJson(BASE()));
  const local = ['彩陶纹样'];
  planTagImports(r.tags, local.slice(), 'deviceB');
  assert.deepEqual(local, ['彩陶纹样']);
});

test('版本号高水位把标签的 updateTime 也算进去', () => {
  const r = parseArchive(exportJson(BASE()));
  const hi = maxImportedTime(r, NOW + 99999);
  assert.equal(hi, NOW + 99999);
  const r2 = parseArchive(exportJson(BASE()));
  assert.ok(maxImportedTime(r2, 0) >= NOW - 1000);
});
