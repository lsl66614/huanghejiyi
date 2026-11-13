// entry/src/main/ets/common/MiniProfile.ets
// 发掘进度条：卡片底部那排 6 格小段（设计稿①年代卡 Mini Profile）。
//
// 一段 = 一个遗址的研读完成态。已读实色、未读 50% 透明灰。
// 这是「发掘深度」在卡片级的最小表达——不需要数字，扫一眼格子
// 就知道这层挖了几个人。
//
// 为什么不用进度环（旧制式是 34×34 圆环 + 数字）：圆环把 34vp 的
// 净空让给一个两位数的百分比，而百分比在 6 格条面前是冗余信息。
// 条的每一格是一个站点，读屏也只需一句"已研读 2 处，共 6 处"。
import { eraColor } from './EraTheme';
import { HAIR_PAD, LINE_HAIR, RADIUS_SEG_10 } from './DesignTokens';

@Component
export struct MiniProfile {
  // 总格数（该年代的站点数）
  total: number = 0;
  // 已完成格数（五段落全读完的站点数）
  done: number = 0;
  // 年代键，决定已完成格的颜色
  era: string = '';

  build() {
    Row({ space: HAIR_PAD }) {
      ForEach(this.idxList(), (i: number) => {
        Row()
          .layoutWeight(1)
          .height(10)
          .borderRadius(RADIUS_SEG_10)
          .backgroundColor(i < this.done ? eraColor(this.era) : LINE_HAIR)
          .opacity(i < this.done ? 1 : 0.5)
      }, (i: number) => `${i}`)
    }
    .width('100%')
    .height(this.total > 0 ? 10 : 0)
  }

  // build() 根节点前不能写语句（PITFALLS #6），索引数组改由方法生成。
  private idxList(): number[] {
    const idxs: number[] = [];
    for (let i = 0; i < this.total; i++) {
      idxs.push(i);
    }
    return idxs;
  }
}
