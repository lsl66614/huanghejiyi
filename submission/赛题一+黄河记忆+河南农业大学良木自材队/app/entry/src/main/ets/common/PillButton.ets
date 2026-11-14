// entry/src/main/ets/common/PillButton.ets
// 胶囊按钮的唯一实现（主 / 次两档）。
//
// 制式（清单 §1）：高度恒 CAPSULE_H 48 + CAPSULE_RADIUS 24，
// **禁用 padding 凑高**（此前六处按钮各自用 top/bottom padding 撑高度，
// 结果同一页里出现 36/40/44/48 四种高度）。
// 主 = ACCENT 实底白字；次 = 白底 + 发丝描边 + INK 字。
//
// 禁用态（清单 §3.4，本轮新增）：
// **不要用 Button(...).enabled(false)**。ArkUI 的系统禁用外观会把自定义的
// backgroundColor / border / fontColor 全部盖掉，表现为"一块灰斑"——
// SyncPage:546 的「切换身份」按钮就是这么坏掉的。
// 正解：自己持一个 disabled 态，降 opacity 与字色、**保留描边轮廓**，
// onClick 内提前 return；读屏侧补"当前不可用"。
import {
  ACCENT, CAPSULE_H, CAPSULE_RADIUS, FONT_SANS, FS_BODY, HAIR,
  INK, LINE_HAIR, PRESS_OPACITY, SUB, SURFACE_CARD, WT_BOLD
} from './DesignTokens';
import { focusRing } from './Accessibility';
import { pressAnim } from './Motion';

@Component
export struct PillButton {
  @Prop label: string = '';
  // secondary = true 走描边次级档；同一页只允许出现一个实心主按钮（清单 N4）。
  @Prop secondary: boolean = false;
  @Prop disabled: boolean = false;
  // fill = true 撑满父容器宽度。给「两个按钮平分一行」用：
  // 自定义组件调用点上链 layoutWeight(1) 不生效（实测宽度仍按内容定），
  // 所以把"占满"做成组件内部属性，而不是在页面上凑。
  @Prop fill: boolean = false;
  onPress: () => void = () => {};
  @State private pressed: boolean = false;

  build() {
    Text(this.label)
      .fontSize(FS_BODY)
      .fontFamily(FONT_SANS)
      .fontWeight(WT_BOLD)
      .fontColor(this.secondary ? INK : SURFACE_CARD)
      .textAlign(TextAlign.Center)
      .width(this.fill ? '100%' : 'auto')
      .height(CAPSULE_H)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.secondary ? SURFACE_CARD : ACCENT)
      .border({
        width: HAIR,
        color: this.secondary ? LINE_HAIR : ACCENT
      })
      .borderRadius(CAPSULE_RADIUS)
      // 禁用：降透明度但保留描边轮廓，不交给系统禁用外观
      .opacity(this.disabled ? 0.45 : (this.pressed ? PRESS_OPACITY : 1))
      .animation(pressAnim())
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.pressed = true;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => {
        if (this.disabled) { return; }
        this.onPress();
      })
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(this.disabled ? `${this.label}，当前不可用` : this.label)
      .accessibilityLevel('yes')
  }
}
