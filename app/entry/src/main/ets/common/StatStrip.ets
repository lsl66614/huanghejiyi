// entry/src/main/ets/common/StatStrip.ets
// 统计条：四边发丝 + 圆角 + 页边留边的均分列（整改清单 §1）。
//
// 为什么抽件：首页档案概览 / 同步三要素 / 我的统计 / DetailPage 三联数据卡
// 是同一种东西的四种写法——有的只有上下发丝（通栏横带），有的没左右留边。
// 列**居中**是刻意的：左对齐时「42」和「104」宽度不同，均分列里会读出
// 忽大忽小的空档（真机实测）。
//
// 数字用 FS_TITLE + FONT_DISPLAY：统计要压过标签一头，否则不成层级。
//
// 第一格可挂一条进度线（progress / progressLabel / progressValue）：
// 同步页要表达「正在搬数据」。此前它是一条通栏 3px 横贯屏幕的线，
// 读作把屏幕切成两半的划痕；挂到数字正下方、宽度不超那一格之后，
// 才读得出「这一格在动」。progress > 0 时才渲染：静息态一条永不
// 前进的线只是横痕。
import {
  ACCENT, CARD_PAD, FONT_DISPLAY, FONT_SERIF, FS_CAPTION, FS_TITLE, HAIR,
  INK, LINE_HAIR, PAGE_PAD_X, RADIUS_CARD_LG, RADIUS_TRACK_3, SUB,
  SURFACE_CARD, WT_DISPLAY
} from './DesignTokens';

export class StatItem {
  label: string = '';
  value: string = '';
  // 这一格是否带进度线。progress >= 0 时在该格数字下方画一条细线。
  progress: number = -1;
  constructor(label: string, value: string, progress: number = -1) {
    this.label = label;
    this.value = value;
    this.progress = progress;
  }
}

@Component
export struct StatStrip {
  @Prop items: StatItem[] = [];
  // 页边距归属：默认自带左右 PAGE_PAD_X（独立使用场景，直接贴页边）。
  // 嵌入到已有横向内衬的容器里时（如档案页研读分段，外层已加 padding），
  // 必须置 false，否则双重缩进——卡片比同组的节标题右移一个 PAGE_PAD_X，
  // 读作没对齐（实测截图）。
  @Prop ownMargin: boolean = true;

  build() {
    Row({ space: 12 }) {
      ForEach(this.items, (it: StatItem) => {
        Column({ space: 4 }) {
          Text(it.value)
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text(it.label)
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
          // 只在 progress > 0 时渲染：静息态一条永不前进的线只是横痕。
          if (it.progress > 0) {
            Row() {
              Row()
                .height(3)
                .borderRadius(RADIUS_TRACK_3)
                .backgroundColor(ACCENT)
                .width(`${it.progress}%`)
            }
            .width('100%')
            .height(3)
            .borderRadius(RADIUS_TRACK_3)
            .backgroundColor(LINE_HAIR)
          }
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .accessibilityText(`${it.label} ${it.value}`)
        // 键必须带上值：只用 label 时三格的 label 恒定（同步进度/最后同步/
        // 冲突记录），值变了 ForEach 判定键未变、不重建单元格——同步跑完
        // 进度仍停在 0%、最后同步仍停在「—」（2026-11-05 实测）。
      }, (it: StatItem) => `${it.label}|${it.value}|${it.progress}`)
    }
    .width('100%')
    .padding(CARD_PAD)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .margin(this.ownMargin ? { left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 12 } : { bottom: 12 })
  }
}
