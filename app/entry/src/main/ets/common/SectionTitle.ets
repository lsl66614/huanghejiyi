// entry/src/main/ets/common/SectionTitle.ets
// 区块/页级标题：FS_PAGE 30 展示体 + 可选副题。
//
// 为什么没有 40×4 短杠（2026-11-05 全站撤除）：
// 短杠是「标题下画一道横线」的装饰件，落在标题与正文之间。它不带任何
// 信息——标题本身已经说明了这是什么——却在每一页的标题下都留一道，
// 于是全站每个界面都顶着同一道黑线。实测截图里它读作排版事故：
// 顶部「我的收藏」下那道黑线与下面的筛选胶囊行里的一条边线挤在一起，
// 页面像是被划了一道。信息量最低的装饰件在全站铺开，就是全站最显眼的
// 噪音源。撤掉后标题靠字号与字重自己立住，页面反而干净。
import {
  FONT_DISPLAY, FS_CAPTION, FS_PAGE, INK, LH_CAPTION, LH_PAGE,
  SUB, WT_DISPLAY, WT_REGULAR
} from './DesignTokens';

@Component
export struct SectionTitle {
  @Prop title: string = '';
  // 可选副题（如「42 处已归层」）。空串不渲染。
  @Prop caption: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(FS_PAGE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .lineHeight(LH_PAGE)
        .fontColor(INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.caption !== '') {
        Text(this.caption)
          .fontSize(FS_CAPTION)
          .fontWeight(WT_REGULAR)
          .lineHeight(LH_CAPTION)
          .fontColor(SUB)
      }
    }
    .alignItems(HorizontalAlign.Start)
    // 不给 width('100%')：页头常与 Blank+按钮同排（NoteCenterPage），
    // 百分比宽度会吃掉整行、把按钮挤出屏。让标题按内容收，剩余交给 Blank。
  }
}
