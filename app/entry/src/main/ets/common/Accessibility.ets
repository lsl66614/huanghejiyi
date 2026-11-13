// entry/src/main/ets/common/Accessibility.ets
//
// 无障碍的单一入口：焦点环样式 + 读屏文案。页面不要直接调
// accessibility.* / FocusBoxStyle，一律经由本文件。
//
// 动效不在这里：时长、曲线、转场都归 Motion.ets。两者曾合在一个文件里，
// 结果是「时长」这个纯视觉参数挂在无障碍命名空间下，后来者以为改动它
// 必然影响读屏行为而不敢动，曲线就此散落成三份字面量。依赖方向只能是
// Motion → Accessibility，反过来不成立。
//
// 读系统设置：HarmonyOS 的「减弱动画」在设置 → 无障碍 → 视觉下，
// 由 Motion.ets 的 syncReduceMotion() 读取后转交本文件维护焦点环策略。
import { ColorMetrics, LengthMetrics } from '@kit.ArkUI';
import { FOCUS_RING_COLOR, FOCUS_RING_INSET_VP, FOCUS_RING_WIDTH_VP } from './DesignTokens';

// ---------------------------------------------------------------- 焦点环
// 用法：把 onClick 的宿主组件接上 focusable(true) + focusRing()，例如
//     Text('检索').onClick(...)
//       .focusable(true)
//       .focusRing()
//
// 它一次做两件事：让组件可聚焦，并给它全站统一的焦点环。
// 之所以合成一个方法而不是两个：可聚焦但没环（有焦点没指示）比不可聚焦
// 更糟——键盘用户会以为页面卡住了；只加 ring 不加 focusable 则什么都不会发生，
// 而「什么都不会发生」正是 47 处 Text 挂 onClick 的现状。
export function focusRing(): FocusBoxStyle {
  return {
    margin: LengthMetrics.vp(FOCUS_RING_INSET_VP),
    strokeColor: ColorMetrics.resourceColor(FOCUS_RING_COLOR),
    strokeWidth: LengthMetrics.vp(FOCUS_RING_WIDTH_VP)
  };
}

// ---------------------------------------------------------------- 无障碍文案
// 规则：accessibilityText 给「是什么」，accessibilityDescription 给「会怎样」。
// 两者都缺失时读屏只会念出可见文字的碎片（「›」「✕」「01」），
// 这是本项目当前最大的无障碍缺口——全站 accessibilityText 计数为 0。

/** 纯图标按钮：名字 + 结果。例：btn('关闭', '退出文物细观') */
export function btn(name: string, result: string): string {
  return `${name}，${result}`;
}

/** 卡片：标题 + 副信息。 */
export function card(title: string, meta: string): string {
  return meta.length > 0 ? `${title}，${meta}` : title;
}

/** 数量：把视觉数字念成有单位的说法。例：count(10, '处遗址') → 「10 处遗址」 */
export function count(n: number | string, unit: string): string {
  return `${n} ${unit}`;
}