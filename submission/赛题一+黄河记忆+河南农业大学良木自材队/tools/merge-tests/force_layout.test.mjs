// tools/merge-tests/force_layout.test.mjs —— 力导向布局的可测性验证
import test from 'node:test';
import assert from 'node:assert/strict';
import { forceLayout, ForceInput, cooccurrenceEdges } from '../.tsbuild/service/network/ForceLayout.ts';
import { buildGraph } from '../.tsbuild/service/network/NetworkSource.ts';
import { parseAll } from '../.tsbuild/service/content/ContentParse.ts';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const DIR = join(import.meta.dirname, '../../app/entry/src/main/resources/rawfile/sites');

function loadSites() {
  return parseAll(readdirSync(DIR).filter((f) => f.endsWith('.json')).map((f) => readFileSync(join(DIR, f), 'utf8')));
}

const sites = loadSites();

// 用真实语料构造一张图：收藏 8 处遗址 + 若干笔记标签
function realGraph() {
  const keys = [
    'site:yangshao_village', 'site:mianchi_yangshao', 'site:dahecun', 'site:banpo_unused',
    'site:erlitou', 'site:yanshi_shangcheng', 'site:zhengzhou_shangcheng',
    'site:hanwei_luoyangcheng', 'site:song_ling', 'site:dongjing'
  ];
  const notes = [
    { targetKey: 'site:yangshao_village', tagIds: ['彩陶', '命名地'] },
    { targetKey: 'site:mianchi_yangshao', tagIds: ['彩陶'] },
    { targetKey: 'site:dahecun', tagIds: ['彩陶', '龙山'] },
    { targetKey: 'site:erlitou', tagIds: ['青铜', '都邑'] },
    { targetKey: 'site:yanshi_shangcheng', tagIds: ['青铜'] },
    { targetKey: 'site:zhengzhou_shangcheng', tagIds: ['青铜', '都邑'] },
    { targetKey: 'site:hanwei_luoyangcheng', tagIds: ['都城'] },
    { targetKey: 'site:song_ling', tagIds: ['都城'] },
    { targetKey: 'site:dongjing', tagIds: ['都城', '市井'] }
  ];
  return buildGraph(sites, keys, notes);
}

test('力导向：确定性 —— 同一份输入两次跑，坐标完全一致', () => {
  const g = realGraph();
  const input = new ForceInput();
  input.nodes = g.nodes;
  input.edges = g.forces;
  const a = forceLayout(input, 800, 600, 34);
  const b = forceLayout(input, 800, 600, 34);
  assert.equal(a.size, b.size);
  a.forEach((pa, id) => {
    const pb = b.get(id);
    assert.ok(pb !== undefined, `第二次少了节点 ${id}`);
    assert.equal(pa[0], pb[0], `${id} x 不一致`);
    assert.equal(pa[1], pb[1], `${id} y 不一致`);
  });
});

test('力导向：所有节点都落在画布内（含边距）', () => {
  const g = realGraph();
  const input = new ForceInput();
  input.nodes = g.nodes;
  input.edges = g.forces;
  const W = 800, H = 600, PAD = 34;
  const pos = forceLayout(input, W, H, PAD);
  pos.forEach((p, id) => {
    assert.ok(p[0] >= PAD && p[0] <= W - PAD, `${id} x=${p[0].toFixed(1)} 出界`);
    assert.ok(p[1] >= PAD && p[1] <= H - PAD, `${id} y=${p[1].toFixed(1)} 出界`);
  });
});

test('力导向：中心根固定在画布正中', () => {
  const g = realGraph();
  const input = new ForceInput();
  input.nodes = g.nodes;
  input.edges = g.forces;
  const pos = forceLayout(input, 800, 600, 34);
  const root = pos.get('root');
  assert.ok(root !== undefined);
  assert.equal(root[0], 400);
  assert.equal(root[1], 300);
});

test('力导向：共现多的站点被拉得更近（彩陶三处 vs 分散的都城）', () => {
  const g = realGraph();
  const input = new ForceInput();
  input.nodes = g.nodes;
  input.edges = g.forces;
  const pos = forceLayout(input, 900, 700, 34);
  const dist = (a, b) => {
    const pa = pos.get(a), pb = pos.get(b);
    if (pa === undefined || pb === undefined) { return 1e9; }
    return Math.hypot(pa[0] - pb[0], pa[1] - pb[1]);
  };
  // 彩陶共现：yangshao_village ↔ mianchi_yangshao ↔ dahecun
  const dClose = Math.min(
    dist('site:yangshao_village', 'site:mianchi_yangshao'),
    dist('site:yangshao_village', 'site:dahecun'),
    dist('site:mianchi_yangshao', 'site:dahecun')
  );
  // 无共现的一对：dongjing ↔ erlitou
  const dFar = dist('site:dongjing', 'site:erlitou');
  assert.ok(dClose < dFar, `共现组 ${dClose.toFixed(1)} 未近于非共现组 ${dFar.toFixed(1)}`);
});

test('力导向：非空 —— 空输入返回空表，不抛异常', () => {
  const input = new ForceInput();
  const pos = forceLayout(input, 800, 600, 34);
  assert.equal(pos.size, 0);
});

test('力导向：单节点自持 —— 只有一个节点时也能定位', () => {
  const g = buildGraph(sites, ['site:erlitou'], []);
  const input = new ForceInput();
  input.nodes = g.nodes;
  input.edges = g.forces;
  const pos = forceLayout(input, 800, 600, 34);
  assert.ok(pos.size > 0);
  assert.ok(pos.get('root') !== undefined);
});

test('cooccurrenceEdges：共现次数正确聚合并按字典序定 A/B', () => {
  const m = new Map();
  m.set('彩陶', ['site:a', 'site:b', 'site:c']);
  m.set('龙山', ['site:b', 'site:c']);
  const edges = cooccurrenceEdges(['site:a', 'site:b', 'site:c'], m);
  // a-b: 彩陶 → 1；a-c: 彩陶 → 1；b-c: 彩陶+龙山 → 2
  const get = (x, y) => edges.find((e) => e.a === x && e.b === y);
  assert.equal(get('site:a', 'site:b').weight, 1);
  assert.equal(get('site:a', 'site:c').weight, 1);
  assert.equal(get('site:b', 'site:c').weight, 2);
});

test('buildGraph 出力：forces 非空且权重 ≥1，forceTags 键为 "a|b"', () => {
  const g = realGraph();
  assert.ok(g.forces.length > 0, 'forces 为空');
  for (const e of g.forces) {
    assert.ok(e.weight >= 1, `权重 ${e.weight} < 1`);
    assert.ok(e.a !== '' && e.b !== '');
  }
  g.forceTags.forEach((tags, key) => {
    assert.equal(key.split('|').length, 2, `键 ${key} 不是 a|b`);
    assert.ok(tags.length >= 1, `键 ${key} 无标签`);
  });
});

test('buildGraph：无收藏时 empty 为 true 且不崩', () => {
  const g = buildGraph(sites, [], []);
  assert.equal(g.empty, true);
  assert.equal(g.nodes.length, 1); // 只有根
});
