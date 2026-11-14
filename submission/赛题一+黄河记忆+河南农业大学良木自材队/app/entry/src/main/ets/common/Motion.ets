// entry/src/main/ets/common/Motion.ets
// 全站动效的唯一入口：时长、曲线、几何、以及路由转场。
//
// 为什么从 Accessibility.ets 独立出来：动效与无障碍文案是两件事。
// 混在一起时「时长」这个纯视觉参数挂在 a11y 命名空间下，后来者会以为
// 改动它必然影响读屏行为，从而不敢动——这正是曲线至今散落三处的原因。
// 动效依赖 a11y（要读「减弱动画」开关），a11y 不依赖动效，单向依赖。
//
// 全站三条硬规矩，违反任意一条即为缺陷：
//   1. 时长不许写数字，只能用 dur*()——否则系统「减弱动画」开关失效。
//   2. 曲线不许用 Curve.* 字面量，只能用 CURVE_* 令牌。
//   3. 位置不许写死，用 pressReveal / revealShift 等几何常量。
// 这三条由 tools/lint_motion.py 逐条守。

import { accessibility } from '@kit.AccessibilityKit';
import { CURVE_IN, CURVE_INOUT, CURVE_OUT, DURATION_BASE, DURATION_FAST,
  DURATION_ROUTE_IN, DURATION_ROUTE_OUT, DURATION_SCROLL_TO, DURATION_SLOW,
  PRESS_OPACITY, PRESS_SCALE, REVEAL_FADE_MIN, REVEAL_SHIFT_VP, ROUTE_FADE_MIN,
  ROUTE_SHIFT_VP } from './DesignTokens';

let reduceEnabled: boolean = false;

/** 读系统「减弱动画」。EntryAbility 启动时调一次，之后靠 onChange 增量更新。 */
export function syncReduceMotion(): void {
  try {
    reduceEnabled = accessibility.isAnimationReduceEnabledSync();
  } catch (err) {
    reduceEnabled = false;
  }
}

export function onReduceMotionChanged(reduced: boolean): void {
  reduceEnabled = reduced;
}

export function isReduceMotion(): boolean {
  return reduceEnabled;
}

// ---------------------------------------------------------------- 时长

/** 减弱动画时统一折成 0：不是「变快」，是「不播」。 */
export function dur(base: number): number {
  return reduceEnabled ? 0 : base;
}

export function durFast(): number {
  return dur(DURATION_FAST);
}

export function durBase(): number {
  return dur(DURATION_BASE);
}

export function durSlow(): number {
  return dur(DURATION_SLOW);
}

export function durScrollTo(): number {
  return dur(DURATION_SCROLL_TO);
}

// ---------------------------------------------------------------- 曲线

/**
 * 曲线令牌要跟着减弱动画一起降级，否则「0 毫秒 + EaseInOut」虽然
 * 不会动，但 ArkUI 仍会跑一帧布局，白花开销还在。
 */
export function curveOut(): Curve {
  return reduceEnabled ? Curve.Linear : CURVE_OUT;
}

export function curveIn(): Curve {
  return reduceEnabled ? Curve.Linear : CURVE_IN;
}

export function curveInOut(): Curve {
  return reduceEnabled ? Curve.Linear : CURVE_INOUT;
}

/** 按压反馈的统一动画参数。 */
export function pressAnim(): AnimateParam {
  return { duration: durFast(), curve: curveOut() };
}

/** 进场类动画的统一参数（筛选条选中、卡片展开）。 */
export function enterAnim(): AnimateParam {
  return { duration: durBase(), curve: curveOut() };
}

/** 大区块展开：唯一用慢档的地方。 */
export function expandAnim(): AnimateParam {
  return { duration: durSlow(), curve: curveOut() };
}

// ---------------------------------------------------------------- 按压几何

export function pressScale(pressed: boolean): number {
  return pressed ? PRESS_SCALE : 1;
}

export function pressOpacity(pressed: boolean): number {
  return pressed ? PRESS_OPACITY : 1;
}

