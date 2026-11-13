// entry/src/main/ets/common/StratumCrumb.ets
// 层位面包屑：回答「我在第几层」。修复计划 §6.3。
//
// 为什么需要它：全站跳转是数据驱动的（共出器物、同脉络推荐……），
// 单条边都合理，连起来却没有目录。面包屑给每个内容页一个显式层位——
// 地表 › 地层 › 遗址 › 展品，返回键的每一次按压都在重放这条下降线。
//
// 小字一律 FONT_SANS：12pt 下展示体的「宋」会读成「市」（真机实测，
// 见 chips 同因），年代名恰好在语料里高频出现。
// 当前层（最深一段）用 INK，祖先段用 SUB——层级不靠颜色发明，
// 只复用令牌表里已有的两级。
import { eraColor } from './EraTheme';
import {
  FONT_SANS, FS_CAPTION, INK, RADIUS_DOT_6, SUB, WT_REGULAR
} from './DesignTokens';

@Component
export struct StratumCrumb {
  // 年代键（决定色点颜色）；与 eraLabel 成对给出。
  @Prop era: string = '';
  @Prop eraLabel: string = '';
  @Prop siteName: string = '';
  @Prop relicName: string = '';

  private current(): string {
    if (this.relicName !== '') { return this.relicName; }
    if (this.siteName !== '') { return this.siteName; }
    if (this.eraLabel !== '') { return this.eraLabel; }
    return '地表';
  }

  private colorOf(seg: string): string {
    return seg === this.current() ? INK : SUB;
  }

  build() {
    Row({ space: 6 }) {
      Text('地表')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SANS)
        .fontWeight(WT_REGULAR)
        .fontColor(this.colorOf('地表'))
      if (this.eraLabel !== '') {
        Text('›')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontColor(SUB)
        Row()
          .width(6)
          .height(6)
          .borderRadius(RADIUS_DOT_6)
          .backgroundColor(eraColor(this.era))
        Text(this.eraLabel)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontWeight(WT_REGULAR)
          .fontColor(this.colorOf(this.eraLabel))
      }
      if (this.siteName !== '') {
        Text('›')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontColor(SUB)
        Text(this.siteName)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontWeight(WT_REGULAR)
          .fontColor(this.colorOf(this.siteName))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      if (this.relicName !== '') {
        Text('›')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontColor(SUB)
        Text(this.relicName)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontWeight(WT_REGULAR)
          .fontColor(this.colorOf(this.relicName))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(VerticalAlign.Center)
    .accessibilityText(`层位：地表 ${this.eraLabel} ${this.siteName} ${this.relicName}，当前 ${this.current()}`)
  }
}
