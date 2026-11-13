// entry/src/main/ets/common/RevealOnScroll.ets
// 滚动揭示：包住一段内容，探进视口时从下方 18vp 升起并转正（REVEAL_* 令牌）。
//
// 为什么是组件而不是页面级状态：起始态（低透明度 + 下移）要等「进入视口」
// 这个事件来翻转，而列表条目与页面分区各有一份进入时机，状态必须各自持有。
// 为什么用 @BuilderParam 包内容：内容仍在父组件作用域里取状态；
// @Builder 不能按参数收父组件状态，所以包装器不做参数化。
// 可见比带取 [REVEAL_ENTER_RATIO, 1]：下沿不取 0——初始就压在 0 的元素
// 不算「已进入」，否则首屏之外的内容会在挂载时一起转正，揭示就没了。
// 减弱动画：enterAnim() 的时长在系统开关下折 0，直接落到目标态。

import { REVEAL_ENTER_RATIO } from './DesignTokens';
import { enterAnim, revealStart } from './Motion';

@Builder
function revealEmpty(): void {
}

@Component
export struct RevealOnScroll {
  @BuilderParam content: () => void = revealEmpty;
  @State private shown: boolean = false;
  private startOpacity: number = revealStart()[0];
  private startShiftVp: number = revealStart()[1];

  build() {
    Column() {
      this.content()
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .opacity(this.shown ? 1 : this.startOpacity)
    .translate({ y: this.shown ? 0 : this.startShiftVp })
    .onVisibleAreaChange([REVEAL_ENTER_RATIO, 1.0], (visible: boolean, _ratio: number) => {
      if (visible && !this.shown) {
        this.getUIContext().animateTo(enterAnim(), () => {
          this.shown = true;
        });
      }
    })
  }
}
