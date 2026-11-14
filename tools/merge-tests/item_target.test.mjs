// tools/merge-tests/item_target.test.mjs —— 单条内容条目的笔记 target_key
//
// 赛题主要功能第 2 条写的是「对任意内容条目添加自定义笔记」：原来只有
// 全篇 / 五段分节 / 文物 / 随手四种粒度，单条诗词、单条事件、单张图挂不上。
// 新键 site:{id}:poems:i0 这种形式，label 必须能把序号念出来，否则同一个
// 遗址下三首诗词的笔记在列表里全叫「班村遗址 · 诗词」，用户分不清。
import test from 'node:test';
import assert from 'node:assert/strict';
import { itemTargetKey, itemLabel } from '../.tsbuild/service/content/ItemTarget.ts';
import { TargetLabels } from '../.tsbuild/service/content/TargetLabel.ts';

test('itemTargetKey：三种条目各有稳定键，含从 0 起的序号', () => {
  assert.equal(itemTargetKey('bancun', 'poems', 0), 'site:bancun:poems:i0');
  assert.equal(itemTargetKey('bancun', 'events', 2), 'site:bancun:events:i2');
  assert.equal(itemTargetKey('bancun', 'images', 5), 'site:bancun:images:i5');
});

test('itemLabel：诗词/事件/图片各有量词，序号按 1 起念', () => {
  assert.equal(itemLabel('site:bancun:poems:i0', '班村遗址'), '班村遗址 · 诗词 · 第1首');
  assert.equal(itemLabel('site:bancun:events:i2', '班村遗址'), '班村遗址 · 历史 · 第3条');
  assert.equal(itemLabel('site:bancun:images:i5', '班村遗址'), '班村遗址 · 图集 · 第6张');
});

test('itemLabel：非条目键返回空串，交回原来的段落/文物映射', () => {
  assert.equal(itemLabel('site:bancun', '班村遗址'), '');
  assert.equal(itemLabel('site:bancun:poems', '班村遗址'), '');
  assert.equal(itemLabel('relic:r1', '班村遗址'), '');
  assert.equal(itemLabel('notebook:inbox', '班村遗址'), '');
  assert.equal(itemLabel('site:bancun:unknown:i0', '班村遗址'), '');
  assert.equal(itemLabel('site:bancun:poems:bad', '班村遗址'), '');
});

test('TargetLabels：新键走条目映射，五段分节键不受影响', () => {
  const l = new TargetLabels();
  assert.equal(l.label('site:bancun:poems:i1'), 'bancun · 诗词 · 第2首');
  assert.equal(l.label('site:bancun:poems'), 'bancun · 诗词');
  assert.equal(l.label('site:bancun'), 'bancun');
});
