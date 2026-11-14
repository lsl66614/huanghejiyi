// entry/src/main/ets/common/HuangheSeal.ets
// 黄河水文四字印：设计稿①页头的 64×64 印章。
//
// 构成（设计稿实测）：
//   印面 88×88 白底 + 2px ACCENT 赭红描边 + 6px 圆角（外框）
//   四字 2×2 排布，每字 44×44 格、38px ZCOOL XiaoWei
//   黄/河/水 三字赭红 #9C4A2F，纹 一字宋色 #7F97A4
//
// 为什么「纹」用宋色：四字印是「黄河水文」——前三字是本体（黄河水），
// 第四字「纹」指水纹/纹理，用宋代的瓷青釉色收尾，让印面本身
// 成为一条微缩的年代轴（赭红=仰韶陶 → 宋青=宋瓷）。
// 这是设计稿最巧的一笔，实现时不许为了"统一"把它也改成赭红。
import {
  ACCENT, FONT_DISPLAY, SEAL_BORDER, SEAL_CELL, SEAL_FACE, SEAL_FONT,
  SEAL_RADIUS, SEAL_SIZE, SURFACE_CARD, WT_DISPLAY
} from './DesignTokens';
import { eraColor } from './EraTheme';

@Component
export struct HuangheSeal {
  // 印面尺寸；设计稿容器 64vp（印面 88vp 溢出裁切）
  sealBox: number = SEAL_SIZE;

  @Builder
  sealChar(ch: string, color: string) {
    // 单字格：44×44，38px ZCOOL 居中
    Text(ch)
      .fontSize(SEAL_FONT)
      .fontFamily(FONT_DISPLAY)
      .fontWeight(WT_DISPLAY)
      .fontColor(color)
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 印面：白底 + 赭红描边
      Row()
        .width(SEAL_FACE)
        .height(SEAL_FACE)
        .backgroundColor(SURFACE_CARD)
        .border({ width: SEAL_BORDER, color: ACCENT })
        .borderRadius(SEAL_RADIUS)

      // 四字 2×2
      Column({ space: 0 }) {
        Row({ space: 0 }) {
          this.sealChar('黄', ACCENT)
          this.sealChar('河', ACCENT)
        }
        Row({ space: 0 }) {
          this.sealChar('水', ACCENT)
          this.sealChar('纹', eraColor('song'))
        }
      }
      .width(SEAL_FACE)
      .height(SEAL_FACE)
    }
    .width(this.sealBox)
    .height(this.sealBox)
    .clip(true)
  }
}
