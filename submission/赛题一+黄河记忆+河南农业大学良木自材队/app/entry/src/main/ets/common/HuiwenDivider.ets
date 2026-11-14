// entry/src/main/ets/common/HuiwenDivider.ets
// 回纹分隔：设计稿①的「回纹分隔 / 回纹收尾」。
//
// 构成：两侧发丝线 + 中间三个 16vp 回纹（`M2 2 L14 2 L14 14 L6 14
// L6 6 L10 6 L10 10`，stroke #6E675E，1.2vp 粗）。
// 回纹是雷纹的构成单元——「回」字形的螺旋，在青铜器与陶器上是
// 最古老的连续纹样之一。用它做分隔，比一根光杆线多一层文化指认，
// 又比具象图案克制（不抢内容）。
//
// 为什么用 Shape 抽象而不是 SVG 资源：path 只有一条折线，
// Shape + Path 在 ArkUI 里是原生能力，多一个 rawfile 文件反而难维护。
import { LINE_HAIR, SUB } from './DesignTokens';

@Component
export struct HuiwenDivider {
  // 上下留白；设计稿容器高 20vp
  bandH: number = 20;

  build() {
    Row({ space: 8 }) {
      Row()
        .layoutWeight(1)
        .height(1)
        .backgroundColor(LINE_HAIR)

      // 三个回纹并列
      Row({ space: 6 }) {
        ForEach([0, 1, 2], (_: number) => {
          Stack() {
            // 用 Shape 画回纹：16vp 见方，path 见文件头注释
            Path()
              .width(16)
              .height(16)
              .commands('M2 2 L14 2 L14 14 L6 14 L6 6 L10 6 L10 10')
              .stroke(SUB)
              .strokeWidth(1.2)
              .strokeLineJoin(LineJoinStyle.Miter)
              .fillOpacity(0)
          }
        }, (i: number) => `${i}`)
      }
      .height(16)

      Row()
        .layoutWeight(1)
        .height(1)
        .backgroundColor(LINE_HAIR)
    }
    .width('100%')
    .height(this.bandH)
    .justifyContent(FlexAlign.Center)
  }
}
