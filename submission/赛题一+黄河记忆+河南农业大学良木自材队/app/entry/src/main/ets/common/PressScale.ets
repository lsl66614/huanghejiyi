// entry/src/main/ets/common/PressScale.ets
// 按压反馈的统一实现：@State + onTouch(Down/Up/Cancel) + scale/opacity + animation。
//
// 为什么不再用 stateStyles({ pressed })：2026-10-09 在模拟器上逐像素实测
// （tools/press_probe.py），stateStyles 的按压态在本 SDK 抓不到按下态——
// 56 处能编译、能过门禁，但按住时屏幕零变化，连 pressed 里写死
// backgroundColor:'#FF0000' 都没有一像素变化。唯一被证实有效的是手写
// 的 onTouch 三段式（Index 年代卡，同法按压变化 42.5%，对照组 0%）。
//
// 为什么抽成组件而不是每处各写一套：三段式 onTouch 每处要配一个 @State
// 字段，60 处平铺会让「按压反馈」这件事散落 60 份。包装器只持有一份
// 状态，用 @BuilderParam 收内容——内容仍在调用方作用域里取状态，
// 与 RevealOnScroll 同一套机制（见该文件顶部注释）。
//
// 两种形态对应两类可点元素：
//   PressScale  有底色的卡片/胶囊/图片——只缩放不压暗。opacity 会连底色
//               一起变暗，整块色块像出了错；缩放只动几何，视觉上是
//               「被按下去」。
//   PressFade   无底色的文字/符号按钮——只压暗不缩放。缩放会让文字
//               边界内缩，小字会糊。
// 减弱动画：pressAnim() 的时长在系统开关下折 0，直接落到目标态。

import { pressAnim } from './Motion';
import { PRESS_OPACITY, PRESS_SCALE } from './DesignTokens';
import { focusRing } from './Accessibility';

/** 空内容占位：@BuilderParam 的默认值必须是无参无返回的构造。 */
@Builder
function pressEmpty(): void {
}

/**
 * 有底色元素的按压反馈：按下时整体缩到 PRESS_SCALE。
 * 内容由调用方以 @BuilderParam 传入，点击事件挂在调用方自己的节点上
 * （包装器不接管 onClick——那会改变事件冒泡的落点）。
 *
 * 为什么用 Stack 而不是 Column：包装器会多出一层布局节点，这层节点的
 * 尺寸规则必须与「内容原本的父容器」一致，否则布局会变形。
 *   · Column + width('100%')：芯片会被拉成整行宽，胶囊变成长条。
 *   · Column + 不设宽：内容里的 layoutWeight(1) 会在竖向被拉伸。
 * Stack 不设宽高时按最大子节点定尺寸，alignContent 取 TopStart，
 * 内容原样落在左上角——对「文本项 / 芯片 / 图片 / 卡片」都成立。
 *
 * 什么时候不能用包装器：子节点依赖父级 Row 的 layoutWeight 分配宽度
 * （AppNavBar 的底栏格、两个页面的并排 Button、列表卡内的 layoutWeight
 * 列）。这些改为在节点自身挂 onTouch 三段式，按压态记在页面的 @State 上。
 */
@Component
export struct PressScale {
  @BuilderParam content: () => void = pressEmpty;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .scale({ x: this.pressed ? PRESS_SCALE : 1, y: this.pressed ? PRESS_SCALE : 1 })
    .animation(pressAnim())
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }

  @State private pressed: boolean = false;
}

/**
 * 无底色文字/符号按钮的按压反馈：按下时透明度降到 PRESS_OPACITY。
 * 不缩放——小字缩放后边界内缩，笔画会糊。
 */
@Component
export struct PressFade {
  @BuilderParam content: () => void = pressEmpty;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .opacity(this.pressed ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
  }

  @State private pressed: boolean = false;
}
