// entry/src/main/ets/common/UnderlineTabs.ets
// 页签（Material 主页签制式）：表达「这个页里有哪几个内容目的地」。
//
// 为什么不能继续用胶囊（SegmentTab）——两条外部依据 + 一条自己的实测：
//   1. Segmented control 的正确定位是「同一份数据的视图切换」，
//      2–5 个互斥项；把它用于导航或页面级模式切换是典型误用
//      （"navigation disguised as view switching"）。
//      https://www.letsgroto.com/blog/segmented-control-ui
//   2. Material 主页签就放在内容区顶部、顶栏正下方，用来表达主要目的地；
//      嵌套层才用 secondary tab bar。
//      https://m3.material.io/components/tab-bar/overview
//   3. 实测：档案页三行控件（分段 / 视图切换 / 标签筛选）全都写成
//      「黑底选中胶囊」，看起来是三排同类控件，读者无法判断哪一行是导航。
//      页签不带盒子，只用字重与下划线，与胶囊在语法上分得开。
//
// 制式（对齐 2026-11-04 设计稿「档案」页，参数钉死，页内不许覆盖）：
//   一行左起，项间距 24；项高 = 文字 + 下内衬 10；
//   选中＝INK 字 + 15pt 半粗 + 字下 2px INK 下划线；
//   未选＝SUB 字 + 15pt 常规；
//   整行下沿一条 1px 发丝（下划线压在它上方）。
import { FS_ITEM, INK, LINE_HAIR, SUB, WT_BOLD, WT_REGULAR } from './DesignTokens';
import { focusRing } from './Accessibility';

export class TabItem {
  key: string = '';
  label: string = '';
}

@Component
export struct UnderlineTabs {
  @Prop items: TabItem[] = [];
  @Prop selected: string = '';
  // hairline = true 时整行下沿加一条发丝，把页签与内容分开。
  // 页签上方已有别的横线时传 false：同一屏出现「刊头短杠 + 页签下划线
  // + 行下沿发丝」三条横线密集，读作划痕而不是层级。
  @Prop hairline: boolean = true;
  onPick: (key: string) => void = () => {};

  build() {
    Column() {
      Row({ space: 24 }) {
        ForEach(this.items, (it: TabItem) => {
          Text(it.label)
            .fontSize(FS_ITEM)
            .fontWeight(this.selected === it.key ? WT_BOLD : WT_REGULAR)
            .fontColor(this.selected === it.key ? INK : SUB)
            .maxLines(1)
            .padding({ bottom: 10 })
            // 选中项字下 2px 下划线；未选保留同尺寸透明下划线，切换时文字不跳
            .border({
              width: { bottom: 2 },
              color: this.selected === it.key ? INK : Color.Transparent
            })
            .onClick(() => {
              this.onPick(it.key);
            })
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText(this.selected === it.key ? `${it.label}，已选中` : it.label)
            .accessibilityLevel('yes')
            .accessibilitySelected(this.selected === it.key)
        }, (it: TabItem) => it.key)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)

      // 整行下沿发丝：页签与内容之间的分界，下划线压在它上面
      if (this.hairline) {
        Row()
          .width('100%')
          .height(1)
          .backgroundColor(LINE_HAIR)
      }
    }
    .width('100%')
  }
}