/**
 * 按压态的写法：**全站走 common/PressScale.ets 的两个包装器**，
 * 不再有人手写 .stateStyles({ pressed })。
 *
 * 为什么弃用 stateStyles：2026-10-09 在模拟器（127.0.0.1:5555）上
 * 逐像素实测（tools/press_probe.py 比对基线与按压中的截图），
 * stateStyles 的按压态在本 SDK 抓不到按下态——全站 60 处能编译、
 * 能过全部门禁，但按住时屏幕上零变化，连 pressed 里写死
 * backgroundColor:'#FF0000' 都没有一像素变化。唯一被证实有效的是
 * Index 年代卡早先手写的那套（@State + .onTouch(Down/Up/Cancel) +
 * .opacity()/.scale() + .animation()），本轮把全站改成同一套机制。
 *
 * 实测过程：
 *   - 按下态注入确实有效：`uinput -T -d x y -i 15000` 日志打印 touch down，
 *     同坐标改用 `-c` 点击也确实跳页了，事件真的到达了组件。
 *   - 对照组有效：年代卡（手写 onTouch）在同样按法下变化 42.5%，而
 *     「什么都不按、纯等 3 秒」的对照组变化 0% —— 探针抓得住按下态，
 *     抓不到的是 stateStyles 本身。
 *   - 不是 UI 语法丢标识符：把令牌换成字面量 opacity 0.3 同样为 0。
 *   - 不是没进产物：编译产物 modules.abc 里 'pressed' 键存在。
 *   - 不是输入通道问题：鼠标通道（uinput -M）同样为 0。
 *
 * 2026-10-24 复盘：全站改成 onTouch 之后**又踩了一个更隐蔽的坑**。
 * 最初把状态变更包在 animateTo 里（`animateTo(pressAnim(), () => {
 * this.pressed = true })`），编译通过、onTouch 也确实触发了（hilog
 * 里能看到 type=0 与 set pressed=true），但屏幕上仍然零变化。原因是
 * animateTo 的状态变更动画会与 .animation() 的属性动画互相打断——
 * 两者都想独占被改属性的过渡，最终谁都没插上值。
 * 正确写法是**直接赋值**，让 .animation() 自己插值：
 *   this.pressed = true;   // 不包 animateTo
 *   .animation(pressAnim()) // 插值由它做
 * 全站 34 处内联 onTouch + 两个包装器都按这个改完，逐像素复测通过
 * （几何型 20.8% / 边界内缩，透明型 15.2% / 包围盒不变而变浅）。
 * 复测脚本：tools/press_probe_e2e.sh --by-text "<文本>"。
 *
 * 现在的两条路：
 *   常规节点  套 PressScale()（有底色，缩放）或 PressFade()（无底色，
 *             压暗）。包装器用 @BuilderParam 收内容，内容仍在调用方
 *             作用域里取状态。
 *   特殊节点  容器/Canvas/绝对定位的徽章不能套包装器（多一层会改
 *             命中区或定位基准），就地在链上写同一套 onTouch 三段式，
 *             按压态记在页面的 @State 上。
 *
 * 为什么两种反馈分开：有底色的只缩放不压暗——opacity 会连底色一起
 * 变暗，整块色块像出了错；缩放只动几何，视觉上是「被按下去」。
 * 无底色的文字只压暗不缩放——缩放会让小字边界内缩，笔画会糊。
 */

// ---------------------------------------------------------------- 滚动揭示

/**
 * 揭示动画的起止状态。返回 [起始, 目标] 两组，调用方分别绑到
 * .opacity / .translate，避免各处自己算偏移。
 * 统一入口是 common/RevealOnScroll.ets——页面与列表不要自己绑这套值。
 */
export function revealStart(): [number, number] {
  return [REVEAL_FADE_MIN, REVEAL_SHIFT_VP];
}

/**
 * 路由转场：非对称，进 ease-out、出 ease-in。
 *
 * 为什么非对称：入场是「吸引视线」，该快起慢收；退场是「让路」，
 * 该慢起快走。同一条曲线两边共用时，退场会显得黏手——用户连点返回，
 * 上一屏还没走完就被压掉了。
 *
 * **为什么这段不能抽成函数**：PageTransitionEnter / PageTransitionExit 是
 * UI 组件语法（ArkTS 报 10905236 "cannot be used in this place"），
 * 只能写在页面自身的 pageTransition() 钩子里。十页因此各写一遍，
 * 但取值全部来自本文件——dur() / curveOut() / ROUTE_SHIFT_VP，
 * 几何与时序仍然只有一处定义。lint_motion.py 逐页比对这三者，
 * 任何一页偷偷改了数字或漏写钩子都会被拦下。
 *
 * 每页的标准写法：
 *
 *   pageTransition(): void {
 *     PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
 *       .translate({ x: ROUTE_SHIFT_VP, y: 0 })
 *       .opacity(ROUTE_FADE_MIN);
 *     PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
 *       .translate({ x: ROUTE_SHIFT_VP, y: 0 })
 *       .opacity(ROUTE_FADE_MIN);
 *   }
 *
 * 为什么没有更好的入口：router.pushUrl 的 transition 参数已于 API 18
 * 废弃，Navigation 组件是另一套路由体系——为了一次转场把十页搬进
 * Navigation 容器，代价远大于收益。
 */
export function durRouteIn(): number {
  return dur(DURATION_ROUTE_IN);
}

export function durRouteOut(): number {
  return dur(DURATION_ROUTE_OUT);
}