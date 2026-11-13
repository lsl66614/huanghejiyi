// entry/src/main/ets/common/LayerBadge.ets
// 层号章：设计稿「展签色标」的最小载体。
//
// 为什么是白底 + 层色圆点 + 发丝描边，而不是层色实底：
// 层色实底会把 6 个年代的卡片切成 6 块色板，白盒的"照片是最饱和的东西"
// 就不成立了。章是标签，不是装饰块——它只回答"这是第几层、什么年代"。
//
// mono 字体的层号（L1/L2）是刻意的：层号是数据不是文学，
// 等宽数字在 6 个章并排时宽度一致，读起来像编号而不是像句子。
import { eraColor } from './EraTheme';
import {
  FONT_MONO, FS_CAPTION, HAIR, INK, LINE_HAIR, ON_DARK_BG, ON_DARK_LINE,
  ON_DARK_TEXT_ALT, RADIUS_SM, RADIUS_DOT_6, SUB, SURFACE_CARD, WT_MEDIUM
} from './DesignTokens';

@Component
export struct LayerBadge {
  // 层号显示文本，如 'L1'、'第 3 层'。空串时只画色点 + 年代名。
  layerCode: string = '';
  // 年代键（yangshao/longshan/...），决定圆点颜色。
  era: string = '';
  // 年代名，如 '仰韶'。与 layerCode 至少给一个。
  eraLabel: string = '';
  // 深底变体：RelicPage 展柜内用深底 + 深发丝。
  onDark: boolean = false;

  build() {
    Row({ space: 6 }) {
      if (this.layerCode !== '') {
        Text(this.layerCode)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontWeight(WT_MEDIUM)
          .fontColor(this.onDark ? ON_DARK_TEXT_ALT : INK)
      }
      // 层色圆点：直径 6vp。尺寸再小就不是"点"而是"像素噪点"。
      Row()
        .width(6)
        .height(6)
        .borderRadius(RADIUS_DOT_6)
        .backgroundColor(eraColor(this.era))
      if (this.eraLabel !== '') {
        Text(this.eraLabel)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
      }
    }
    .padding({ left: 10, right: 10, top: 6, bottom: 6 })
    .borderRadius(RADIUS_SM)
    .backgroundColor(this.onDark ? ON_DARK_BG : SURFACE_CARD)
    .border({
      width: HAIR,
      color: this.onDark ? ON_DARK_LINE : LINE_HAIR
    })
  }
}
