// tools/merge-tests/network_graph.test.mjs
// 主题网络图的节点跳转：文物节点 id 只有 relic:{id}，所属遗址要从图上那条
// site → relic 的叶边反查；查不到时调用方退回「选中」而不是跳空页面。
import test from 'node:test';
import assert from 'node:assert/strict';
import { ownerSiteOf, expansionSeed, unseenSiteIds, NetGraph, NetNode, NetEdge } from '../.tsbuild/service/network/NetworkSource.ts';

function node(id) {
  const n = new NetNode();
  n.id = id;
  return n;
}

function edge(a, b) {
  const e = new NetEdge();
  e.a = a;
  e.b = b;
  return e;
}

function graph() {
  const g = new NetGraph();
  g.nodes.push(node('root'), node('era:yangshao'), node('site:bancun'), node('relic:r1'), node('tag:彩陶'));
  g.edges.push(edge('root', 'era:yangshao'));
  g.edges.push(edge('era:yangshao', 'site:bancun'));
  g.edges.push(edge('site:bancun', 'relic:r1'));
  g.edges.push(edge('site:bancun', 'tag:彩陶'));
  return g;
}

test('文物节点 → 反查出所属遗址 id', () => {
  assert.equal(ownerSiteOf(graph(), 'relic:r1'), 'bancun');
});

test('遗址节点没有入边（只有指向文物的出边），查不到就返回空串', () => {
  assert.equal(ownerSiteOf(graph(), 'site:bancun'), '');
});

test('函数只按「边的目标 id」反查，标签节点同样能查到所属遗址（调用方只对 relic: 调用）', () => {
  assert.equal(ownerSiteOf(graph(), 'tag:彩陶'), 'bancun');
});

test('节点不在图里 → 空串', () => {
  assert.equal(ownerSiteOf(graph(), 'relic:不存在'), '');
});

test('空图不崩', () => {
  assert.equal(ownerSiteOf(new NetGraph(), 'relic:r1'), '');
});

test('同一文物被两条边指向时取第一条 site 边（图不该出现，但不崩）', () => {
  const g = graph();
  g.edges.push(edge('site:other', 'relic:r1'));
  assert.equal(ownerSiteOf(g, 'relic:r1'), 'bancun');
});

// ── 拓展推荐（赛题创新拓展第 1 条「并推荐拓展内容」）──────────────────
// 网络图原先只回答「我收藏的东西之间怎么连」，没回答「顺着这条脉络还能看什么」。
// 推荐算法本身复用 RecommendService，这里只定两件事：拿哪个节点当种子、
// 以及结果里哪些是图上还没有的。

function richGraph() {
  const g = new NetGraph();
  g.nodes.push(node('root'), node('era:yangshao'), node('site:bancun'),
    node('site:dahecun'), node('relic:r1'), node('tag:彩陶'));
  g.edges.push(edge('root', 'era:yangshao'));
  g.edges.push(edge('era:yangshao', 'site:bancun'));
  g.edges.push(edge('era:yangshao', 'site:dahecun'));
  g.edges.push(edge('site:bancun', 'relic:r1'));
  g.edges.push(edge('site:bancun', 'tag:彩陶'));
  g.edges.push(edge('site:dahecun', 'tag:彩陶'));
  return g;
}

test('expansionSeed：选中遗址节点就用它当种子', () => {
  assert.equal(expansionSeed(richGraph(), 'site:dahecun'), 'site:dahecun');
});

test('expansionSeed：选中文物节点退回它的所属遗址', () => {
  assert.equal(expansionSeed(richGraph(), 'relic:r1'), 'site:bancun');
});

test('expansionSeed：选中标签/年代/根或没选时，取连边最多的遗址（平局按 id 字典序）', () => {
  // bancun 3 条边、dahecun 2 条
  for (const p of ['tag:彩陶', 'era:yangshao', 'root', '']) {
    assert.equal(expansionSeed(richGraph(), p), 'site:bancun', p);
  }
  const g = richGraph();
  g.edges = g.edges.filter((e) => !(e.a === 'site:bancun' || e.b === 'site:bancun'));
  // 只剩 dahecun 一个遗址时也要给出种子
  assert.equal(expansionSeed(g, ''), 'site:dahecun');
});

test('expansionSeed：图里没有遗址节点（空图/只有根）返回空串', () => {
  assert.equal(expansionSeed(new NetGraph(), ''), '');
  const g = new NetGraph();
  g.nodes.push(node('root'));
  assert.equal(expansionSeed(g, 'root'), '');
});

test('unseenSiteIds：滤掉图上已有的遗址，保持输入顺序', () => {
  const g = richGraph();
  assert.deepEqual(unseenSiteIds(g, ['qingtai', 'bancun', 'erlitou']), ['qingtai', 'erlitou']);
  assert.deepEqual(unseenSiteIds(g, ['bancun', 'dahecun']), []);
  assert.deepEqual(unseenSiteIds(new NetGraph(), ['a', 'b']), ['a', 'b']);
});
