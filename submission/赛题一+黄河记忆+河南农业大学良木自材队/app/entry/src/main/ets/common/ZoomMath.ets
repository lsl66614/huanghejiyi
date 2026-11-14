// entry/src/main/ets/common/ZoomMath.ets —— 灯箱缩放状态机（纯函数，禁 @kit）
//
// 为什么要从 ImageViewer 里劈出来：双指捏合在本项目的模拟器上注入不了
// （uitest uiInput 只有 click/doubleClick/longClick/swipe/drag/fling/keyEvent/text），
// 手势识别这一段只能人工验一次；但"能放大到什么、放大后能拖到哪"这套夹取规则
// 是 pinch 与双击共用的判断依据，它必须被单测钉住，否则交付物里就只剩
// "我手机上试过，挺好的"。
//
// 三条不变量：
//   下限 1×——图片永远不比"适应屏幕"更小，缩过头读作渲染坏了；
//   上限 ZOOM_MAX——到顶就停，不做橡皮筋；
//   平移半轴＝盒子半轴×(倍率−1)——这是 objectFit:Contain 后图片被放大
//   真正溢出的那一段，贴边即止，保证文物主体拖不出屏。

/** 不允许缩到比适应屏幕更小 */
export const ZOOM_MIN: number = 1;
/** 放大上限：再高就只剩像素 */
export const ZOOM_MAX: number = 4;
/** 双击落点：够看清器物纹饰，又不至于一次就顶到上限 */
export const ZOOM_TAP: number = 2.5;
/** 判"已放大"的死区：捏合收尾常留下 1.000x，此刻不该允许平移 */
const ZOOM_EPSILON: number = 0.001;

/** 平移量（vp），由 ImageViewer 的 translate 直接消费 */
export class ZoomOffset {
  dx: number = 0;
  dy: number = 0;
}

export function clampScale(raw: number): number {
  if (raw < ZOOM_MIN) { return ZOOM_MIN; }
  if (raw > ZOOM_MAX) { return ZOOM_MAX; }
  return raw;
}

export function isZoomed(scale: number): boolean {
  return scale > ZOOM_MIN + ZOOM_EPSILON;
}

/** 双击：已放大就回到适应屏幕，否则一步到 ZOOM_TAP（捏合停在中间值也算已放大） */
export function tapScale(cur: number): number {
  return isZoomed(cur) ? ZOOM_MIN : ZOOM_TAP;
}

export function clampOffset(dx: number, dy: number, scale: number,
  boxW: number, boxH: number): ZoomOffset {
  const out = new ZoomOffset();
  if (!isZoomed(scale)) { return out; }
  const maxX: number = boxW * (scale - ZOOM_MIN) / 2;
  const maxY: number = boxH * (scale - ZOOM_MIN) / 2;
  out.dx = dx > maxX ? maxX : (dx < -maxX ? -maxX : dx);
  out.dy = dy > maxY ? maxY : (dy < -maxY ? -maxY : dy);
  return out;
}
