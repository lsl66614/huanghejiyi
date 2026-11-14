// entry/src/main/ets/common/IconButton.ets
// 页头圆形图标按钮：设计稿的「Actions」组（36×36 白底 + 发丝描边 + 18 圆角）。
//
// 为什么独立成件：设计稿里同步页 3 颗、档案页 4 颗，每颗都是同一个形状
// （白底 / 发丝环 / 居中 16px 图标）。此前各页各写一遍，
// 尺寸与描边色各写各的，现在是 40/20 与 36/18 两套并存。
import { FS_TITLE, HAIR, INK, LINE_HAIR, NAV_ICON_BTN_H, NAV_ICON_BTN_RADIUS, SURFACE_CARD } from './DesignTokens';
import { focusRing } from './Accessibility';

// 图标边长（svg 自身 16×16，按钮 36 内居中）
const ICON_SIZE: number = 16;

@Component
export struct IconButton {
  // svg 基准名（不含前后缀），实际路径按 icons/ic_<icon>_ink.svg 取。
  // 与 AppNavBar 的 ic_<名>_<ink|red> 命名同一套。
  @Prop icon: string = '';
  // 文字字形（如 '⋯' '↻' '?'）；非空时优先于 svg。
  @Prop glyph: string = '';
  @Prop label: string = '';
  // 无障碍「会怎样」：与 label（是什么）配对，见 Accessibility.ets 的文案规则。
  // 顺带解决一个取证缺口：uitest dumpLayout 不导出 accessibilityText，
  // 只导出 description（desc 字段），纯图标按钮因此无法被脚本按文案定位。
  @Prop hint: string = '';
  onPress: () => void = () => {};

  build() {
    Column() {
      if (this.glyph !== '') {
        Text(this.glyph)
          .fontSize(FS_TITLE)
          .fontColor(INK)
      } else {
        Image($rawfile(`icons/ic_${this.icon}_ink.svg`))
          .width(ICON_SIZE)
          .height(ICON_SIZE)
          .draggable(false)
      }
    }
    .width(NAV_ICON_BTN_H)
    .height(NAV_ICON_BTN_H)
    .borderRadius(NAV_ICON_BTN_RADIUS)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onPress();
    })
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(this.label)
    .accessibilityDescription(this.hint)
    .accessibilityLevel('yes')
  }
}
