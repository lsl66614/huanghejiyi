// entry/src/main/ets/common/DepthRuler.ets
// 导览尺：DetailPage 五节目录用。
//
// 每节一格，已读实色、未读发丝灰，格下挂节名。回答"这篇我读到哪了"。
// 为什么不用圆环（旧制式）：圆环把百分比当主角，但百分比本身不是信息——
// "62%"对用户没有意义，"已读 3 节 / 共 5 节"才有。尺的每一格就是一节，
// 未读的空格就是剩下的路程。
import { eraColor } from './EraTheme';
import {
  FS_CAPTION, INK, LINE_HAIR, RADIUS_TRACK_3, ROW_GAP, SUB
} from './DesignTokens';
import { focusRing } from './Accessibility';

// 一段可点击的尺格 + 节名
export interface RulerSeg {
  key: string;
  label: string;
  done: boolean;
}

@Component
export struct DepthRuler {
  // 尺格列表；空列表时组件不渲染。
  // 必须 @Prop：普通成员只在创建时赋值，父页勾选「已研读」后
  // 尺子不会跟着变实色（实测过——勾选后整尺仍是发丝灰）。
  @Prop segs: RulerSeg[] = [];
  // 年代键，决定已完成格的颜色
  @Prop era: string = '';
  // 点击某节（跳转到对应 section）
  onSegTap: (key: string) => void = (_: string) => {};

  build() {
    // 单一根节点：空列表时整尺不占位（Blank 也要包在一个容器里，
    // 否则 build 出现两个根节点，编译报 10905210）。
    Column() {
      if (this.segs.length === 0) {
        Blank()
      } else {
        Row({ space: ROW_GAP }) {
          ForEach(this.segs, (seg: RulerSeg) => {
            Column({ space: 6 }) {
              Row()
                .width('100%')
                .height(3)
                .borderRadius(RADIUS_TRACK_3)
                .backgroundColor(seg.done ? eraColor(this.era) : LINE_HAIR)
              Text(seg.label)
                .fontSize(FS_CAPTION)
                .fontColor(seg.done ? INK : SUB)
                .maxLines(1)
            }
            .layoutWeight(1)
            .onClick(() => this.onSegTap(seg.key))
            .focusable(true)
            .focusBox(focusRing())
          }, (seg: RulerSeg) => `${seg.key}|${seg.done ? '1' : '0'}`)
        }
        .width('100%')
      }
    }
    .width('100%')
  }
}
