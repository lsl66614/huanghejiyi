// tools/merge-tests/zoom.test.mjs —— 灯箱缩放的夹取与平移边界
//
// ImageViewer 的手势接线（PinchGesture / TapGesture / PanGesture）在 ArkUI 侧，
// 进不了 Node 转译体系；这里锁的是它唯一的判断依据——缩放状态机本身。
// 之所以值得单独成模块：双指捏合在本模拟器上无法用 uitest 注入（只有
// click/doubleClick/longClick/swipe/drag/fling/keyEvent/text），屏上实测只能覆盖
// 双击与平移两条路，pinch 走的是同一组函数。函数钉住了，未证的就只剩事件接线。
//
// 每条用例对应一个"改掉就会出故障"的生产改动：
// 夹取下限 → 图片被缩得比适应屏幕还小，读作渲染坏了；
// 夹取上限 → 无限放大到像素糊；
// 平移边界 → 放大后一拖就把文物拖出屏外，只剩黑底；
// 未放大不平移 → 1× 状态下手指会把图片拖离中心再也回不去。
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  ZOOM_MIN, ZOOM_MAX, ZOOM_TAP, clampScale, tapScale, isZoomed, clampOffset
} from '../.tsbuild/common/ZoomMath.ts';

test('下限：缩到小于适应屏幕被抬回 1×', () => {
  assert.equal(clampScale(0.4), ZOOM_MIN);
  assert.equal(clampScale(0.999), ZOOM_MIN);
});

test('上限：放大过 4× 被夹住', () => {
  assert.equal(clampScale(9), ZOOM_MAX);
  assert.equal(clampScale(1e9), ZOOM_MAX);
});

test('区间内原样保留，含两端点', () => {
  assert.equal(clampScale(1), 1);
  assert.equal(clampScale(2.3), 2.3);
  assert.equal(clampScale(4), 4);
});

test('双击往复：1× 放大到 2.5×，其余任何倍率回到 1×', () => {
  assert.equal(ZOOM_TAP, 2.5);
  assert.equal(tapScale(1), ZOOM_TAP);
  assert.equal(tapScale(ZOOM_TAP), ZOOM_MIN, '再点一次必须回到适应屏幕');
  // 捏合停在中间值（比如 3.1×）时双击，不该停在原地，也不该继续放大
  assert.equal(tapScale(3.1), ZOOM_MIN);
});

test('isZoomed 有防抖死区：捏合残留的 1.0004 不算已放大', () => {
  assert.equal(isZoomed(1), false);
  assert.equal(isZoomed(1.0004), false);
  assert.equal(isZoomed(1.01), true);
});

test('未放大时平移归零：1× 下拖不动图片', () => {
  const o = clampOffset(-800, 1200, 1, 1260, 1900);
  assert.equal(o.dx, 0);
  assert.equal(o.dy, 0);
});

test('平移上限＝盒子半轴×(倍率−1)：2× 时横向最多 630', () => {
  const o = clampOffset(5000, 5000, 2, 1260, 1900);
  assert.equal(o.dx, 630);
  assert.equal(o.dy, 950);
});

test('未越界时原样返回，且负方向对称', () => {
  assert.equal(clampOffset(-200, 300, 2, 1260, 1900).dx, -200);
  assert.equal(clampOffset(300, -200, 2, 1260, 1900).dy, -200);
  const far = clampOffset(-99999, -99999, 4, 1260, 1900);
  assert.equal(far.dx, -1890, '4× 时半轴＝1260×3/2');
  assert.equal(far.dy, -2850);
});
