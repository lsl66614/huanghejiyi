// entry/src/main/ets/common/SegmentTab.ets
// 胶囊式切换器（筛选 / 模式切换 / 视图切换）的唯一实现。
//
// 为什么要抽（制式整改清单 §0）：同一个语义此前在每个页面各写一遍——
// NoteCenterPage 的 scopeChip 是白底发丝 + 选中 INK 实底（正确），
// 同页的 tagChip 却是未选即 ACCENT 描边、选中 ACCENT 实底（错误），
// 两行筛选并排时用户看不出哪一行才是"当前"。SyncPage 的模式切换
// 又是纯文字、只靠字色区分。漂移是逐页手写的必然结果。
//
// 制式（清单 §1，参数钉死，不许页内覆盖）：
//   高度恒 CHIP_H；选中 = INK 实底 + SURFACE_CARD 字；
//   未选 = SURFACE_CARD 底 + HAIR/LINE_HAIR 描边 + BODY 字。
//   整组左对齐。
//
// 一条硬约束（清单 §1.1）：**未选中态一律不许上 ACCENT**。
// 未选中=白底+发丝+中性字，选中才上色；否则看着"全被选中了"，
// 真正的选中态反而分不出来。
//
// 为什么是 @Component 而不是 @Builder：@Builder 参数按值传递，
// 父组件的 selected 变化不会触发内部重渲染（清单 §3.2，
// CabinetCell / MetricCell 都栽过一次）。
import {
  BODY, CHIP_H, CHIP_RADIUS, FONT_SANS, FS_CAPTION, HAIR, INK,
  LINE_HAIR, ROW_GAP, SURFACE_CARD, WT_BOLD, WT_REGULAR
} from './DesignTokens';
import { focusRing } from './Accessibility';
import { PressScale } from './PressScale';

export class SegmentItem {
  key: string = '';
  label: string = '';
  // count < 0 表示这一项不带计数（如模式切换），不渲染数字。
  count: number = -1;
}

@Component
export struct SegmentTab {
  @Prop items: SegmentItem[] = [];
  @Prop selected: string = '';
  // compact = true：小一号的胶囊（28 高 / 11pt），只给「同排还有别的控件」用。
  // 例：档案页把「视图」切换折进「收藏 3/3 条」那一行，标准 32 高会把该行撑爆。
  @Prop compact: boolean = false;
  onPick: (key: string) => void = () => {};

  private textOf(it: SegmentItem): string {
    return it.count >= 0 ? `${it.label} ${it.count}` : it.label;
  }

  private speakOf(it: SegmentItem): string {
    const base: string = it.count >= 0 ? `${it.label}，${it.count} 条` : it.label;
    return this.selected === it.key ? `${base}，已选中` : base;
  }

  build() {
    Row({ space: ROW_GAP }) {
      ForEach(this.items, (it: SegmentItem) => {
        PressScale() {
          Text(this.textOf(it))
            .fontSize(this.compact ? 11 : FS_CAPTION)
            .fontFamily(FONT_SANS)
            .fontWeight(this.selected === it.key ? WT_BOLD : WT_REGULAR)
            .fontColor(this.selected === it.key ? SURFACE_CARD : BODY)
            .height(this.compact ? 28 : CHIP_H)
            .padding({ left: this.compact ? 10 : 12, right: this.compact ? 10 : 12 })
            .backgroundColor(this.selected === it.key ? INK : SURFACE_CARD)
            .border({ width: HAIR, color: this.selected === it.key ? INK : LINE_HAIR })
            .borderRadius(CHIP_RADIUS)
            .onClick(() => {
              this.onPick(it.key);
            })
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText(this.speakOf(it))
            .accessibilityLevel('yes')
            .accessibilitySelected(this.selected === it.key)
        }
      }, (it: SegmentItem) => it.key)
    }
    .justifyContent(FlexAlign.Start)
  }
}
